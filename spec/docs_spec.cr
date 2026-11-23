require "./spec_helper"

private DOCS_PONYC  = Sparkle::Driver.find_ponyc(exe_path: File.join(ROOT, "bin", "sparkle"), cwd: ROOT)
private DECLARATION = /\A(class|struct|actor|primitive|trait|interface|enum|alias|use)\b/

# A `crystal` code block in the language docs, and the `text` block right after
# it, if any, which holds what the program prints.
private record DocExample, file : String, line : Int32, code : String, output : String?

private def doc_examples(path : String) : Array(DocExample)
  examples = [] of DocExample
  lines = File.read_lines(path)
  i = 0
  while i < lines.size
    unless lines[i] == "```crystal"
      i += 1
      next
    end
    start = i + 1
    while i < lines.size && lines[i] != "```"
      i += 1
    end
    code = lines[start...i].join("\n") + "\n"
    i += 1
    j = i
    while j < lines.size && lines[j].strip.empty?
      j += 1
    end
    output = nil
    if lines[j]? == "```text"
      k = j + 1
      while k < lines.size && lines[k] != "```"
        k += 1
      end
      output = lines[(j + 1)...k].join("\n") + "\n"
      i = k + 1
    end
    examples << DocExample.new(path, start, code, output)
  end
  examples
end

# A block that declares `Main` is a whole program. One that starts with a
# declaration gets an empty `Main`. Anything else is statements, run in
# `Main.new` with `env` in scope.
private def doc_program(code : String) : String
  return code if code.includes?("actor Main")
  first = code.lines.map(&.strip).find { |line| !line.empty? && !line.starts_with?('#') } || ""
  return code + "\nactor Main\n  def self.new(env : Env)\n  end\nend\n" if first.matches?(DECLARATION)
  "actor Main\n  def self.new(env : Env)\n" + code.lines(chomp: false).map { |line| "    #{line}" }.join + "  end\nend\n"
end

describe "language docs" do
  files = Dir.glob(File.join(ROOT, "skills", "sparkle", "**", "*.md")).sort!
  files.each do |file|
    doc_examples(file).each do |example|
      name = "#{Path[file].relative_to(ROOT)}:#{example.line}"
      if DOCS_PONYC.nil?
        pending "checks #{name} (ponyc not found)"
        next
      end
      it "#{example.output ? "runs" : "checks"} #{name}" do
        dir = File.join(Dir.tempdir, "sparkle-doc-#{Process.pid}-#{example.line}")
        Dir.mkdir_p(dir)
        begin
          File.write(File.join(dir, "main.spk"), doc_program(example.code))
          err = IO::Memory.new
          if expected = example.output
            code, binary = Sparkle::Driver.build(dir, File.join(dir, "bin"), err)
            code.should eq(0), err.to_s
            stdout = IO::Memory.new
            Process.run(binary || raise("no binary"), output: stdout, error: err).success?.should be_true, err.to_s
            stdout.to_s.should eq expected
          else
            Sparkle::Driver.check(dir, err).should eq(0), err.to_s
          end
        ensure
          FileUtils.rm_rf(dir)
        end
      end
    end
  end
end
