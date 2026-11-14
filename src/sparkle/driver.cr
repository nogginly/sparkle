require "./parser"
require "./emitter"
require "./diagnostics"

module Sparkle
  # Result of translating one Sparkle source.
  record Translation, source : String, program : Program, pony : String, map : SourceMap

  module Driver
    PONYC_RELATIVE = "vendor/ponyc/build/release/ponyc"

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

    # Locates ponyc: `$SPARKLE_PONYC`, then the vendored build relative to the
    # executable and the working directory (and their parents), then `PATH`.
    def self.find_ponyc(env_value : String? = ENV["SPARKLE_PONYC"]?, exe_path : String? = Process.executable_path, cwd : String = Dir.current) : String?
      if env_value && !env_value.empty?
        return env_value
      end
      roots = [] of String
      if exe_path
        roots << File.dirname(File.dirname(File.expand_path(exe_path)))
      end
      roots << File.expand_path(cwd)
      roots.each do |root|
        dir = root
        loop do
          candidate = File.join(dir, PONYC_RELATIVE)
          return candidate if File.file?(candidate) && File.executable?(candidate)
          parent = File.dirname(dir)
          break if parent == dir
          dir = parent
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

    # Translates, writes `.sparkle/<package>/*.pony` and runs ponyc. Returns
    # the exit code. `out_dir` receives the binary.
    def self.build(path : String, out_dir : String?, err : IO = STDERR) : {Int32, String?}
      files, package = sources_for(path)
      if files.empty?
        err.puts "sparkle: no .spk files in #{path}"
        return {1, nil}
      end
      gen_dir = File.join(".sparkle", package)
      Dir.mkdir_p(gen_dir)
      Dir.glob(File.join(gen_dir, "*.pony")).each { |f| File.delete(f) }
      generated = [] of GeneratedFile
      files.each do |f|
        source = File.read(f)
        begin
          t = translate(source)
        rescue e : ParseError
          err.print format_error(f, source, e)
          return {1, nil}
        end
        pony_path = File.join(gen_dir, File.basename(f, ".spk") + ".pony")
        File.write(pony_path, t.pony)
        generated << GeneratedFile.new(pony_path, f, t.map, source)
      end
      ponyc = find_ponyc
      unless ponyc
        err.puts "sparkle: ponyc not found (set SPARKLE_PONYC, build vendor/ponyc, or put ponyc on PATH)"
        return {1, nil}
      end
      out_dir ||= File.join(".sparkle", "bin")
      Dir.mkdir_p(out_dir)
      io = IO::Memory.new
      status = Process.run(ponyc, ["-o", out_dir, "-b", package, File.expand_path(gen_dir)], output: io, error: io)
      err.print Diagnostics.rewrite(io.to_s, generated)
      {status.exit_code, File.join(out_dir, package)}
    end
  end
end
