require "./sparkle/driver"
require "./sparkle/cap_stats"

module Sparkle
  USAGE = <<-TXT
    usage:
      sparkle translate FILE.spk          print the generated Pony
      sparkle build PATH [-o DIR]         translate and compile with ponyc
      sparkle run PATH [-- args]          build, then run the binary
      sparkle caps PATH...                capability statistics
    TXT

  module CLI
    def self.run(args : Array(String)) : NoReturn
      cmd = args.shift?
      case cmd
      when "translate" then exit translate(args)
      when "build"     then exit build(args)
      when "run"       then exit run_program(args)
      when "caps"      then exit caps(args)
      else
        STDERR.puts USAGE
        exit 2
      end
    end

    private def self.translate(args : Array(String)) : Int32
      return usage if args.size != 1
      source = File.read(args[0])
      begin
        print Driver.translate(source).pony
        0
      rescue e : ParseError
        STDERR.print Driver.format_error(args[0], source, e)
        1
      end
    rescue e : File::Error
      STDERR.puts "sparkle: #{e.message}"
      1
    end

    private def self.build(args : Array(String)) : Int32
      out_dir = nil
      paths = [] of String
      while arg = args.shift?
        if arg == "-o"
          out_dir = args.shift? || return usage
        else
          paths << arg
        end
      end
      return usage unless paths.size == 1
      Driver.build(paths[0], out_dir)[0]
    end

    private def self.run_program(args : Array(String)) : Int32
      split = args.index("--")
      program_args = split ? args[(split + 1)..] : [] of String
      own = split ? args[0, split] : args
      return usage unless own.size == 1
      code, binary = Driver.build(own[0], nil)
      return code unless code == 0 && binary
      Process.run(File.expand_path(binary), program_args, input: Process::Redirect::Inherit, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit).exit_code
    end

    private def self.caps(args : Array(String)) : Int32
      return usage if args.empty?
      entries = [] of {String, Program}
      args.each do |path|
        files = File.directory?(path) ? Dir.glob(File.join(path, "*.spk")).sort : [path]
        files.each do |file|
          source = File.read(file)
          begin
            entries << {file, Parser.parse(source)}
          rescue e : ParseError
            STDERR.print Driver.format_error(file, source, e)
            return 1
          end
        end
      end
      print CapStats.report(entries)
      0
    end

    private def self.usage : Int32
      STDERR.puts USAGE
      2
    end
  end
end

Sparkle::CLI.run(ARGV)
