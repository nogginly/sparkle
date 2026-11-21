require "./spec_helper"

include Sparkle

private HOME = Driver.find_ponyc(exe_path: File.join(ROOT, "bin", "sparkle"), cwd: ROOT).try { |ponyc| File.dirname(File.dirname(ponyc)) }

# The examples the AST path lowers so far; stage 3 is done when this is all of them.
private LOWERED = %w[fields counter fizzbuzz handoff shapes ring traffic]

describe Lowerer do
  if home = HOME
    LOWERED.each do |name|
      dir = File.join(ROOT, "examples", name)
      file = File.join("examples", name, "main.spk")
      source = File.read(File.join(dir, "main.spk"))

      it "lowers examples/#{name} to the tree ponyc parses from its expected.pony" do
        program = Parser.parse(source)
        primed = Emitter.primed_params([program])
        calls = Driver.tree_calls([file], [source], [program], home, primed) { }
        lowered = Ponyc.tree_text(home) { |tree| Lowerer.new(tree, calls[file]? || Set({Int32, Int32}).new, primed).lower(program, file, source) }
        lowered.should eq Ponyc.parse_text(dir, home)
      end

      it "builds and runs examples/#{name} through the AST path" do
        err = IO::Memory.new
        previous = ENV["SPARKLE_AST"]?
        begin
          ENV["SPARKLE_AST"] = "1"
          code, binary = Dir.cd(ROOT) { Driver.build(file, File.join(".sparkle", "bin"), err) }
          code.should eq(0), err.to_s
          output = IO::Memory.new
          Process.run(File.join(ROOT, binary || raise "no binary"), output: output).success?.should be_true
          output.to_s.should eq File.read(File.join(dir, "expected.out"))
        ensure
          ENV["SPARKLE_AST"] = previous
        end
      end
    end

    it "reports a construct it cannot lower yet at its Sparkle position" do
      source = "class Point\n  @x : Float64 = 1.5\nend\n"
      expect_raises(ParseError, "the AST path does not lower") do
        Ponyc.tree_text(home) { |tree| Lowerer.new(tree).lower(Parser.parse(source), "main.spk", source) }
      end
    end
  else
    pending "lowers the examples (ponyc not found)"
  end
end
