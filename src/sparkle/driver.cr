require "./parser"
require "./rules"
require "./lowerer"
require "./diagnostics"
require "./ponyc/compiler"

module Sparkle
  module Driver
    METHOD_WITHOUT_CALL = "can't reference a method without calling it"
    MAX_ROUNDS          = 50
    PONYC_RELATIVES     = [".tools/ponyc/bin/ponyc", "vendor/ponyc/build/release/ponyc"]
    INSTALLED_PONY_HOME = "lib/pony"

    # Formats a parse error as `file:line:col: message`, the source line and a caret.
    def self.format_error(path : String, source : String, err : ParseError) : String
      line = source.lines(chomp: true)[err.line - 1]? || ""
      "#{path}:#{err.line}:#{err.col}: #{err.message}\n#{line}\n#{Diagnostics.caret_padding(line, err.col)}^\n"
    end

    # The Pony installation whose standard library and runtime `build` uses:
    # the one holding `$SPARKLE_PONYC`, else `lib/pony` beside an installed
    # `bin/sparkle` (see `make install`), else the one holding the `ponyc`
    # found by `find_ponyc`.
    def self.find_pony_home(env_value : String? = ENV["SPARKLE_PONYC"]?, exe_path : String? = Process.executable_path, cwd : String = Dir.current) : String?
      if exe_path && (env_value.nil? || env_value.empty?)
        installed = File.join(File.dirname(File.dirname(File.expand_path(exe_path))), INSTALLED_PONY_HOME)
        return installed if File.directory?(File.join(installed, "packages", "builtin"))
      end
      find_ponyc(env_value, exe_path, cwd).try { |ponyc| File.dirname(File.dirname(ponyc)) }
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
    private record Project, files : Array(String), package : String, sources : Array(String), programs : Array(Program), home : String, primed : Hash(String, Set(String)), predicates : Rules::Predicates

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
      home = find_pony_home
      unless home
        err.puts "sparkle: ponyc not found (set SPARKLE_PONYC, run `make ponyc`, or put ponyc on PATH)"
        return
      end
      Project.new(files, package, sources, programs, home, Rules.primed_params(programs), Rules.enum_predicates(programs))
    end

    private def self.lower_files(tree : Ponyc::Tree, files : Array(String), sources : Array(String), programs : Array(Program), calls : Hash(String, Set({Int32, Int32})), primed : Hash(String, Set(String)), predicates : Rules::Predicates, & : Int32 -> Nil) : Nil
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

    private def self.build_tree(project : Project, out_dir : String?, err : IO) : {Int32, String?}
      current = 0
      begin
        calls = tree_calls(project) { |i| current = i }
        out_dir ||= File.join(".sparkle", "bin")
        Dir.mkdir_p(out_dir)
        ok, errors = Ponyc.compile_tree(out_dir, project.package, project.home) do |tree|
          lower_project(tree, project, calls) { |i| current = i }
        end
        err.print Diagnostics.rewrite(errors, names: Rules.enum_names(project.programs))
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
    def self.tree_calls(files : Array(String), sources : Array(String), programs : Array(Program), home : String, primed : Hash(String, Set(String)) = Rules.primed_params(programs), predicates : Rules::Predicates = Rules.enum_predicates(programs), & : Int32 -> Nil) : Hash(String, Set({Int32, Int32}))
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
    # compiler, against the standard library of the Pony installation found
    # by `find_pony_home`. It lowers to ponyc's AST.
    # Returns the exit code and the binary's path, which lands in `out_dir`.
    def self.build(path : String, out_dir : String?, err : IO = STDERR) : {Int32, String?}
      project = load_project(path, err) || return {1, nil}
      build_tree(project, out_dir, err)
    end
  end
end
