require "./spec_helper"

include Sparkle

private HOME = Driver.find_ponyc(exe_path: File.join(ROOT, "bin", "sparkle"), cwd: ROOT).try { |ponyc| File.dirname(File.dirname(ponyc)) }

describe Lowerer do
  if home = HOME
    it "lowers a negative literal receiver as the parenthesised literal" do
      source = "actor Main\n  def self.new(env : Env)\n    x = -1.abs()\n    y = -1[0]\n  end\nend\n"
      pony = "actor Main\n  new create(env: Env) =>\n    var x = (-1).abs()\n    var y = (-1)(0)\n"
      lowers_as(Parser.parse(source), source, pony)
    end

    it "reports a construct it cannot lower yet at its Sparkle position" do
      source = "class Point\n  @s : String = \"a\\0\"\nend\n"
      expect_raises(ParseError, "the AST path does not lower") do
        Ponyc.tree_text(home) { |tree| Lowerer.new(tree).lower(Parser.parse(source), "main.spk", source) }
      end
    end
  else
    pending "lowers constructs (ponyc not found)"
  end
end
