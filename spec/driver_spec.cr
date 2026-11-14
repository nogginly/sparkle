require "file_utils"
require "./spec_helper"

include Sparkle

describe Driver do
  it "formats parse errors with the source line and a caret" do
    src = "class A\n  def f\n    1 +\n  end\nend\n"
    err = expect_raises(ParseError) { Driver.translate(src) }
    text = Driver.format_error("a.spk", src, err)
    text.should start_with "a.spk:4:3: "
    text.lines[1].should eq "  end"
    text.lines[2].should eq "  ^"
  end

  describe ".find_ponyc" do
    it "prefers the environment variable" do
      Driver.find_ponyc("/opt/ponyc", nil, "/nonexistent").should eq "/opt/ponyc"
    end

    it "finds the vendored build from the working directory and its parents" do
      dir = File.join(Dir.tempdir, "sparkle-spec-#{Process.pid}")
      bin = File.join(dir, "vendor/ponyc/build/release")
      Dir.mkdir_p(bin)
      path = File.join(bin, "ponyc")
      File.write(path, "#!/bin/sh\n")
      File.chmod(path, 0o755)
      Dir.mkdir_p(File.join(dir, "sub/deeper"))
      begin
        Driver.find_ponyc(nil, nil, File.join(dir, "sub/deeper")).should eq path
        Driver.find_ponyc(nil, File.join(dir, "bin/sparkle"), "/").should eq path
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  it "derives the package from a file or directory" do
    Driver.sources_for("examples/counter/main.spk").should eq({["examples/counter/main.spk"], "counter"})
    Driver.sources_for("examples/counter")[1].should eq "counter"
  end
end
