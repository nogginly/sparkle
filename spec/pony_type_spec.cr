require "./spec_helper"

include Sparkle

private def to_pony(src : String) : String
  prog = Parser.parse("class A\n  def f : #{src}\n  end\nend\n")
  ret = prog.items[0].as(TypeDecl).methods[0].ret || raise "method has no return type"
  PonyType.to_pony(ret)
end

private def to_spk(pony : String) : String
  type = PonyType.parse(pony) || raise "cannot parse #{pony}"
  PonyType.to_sparkle(type)
end

describe PonyType do
  describe "Sparkle to Pony" do
    it "maps builtin names" do
      to_pony("UInt64").should eq "U64"
      to_pony("Float32").should eq "F32"
      to_pony("Nil").should eq "None"
    end

    it "prints generics and capabilities" do
      to_pony("Array(String)").should eq "Array[String]"
      to_pony("val String").should eq "String val"
      to_pony("iso^ String").should eq "String iso^"
      to_pony("A!").should eq "A!"
    end

    it "prints nullables, unions, intersections and tuples" do
      to_pony("String?").should eq "(String | None)"
      to_pony("val String?").should eq "(String val | None)"
      to_pony("A | B").should eq "(A | B)"
      to_pony("A & B").should eq "(A & B)"
      to_pony("{A, B}").should eq "(A, B)"
    end

    it "prints viewpoint arrows and procs" do
      to_pony("this->A").should eq "this->A"
      to_pony("box->A").should eq "box->A"
      to_pony("Proc(A, B)").should eq "{(A): B}"
      to_pony("val Proc(A, B)").should eq "{(A): B} val"
    end

    it "prints a lone capability as Any" do
      to_pony("val").should eq "Any val"
      to_pony("send").should eq "Any #send"
    end
  end

  describe "Pony to Sparkle" do
    it "re-prints generics with capabilities first" do
      to_spk("Array[String val] ref").should eq "ref Array(val String)"
    end

    it "prints unions with None as nullables" do
      to_spk("(String val | None val)").should eq "val String?"
      to_spk("(String | None)").should eq "String?"
      to_spk("(A | B)").should eq "A | B"
    end

    it "prints builtin names, ephemeral and alias markers" do
      to_spk("U8").should eq "UInt8"
      to_spk("String iso^").should eq "iso^ String"
      to_spk("A!").should eq "A!"
      to_spk("None").should eq "Nil"
    end

    it "prints tuples, arrows, lambdas and generic caps" do
      to_spk("(A, B)").should eq "{A, B}"
      to_spk("this->A").should eq "this->A"
      to_spk("{(A): B} val").should eq "val Proc(A, B)"
      to_spk("Any #send").should eq "send"
    end

    it "fails to parse prose" do
      PonyType.parse("see below").should be_nil
      PonyType.parse("Foo[").should be_nil
    end
  end

  describe ".rewrite" do
    it "replaces types inside message text" do
      msg = "argument type is Array[String val] ref, parameter type is (String val | None val)"
      PonyType.rewrite(msg).should eq "argument type is ref Array(val String), parameter type is val String?"
    end

    it "leaves ordinary words alone" do
      msg = "can't find declaration of 'foo' in Main (see below)"
      PonyType.rewrite(msg).should eq msg
    end
  end
end
