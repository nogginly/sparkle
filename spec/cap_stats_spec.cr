require "./spec_helper"

include Sparkle

describe CapStats do
  it "counts annotations by position and capability" do
    src = "class val A\n  def ref f(a : iso B, c : val C?) : box->D\n    recover iso do 1 end\n  end\nend\n"
    stats = CapStats.collect(Parser.parse(src))
    stats.by_position["type declaration"].should eq 1
    stats.by_position["def"].should eq 1
    stats.by_position["type"].should eq 3
    stats.by_position["recover"].should eq 1
    stats.by_cap["iso"].should eq 2
    stats.total.should eq 6
  end

  it "reports per file and a total" do
    p1 = Parser.parse("class val A\nend\n")
    p2 = Parser.parse("class B\nend\n")
    text = CapStats.report([{"a.spk", p1}, {"b.spk", p2}])
    text.should contain "a.spk\n"
    text.should contain "total"
    text.should contain "by capability    val 1"
  end
end
