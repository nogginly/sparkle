require "./parser"
require "./emitter"
require "./diagnostics"
require "./ponyc/compiler"

module Sparkle
  # Result of translating one Sparkle source.
  record Translation, source : String, program : Program, pony : String, map : SourceMap

  module Driver
    PONYC_RELATIVES = [".tools/ponyc/bin/ponyc", "vendor/ponyc/build/release/ponyc"]

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

    # The Sparkle files and package name for a build path.
    def self.sources_for(path : String) : {Array(String), String}
      if File.directory?(path)
        files = Dir.glob(File.join(path, "*.spk")).sort
        {files, File.basename(File.expand_path(path))}
      else
        {[path], File.basename(File.dirname(File.expand_path(path)))}
      end
    end

    # Translates, writes `.sparkle/<package>/*.pony` and compiles it with the
    # linked-in Pony compiler, against the standard library of the Pony
    # installation that holds the `ponyc` found by `find_ponyc`. Returns the
    # exit code. `out_dir` receives the binary.
    def self.build(path : String, out_dir : String?, err : IO = STDERR) : {Int32, String?}
      files, package = sources_for(path)
      if files.empty?
        err.puts "sparkle: no .spk files in #{path}"
        return {1, nil}
      end
      gen_dir = File.join(".sparkle", package)
      Dir.mkdir_p(gen_dir)
      Dir.glob(File.join(gen_dir, "*.pony")).each { |stale| File.delete(stale) }
      generated = [] of GeneratedFile
      sources = files.map { |file| File.read(file) }
      programs = [] of Program
      files.each_with_index do |file, i|
        programs << Parser.parse(sources[i])
      rescue e : ParseError
        err.print format_error(file, sources[i], e)
        return {1, nil}
      end
      primed = Emitter.primed_params(programs)
      names = Emitter.enum_names(programs)
      files.each_with_index do |file, i|
        source = sources[i]
        begin
          pony, map = Emitter.emit(programs[i], primed)
        rescue e : ParseError
          err.print format_error(file, source, e)
          return {1, nil}
        end
        pony_path = File.join(gen_dir, File.basename(file, ".spk") + ".pony")
        File.write(pony_path, pony)
        generated << GeneratedFile.new(pony_path, file, map, source)
      end
      ponyc = find_ponyc
      unless ponyc
        err.puts "sparkle: ponyc not found (set SPARKLE_PONYC, run `make ponyc`, or put ponyc on PATH)"
        return {1, nil}
      end
      out_dir ||= File.join(".sparkle", "bin")
      Dir.mkdir_p(out_dir)
      ok, errors = Ponyc.compile(gen_dir, out_dir, package, File.dirname(File.dirname(ponyc)))
      err.print Diagnostics.rewrite(errors, generated, names: names)
      {ok ? 0 : 1, File.join(out_dir, package)}
    end
  end
end
