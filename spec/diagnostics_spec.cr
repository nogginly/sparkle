require "./spec_helper"

include Sparkle

describe Diagnostics do
  it "keeps a location and its excerpt, re-printing the message" do
    text = <<-TXT
      Error:
      main.spk:4:20: argument type is Array[String val] ref
          env.@out.print(missing)
                         ^

      TXT
    Diagnostics.rewrite(text).should eq text.sub("Array[String val] ref", "ref Array(val String)")
  end

  it "rewrites Info frames and types in messages" do
    text = "Error:\nmain.spk:4:5: bad Array[String val] ref\n    Info:\n    main.spk:4:5: note\n"
    got = Diagnostics.rewrite(text)
    got.should contain "bad ref Array(val String)"
    got.should contain "    main.spk:4:5: note"
  end

  it "maps primed names in messages back" do
    text = "Error:\nmain.spk:4:5: can't reuse name 'payload''\n"
    Diagnostics.rewrite(text).should contain "can't reuse name 'payload'\n"
  end

  it "keeps excerpts that look like Pony types" do
    text = "Error:\nmain.spk:2:3: can't use Array[String val] ref\n    x : Array[String val] ref\n    ^\n"
    Diagnostics.rewrite(text).should eq text.sub("can't use Array[String val] ref", "can't use ref Array(val String)")
  end

  it "leaves output without locations unchanged" do
    Diagnostics.rewrite("Building builtin -> /x\n").should eq "Building builtin -> /x\n"
  end

  it "names enum members in messages" do
    names = {"ColourRed" => "Colour::Red"}
    Diagnostics.rewrite("main.spk:1:1: argument type is ColourRed val\n", names).should contain "val Colour::Red"
    Diagnostics.rewrite("main.spk:1:1: argument type is ColourRedder val\n", names).should contain "ColourRedder"
  end
end
