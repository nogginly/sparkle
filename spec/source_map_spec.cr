require "./spec_helper"

include Sparkle

describe SourceMap do
  it "returns the last mark at or before a position" do
    m = SourceMap.new
    m.add(1, 1, 10, 1)
    m.add(2, 3, 11, 5)
    m.add(2, 9, 11, 12)
    m.lookup(2, 3).should eq({11, 5})
    m.lookup(2, 8).should eq({11, 5})
    m.lookup(2, 20).should eq({11, 12})
    m.lookup(3, 1).should eq({11, 12})
    m.lookup(1, 1).should eq({10, 1})
  end

  it "returns nil before the first mark" do
    m = SourceMap.new
    m.add(2, 3, 1, 1)
    m.lookup(1, 5).should be_nil
  end

  it "records marks while emitting" do
    t = Driver.translate("actor Main\n  def self.new(env : Env)\n    env.@out.print(\"x\")\n  end\nend\n")
    pony_line = t.pony.lines.index! { |l| l.includes?("print") } + 1
    col = t.pony.lines[pony_line - 1].index!("print") + 1
    t.map.lookup(pony_line, col).should eq({3, 14})
  end
end
