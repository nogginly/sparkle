require "./spec_helper"

include Sparkle

private def expr(src : String) : Expr
  p = Parser.parse("actor A\n  def f\n    #{src}\n  end\nend\n")
  body = p.items[0].as(TypeDecl).methods[0].body || raise "method has no body"
  body[0]
end

describe Parser do
  it "parses a class with fields, includes and methods" do
    prog = Parser.parse("class Foo(A : val)\n  include Bar\n  @n : UInt64 = 0\n  def ref incr = @n += 1\nend\n")
    d = prog.items[0].as(TypeDecl)
    d.name.should eq "Foo"
    d.tparams.map(&.name).should eq ["A"]
    d.includes.size.should eq 1
    d.fields[0].name.should eq "n"
    d.methods[0].cap.should eq "ref"
    d.methods[0].body.try(&.size).should eq 1
  end

  it "attaches line and column to nodes" do
    e = expr("foo(1)")
    {e.line, e.col}.should eq({3, 5})
  end

  it "applies Crystal precedence" do
    b = expr("1 + 2 * 3").as(Binary)
    b.op.should eq "+"
    b.right.as(Binary).op.should eq "*"
  end

  it "parses ternary, postfix if and unless" do
    expr("a ? b : c").should be_a(Ternary)
    i = expr("x = 1 if c").as(If)
    i.negate.should be_false
    i.modifier.should be_true
    expr("x unless c").as(If).negate.should be_true
  end

  it "parses calls with named arguments and blocks" do
    c = expr("a.b(1, x: 2) do |i|\n i\n end").as(Call)
    c.args.size.should eq 1
    c.named[0].name.should eq "x"
    c.block.try(&.params.map(&.name)).should eq ["i"]
  end

  it "parses brace blocks and &.name" do
    expr("a.map { |x| x }").as(Call).block.should_not be_nil
    expr("a.map(&.size)").as(Call).args[0].should be_a(AmpMethod)
  end

  it "parses generic constants as type references" do
    c = expr("Array(String).new").as(Call)
    c.recv.as(TypeRef).type.as(NamedType).args.size.should eq 1
  end

  it "parses types with capabilities, unions and nullables" do
    prog = Parser.parse("class A\n  def f(a : iso Array(String), b : String?, c : Proc(Int8, Nil)) : A | B\n  end\nend\n")
    m = prog.items[0].as(TypeDecl).methods[0]
    m.params[0].type.as(NamedType).cap.should eq "iso"
    m.params[1].type.should be_a(UnionType)
    m.params[2].type.should be_a(ProcType)
    m.ret.should be_a(UnionType)
  end

  it "records capability uses by position" do
    prog = Parser.parse("class val A\n  def ref f(a : iso B)\n    recover iso do 1 end\n  end\nend\n")
    prog.cap_uses.map(&.position).should eq ["type declaration", "def", "type", "recover"]
  end

  it "treats capability words as ordinary names in expressions" do
    expr("iso = 1").should be_a(Assign)
  end

  it "reports errors with line and column" do
    err = expect_raises(ParseError) { Parser.parse("class A\n  def f\n    1 +\n  end\nend\n") }
    err.line.should eq 4
  end

  it "rejects fields without a type" do
    expect_raises(ParseError, /needs a type/) { Parser.parse("class A\n  @x = 1\nend\n") }
  end

  it "rejects raise with an argument" do
    expect_raises(ParseError, /takes no argument/) { expr(%(raise "x")) }
  end

  describe "enums" do
    it "resolves member values" do
      enum_decl = Parser.parse("enum Colour\n  Red\n  Green = 5\n  Blue\nend\n").items.first.as(EnumDecl)
      enum_decl.members.map(&.value).should eq [0_i64, 5_i64, 6_i64]
    end

    it "accepts negative values" do
      enum_decl = Parser.parse("enum E\n  A = -2\n  B\nend\n").items.first.as(EnumDecl)
      enum_decl.members.map(&.value).should eq [-2_i64, -1_i64]
    end

    it "rejects bad enums" do
      expect_raises(ParseError, "an enum needs at least one member") { Parser.parse("enum E\nend\n") }
      expect_raises(ParseError, "duplicate enum member A") { Parser.parse("enum E\n  A\n  A\nend\n") }
      expect_raises(ParseError, "only members are allowed in an enum body") { Parser.parse("enum E\n  A\n  def f\n  end\nend\n") }
    end

    it "parses when .red? as a PredicatePattern" do
      program = Parser.parse("actor Main\n  def self.new(env : Env)\n    case 1\n    when .red? then 1\n    end\n  end\nend\n")
      pattern = program.items[0].as(TypeDecl).methods[0].body.as(Array(Expr))[0].as(Case).whens[0].patterns[0]
      pattern.as(PredicatePattern).name.should eq "red?"
    end

    it "parses Colour::Red as an EnumRef" do
      ref = expr("Colour::Red").as(EnumRef)
      {ref.enum_name, ref.member}.should eq({"Colour", "Red"})
    end
  end
end
