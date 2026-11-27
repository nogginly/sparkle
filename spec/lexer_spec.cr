require "./spec_helper"

include Sparkle

private def texts(src : String) : Array(String)
  lex(src).reject { |token| token.kind.newline? || token.kind.eof? }.map(&.text)
end

describe Lexer do
  it "drops comments and joins lines after operators and commas" do
    toks = lex("a = 1 + # note\n  2\nb")
    toks.count(&.kind.newline?).should eq 2
  end

  it "joins a method chain that continues on the next line" do
    lex("a\n  .b\n  .c").count(&.kind.newline?).should eq 1
  end

  it "lexes ? and ! suffixes but not != or ?=" do
    texts("a.empty? b! c != d").should eq ["a", ".", "empty?", "b!", "c", "!=", "d"]
  end

  it "keeps constants free of suffixes" do
    texts("Foo?").should eq ["Foo", "?"]
  end

  it "lexes instance variables" do
    t = lex("@count").first
    t.kind.should eq Kind::InstVar
    t.text.should eq "count"
  end

  it "reads number suffixes" do
    lex("1_u64").first.suffix.should eq "U64"
    lex("7u8").first.suffix.should eq "U8"
    t = lex("2.5_f32").first
    t.kind.should eq Kind::Float
    t.text.should eq "2.5"
    t.suffix.should eq "F32"
    lex("0xf8").first.suffix.should be_nil
    lex("0xff_u8").first.text.should eq "0xff"
  end

  it "does not read a range as a float" do
    texts("1..5").should eq ["1", "..", "5"]
  end

  it "splits interpolations with nested braces and strings" do
    t = lex(%q("a #{ {1, "x}"} } b")).first
    parts = t.parts || raise "string token has no parts"
    parts.size.should eq 3
    parts[0].should eq "a "
    parts[2].should eq " b"
  end

  it "treats capability words as identifiers" do
    lex("iso val").map(&.kind).first(2).should eq [Kind::Ident, Kind::Ident]
  end

  it "records line and column" do
    t = lex("a\n  bb").find! { |x| x.text == "bb" }
    {t.line, t.col}.should eq({2, 3})
  end

  it "rejects unterminated strings" do
    expect_raises(ParseError, /unterminated string/) { lex(%("abc)) }
  end

  it "lexes :: as one operator and : on its own" do
    lex("Colour::Red").map { |token| {token.kind, token.text} }.first(3).should eq [{Kind::Const, "Colour"}, {Kind::Op, "::"}, {Kind::Const, "Red"}]
    lex("x : Int32").map(&.text).first(3).should eq ["x", ":", "Int32"]
  end

  it "refuses names starting with spk_, which Sparkle generates" do
    {"spk_view = 1" => "1:1", "x = @spk_n" => "1:5"}.each do |source, position|
      error = expect_raises(ParseError, "names starting with `spk_` are reserved for Sparkle") { lex(source) }
      "#{error.line}:#{error.col}".should eq position
    end
  end
end
