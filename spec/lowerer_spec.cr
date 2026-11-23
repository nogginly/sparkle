require "./spec_helper"

include Sparkle

private HOME = Driver.find_ponyc(exe_path: File.join(ROOT, "bin", "sparkle"), cwd: ROOT).try { |ponyc| File.dirname(File.dirname(ponyc)) }

# Every example must lower: the AST path has parity with the text path.
private LOWERED = Dir.glob(File.join(ROOT, "examples", "*", "main.spk")).map { |spk| File.basename(File.dirname(spk)) }.sort!

describe Lowerer do
  if home = HOME
    LOWERED.each do |name|
      dir = File.join(ROOT, "examples", name)
      file = File.join("examples", name, "main.spk")
      source = File.read(File.join(dir, "main.spk"))

      it "lowers examples/#{name} to the tree ponyc parses from its expected.pony" do
        program = Parser.parse(source)
        primed = Emitter.primed_params([program])
        predicates = Emitter.enum_predicates([program])
        calls = Driver.tree_calls([file], [source], [program], home, primed, predicates) { }
        lowered = Ponyc.tree_text(home) { |tree| Lowerer.new(tree, calls[file]? || Set({Int32, Int32}).new, primed, predicates).lower(program, file, source) }
        lowered.should eq Ponyc.parse_text(dir, home)
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
