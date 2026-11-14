require "./spec_helper"

include Sparkle

SRC = "actor Main\n  def self.new(env : Env)\n    env.@out.print(\"hi\")\n    env.@out.print(missing)\n  end\nend\n"

private def generated : {GeneratedFile, String}
  t = Driver.translate(SRC)
  {GeneratedFile.new("/work/.sparkle/app/main.pony", "app/main.spk", t.map, SRC, "/work"), t.pony}
end

describe Diagnostics do
  it "maps a location, excerpt and caret to the Sparkle line" do
    file, pony = generated
    row = pony.lines.index!(&.includes?("missing")) + 1
    col = pony.lines[row - 1].index!("missing") + 1
    text = <<-TXT
      Error:
      /work/.sparkle/app/main.pony:#{row}:#{col}: can't find declaration of 'missing'
          #{pony.lines[row - 1].strip}
          #{" " * (col - 1 - (pony.lines[row - 1].size - pony.lines[row - 1].lstrip.size))}^

      TXT
    got = Diagnostics.rewrite(text, [file], "/work")
    got.should eq <<-TXT
      Error:
      app/main.spk:4:20: can't find declaration of 'missing'
      #{SRC.lines[3].chomp}
      #{" " * 19}^

      TXT
  end

  it "accepts relative paths in the output" do
    file, pony = generated
    row = pony.lines.index!(&.includes?("missing")) + 1
    text = ".sparkle/app/main.pony:#{row}:5: oops\n"
    Diagnostics.rewrite(text, [file], "/work").should start_with "app/main.spk:4:"
  end

  it "rewrites Info frames and types in messages" do
    file, pony = generated
    row = pony.lines.index!(&.includes?("print(missing")) + 1
    text = "Error:\n/work/.sparkle/app/main.pony:#{row}:5: bad Array[String val] ref\n    Info:\n    /work/.sparkle/app/main.pony:#{row}:5: note\n"
    got = Diagnostics.rewrite(text, [file], "/work")
    got.should contain "bad ref Array(val String)"
    got.should contain "    app/main.spk:4:"
  end

  it "maps primed names in messages back" do
    file, pony = generated
    row = pony.lines.index!(&.includes?("missing")) + 1
    text = "Error:\n/work/.sparkle/app/main.pony:#{row}:5: can't reuse name 'payload''\n"
    Diagnostics.rewrite(text, [file], "/work").should contain "can't reuse name 'payload'\n"
  end

  it "keeps other files' locations and excerpts, re-printing only the message" do
    file, _ = generated
    text = "Error:\n/usr/lib/pony/builtin/array.pony:12:3: can't use Array[String val] ref\n    fun foo()\n    ^\n"
    Diagnostics.rewrite(text, [file], "/work").should eq text.sub("Array[String val] ref", "ref Array(val String)")
  end

  it "leaves output without locations unchanged" do
    file, _ = generated
    Diagnostics.rewrite("Building builtin -> /x\n", [file], "/work").should eq "Building builtin -> /x\n"
  end
end
