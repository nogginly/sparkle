require "./parser"
require "./emitter"
require "./lowerer"
require "./diagnostics"
require "./ponyc/compiler"

module Sparkle
  # Result of translating one Sparkle source.
  record Translation, source : String, program : Program, pony : String, map : SourceMap

  module Driver
    METHOD_WITHOUT_CALL = "can't reference a method without calling it"
    MAX_ROUNDS          = 50
    PONYC_RELATIVES     = [".tools/ponyc/bin/ponyc", "vendor/ponyc/build/release/ponyc"]

    def self.translate(source : String) : Translation
      program = Parser.parse(source)
      pony, map = Emitter.emit(program)
      Translation.new(source, program, pony, map)
    end

    # Formats a parse error as `file:line:col: message`, the source line and a caret.
    def self.format_error(path : String, source : String, err : ParseError) : String
      line = source.lines(chomp: true)[err.line - 1]? || ""
      "#{path}:#{err.line}:#{err.col}: #{err.message}\n#{line}\n#{Diagnostics.caret_padding(line, err.col)}^\n"
    end

    # Locates ponyc: `$SPARKLE_PONYC`, then `.tools/ponyc`, then the vendored
    # build, each searched upward from the executable and the working
    # directory, then `PATH`.
    def self.find_ponyc(env_value : String? = ENV["SPARKLE_PONYC"]?, exe_path : String? = Process.executable_path, cwd : String = Dir.current) : String?
      if env_value && !env_value.empty?
        return env_value
      end
      roots = [] of String
      if exe_path
        roots << File.dirname(File.dirname(File.expand_path(exe_path)))
      end
      roots << File.expand_path(cwd)
      PONYC_RELATIVES.each do |relative|
        roots.each do |root|
          dir = root
          loop do
            candidate = File.join(dir, relative)
            return candidate if File.file?(candidate) && File::Info.executable?(candidate)
            parent = File.dirname(dir)
            break if parent == dir
            dir = parent
          end
        end
      end
      Process.find_executable("ponyc")
    end

    # Everything `build` and `tree_text` need once the sources parse.
    private record Project, files : Array(String), package : String, sources : Array(String), programs : Array(Program), home : String, primed : Hash(String, Set(String)), predicates : Emitter::Predicates

    # Parses the Sparkle files at `path` and finds ponyc; nil, with the
    # reason on `err`, if either fails.
    private def self.load_project(path : String, err : IO) : Project?
      files, package = sources_for(path)
      if files.empty?
        err.puts "sparkle: no .spk files in #{path}"
        return
      end
      sources = files.map { |file| File.read(file) }
      programs = [] of Program
      files.each_with_index do |file, i|
        programs << Parser.parse(sources[i])
      rescue e : ParseError
        err.print format_error(file, sources[i], e)
        return
      end
      ponyc = find_ponyc
      unless ponyc
        err.puts "sparkle: ponyc not found (set SPARKLE_PONYC, run `make ponyc`, or put ponyc on PATH)"
        return
      end
      Project.new(files, package, sources, programs, File.dirname(File.dirname(ponyc)), Emitter.primed_params(programs), Emitter.enum_predicates(programs))
    end

    private def self.lower_files(tree : Ponyc::Tree, files : Array(String), sources : Array(String), programs : Array(Program), calls : Hash(String, Set({Int32, Int32})), primed : Hash(String, Set(String)), predicates : Emitter::Predicates, & : Int32 -> Nil) : Nil
      files.each_with_index do |file, i|
        yield i
        Lowerer.new(tree, calls[file]? || Set({Int32, Int32}).new, primed, predicates).lower(programs[i], file, sources[i])
      end
    end

    private def self.lower_project(tree : Ponyc::Tree, project : Project, calls : Hash(String, Set({Int32, Int32})), & : Int32 -> Nil) : Nil
      lower_files(tree, project.files, project.sources, project.programs, calls, project.primed, project.predicates) { |i| yield i }
    end

    # The lowered tree of the package at `path`, as `build` compiles it,
    # printed as `ponyc --astmodule` prints one.
    def self.tree_text(path : String, err : IO) : {Int32, String?}
      project = load_project(path, err) || return {1, nil}
      current = 0
      begin
        calls = tree_calls(project) { |i| current = i }
        text = Ponyc.tree_text(project.home) do |tree|
          lower_project(tree, project, calls) { |i| current = i }
        end
        {0, text}
      rescue e : ParseError
        err.print format_error(project.files[current], project.sources[current], e)
        {1, nil}
      end
    end

    # Builds by lowering to ponyc's AST, without writing Pony text.
    private def self.build_tree(project : Project, out_dir : String?, err : IO) : {Int32, String?}
      current = 0
      begin
        calls = tree_calls(project) { |i| current = i }
        out_dir ||= File.join(".sparkle", "bin")
        Dir.mkdir_p(out_dir)
        ok, errors = Ponyc.compile_tree(out_dir, project.package, project.home) do |tree|
          lower_project(tree, project, calls) { |i| current = i }
        end
        err.print Diagnostics.rewrite(errors, [] of GeneratedFile, names: Emitter.enum_names(project.programs))
        {ok ? 0 : 1, File.join(out_dir, project.package)}
      rescue e : ParseError
        err.print format_error(project.files[current], project.sources[current], e)
        {1, nil}
      end
    end

    private def self.tree_calls(project : Project, & : Int32 -> Nil) : Hash(String, Set({Int32, Int32}))
      tree_calls(project.files, project.sources, project.programs, project.home, project.primed, project.predicates) { |i| yield i }
    end

    # The positions, per file, of the bare `x.name`s the type checker reports
    # as methods: lowers, type-checks and adds positions until none is new.
    # Yields the index of each file before lowering it.
    def self.tree_calls(files : Array(String), sources : Array(String), programs : Array(Program), home : String, primed : Hash(String, Set(String)) = Emitter.primed_params(programs), predicates : Emitter::Predicates = Emitter.enum_predicates(programs), & : Int32 -> Nil) : Hash(String, Set({Int32, Int32}))
      calls = Hash(String, Set({Int32, Int32})).new
      MAX_ROUNDS.times do
        found = Ponyc.check_tree(home) do |tree|
          lower_files(tree, files, sources, programs, calls, primed, predicates) { |i| yield i }
        end
        grown = false
        found.each do |file, line, column, message|
          next unless message == METHOD_WITHOUT_CALL && files.includes?(file)
          grown = true if (calls[file] ||= Set({Int32, Int32}).new).add?({line, column})
        end
        break unless grown
      end
      calls
    end

    # The Sparkle files and package name for a build path.
    def self.sources_for(path : String) : {Array(String), String}
      if File.directory?(path)
        files = Dir.glob(File.join(path, "*.spk")).sort
        {files, File.basename(File.expand_path(path))}
      else
        {[path], File.basename(File.dirname(File.expand_path(path)))}
      end
    end

    # Compiles the `.spk` file or package at `path` with the linked-in Pony
    # compiler, against the standard library of the Pony installation that
    # holds the `ponyc` found by `find_ponyc`. It lowers to ponyc's AST,
    # unless `SPARKLE_TEXT=1` asks for the text path, which writes
    # `.sparkle/<package>/*.pony`. Returns the exit code and the binary's
    # path, which lands in `out_dir`.
    def self.build(path : String, out_dir : String?, err : IO = STDERR) : {Int32, String?}
      project = load_project(path, err) || return {1, nil}
      return build_tree(project, out_dir, err) unless ENV["SPARKLE_TEXT"]? == "1"
      build_text(project, out_dir, err)
    end

    private def self.build_text(project : Project, out_dir : String?, err : IO) : {Int32, String?}
      files, sources, programs, home = project.files, project.sources, project.programs, project.home
      primed, predicates = project.primed, project.predicates
      gen_dir = File.join(".sparkle", project.package)
      Dir.mkdir_p(gen_dir)
      Dir.glob(File.join(gen_dir, "*.pony")).each { |stale| File.delete(stale) }
      names = Emitter.enum_names(programs)
      calls = Hash(String, Set({Int32, Int32})).new
      generated = [] of GeneratedFile
      MAX_ROUNDS.times do
        generated = [] of GeneratedFile
        files.each_with_index do |file, i|
          source = sources[i]
          begin
            pony, map = Emitter.emit(programs[i], primed, calls[file]? || Set({Int32, Int32}).new, predicates)
          rescue e : ParseError
            err.print format_error(file, source, e)
            return {1, nil}
          end
          pony_path = File.join(gen_dir, File.basename(file, ".spk") + ".pony")
          File.write(pony_path, pony)
          generated << GeneratedFile.new(pony_path, file, map, source)
        end
        grown = false
        Ponyc.check(gen_dir, home).each do |file, line, column, message|
          next unless message == METHOD_WITHOUT_CALL
          target = generated.find { |candidate| candidate.pony_path == File.expand_path(file) }
          next unless target
          position = target.map.lookup(line, column)
          next unless position
          grown = true if (calls[target.spk_path] ||= Set({Int32, Int32}).new).add?(position)
        end
        break unless grown
      end
      out_dir ||= File.join(".sparkle", "bin")
      Dir.mkdir_p(out_dir)
      ok, errors = Ponyc.compile(gen_dir, out_dir, project.package, home)
      err.print Diagnostics.rewrite(errors, generated, names: names)
      {ok ? 0 : 1, File.join(out_dir, project.package)}
    end
  end
end
