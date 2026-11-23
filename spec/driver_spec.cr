require "file_utils"
require "./spec_helper"

include Sparkle

private def with_ponyc(rel : String, &)
  dir = File.join(Dir.tempdir, "sparkle-spec-#{Process.pid}-#{Random.rand(1_000_000)}")
  bin = File.join(dir, rel)
  Dir.mkdir_p(bin)
  path = File.join(bin, "ponyc")
  File.write(path, "#!/bin/sh\n")
  File.chmod(path, 0o755)
  Dir.mkdir_p(File.join(dir, "sub/deeper"))
  begin
    yield dir, path
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe Driver do
  it "formats parse errors with the source line and a caret" do
    src = "class A\n  def f\n    1 +\n  end\nend\n"
    err = expect_raises(ParseError) { Parser.parse(src) }
    text = Driver.format_error("a.spk", src, err)
    text.should start_with "a.spk:4:3: "
    text.lines[1].should eq "  end"
    text.lines[2].should eq "  ^"
  end

  it "primes named arguments across the files of a package" do
    RULE_HOME || pending!("ponyc not found")
    dir = File.join(Dir.tempdir, "sparkle-spec-#{Process.pid}-#{Random.rand(1_000_000)}")
    Dir.mkdir_p(dir)
    File.write(File.join(dir, "job.spk"), "class val Job\n  @payload : UInt32\n  def self.new(payload : UInt32)\n    @payload = payload\n  end\n  def payload : UInt32 = @payload\nend\n")
    File.write(File.join(dir, "main.spk"), "actor Main\n  def self.new(env : Env)\n    j = Job.new(payload: 1)\n  end\nend\n")
    begin
      code, tree = Driver.tree_text(dir, IO::Memory.new)
      code.should eq 0
      (tree || "").should contain "(namedarg (id payload') (seq 1))"
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  describe ".find_pony_home" do
    it "uses lib/pony beside an installed sparkle" do
      dir = File.tempname("install")
      begin
        Dir.mkdir_p(File.join(dir, "lib/pony/packages/builtin"))
        Driver.find_pony_home(nil, File.join(dir, "bin/sparkle"), "/").should eq File.join(dir, "lib/pony")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "prefers the environment variable to an installed copy" do
      dir = File.tempname("install")
      begin
        Dir.mkdir_p(File.join(dir, "lib/pony/packages/builtin"))
        Driver.find_pony_home("/opt/pony/bin/ponyc", File.join(dir, "bin/sparkle"), "/").should eq "/opt/pony"
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "falls back to the installation holding ponyc" do
      with_ponyc(".tools/ponyc/bin") do |dir, _|
        Driver.find_pony_home(nil, File.join(dir, "bin/sparkle"), "/").should eq File.join(dir, ".tools/ponyc")
      end
    end
  end

  describe ".find_ponyc" do
    it "prefers the environment variable" do
      Driver.find_ponyc("/opt/ponyc", nil, "/nonexistent").should eq "/opt/ponyc"
    end

    it "finds the vendored build from the working directory and its parents" do
      with_ponyc("vendor/ponyc/build/release") do |dir, path|
        Driver.find_ponyc(nil, nil, File.join(dir, "sub/deeper")).should eq path
        Driver.find_ponyc(nil, File.join(dir, "bin/sparkle"), "/").should eq path
      end
    end

    it "finds the downloaded release from the working directory and its parents" do
      with_ponyc(".tools/ponyc/bin") do |dir, path|
        Driver.find_ponyc(nil, nil, File.join(dir, "sub/deeper")).should eq path
        Driver.find_ponyc(nil, File.join(dir, "bin/sparkle"), "/").should eq path
      end
    end

    it "prefers the downloaded release over the vendored build" do
      with_ponyc("vendor/ponyc/build/release") do |dir, _|
        tools = File.join(dir, ".tools/ponyc/bin")
        Dir.mkdir_p(tools)
        path = File.join(tools, "ponyc")
        File.write(path, "#!/bin/sh\n")
        File.chmod(path, 0o755)
        Driver.find_ponyc(nil, nil, dir).should eq path
      end
    end
  end

  it "derives the package from a file or directory" do
    Driver.sources_for("examples/counter/main.spk").should eq({["examples/counter/main.spk"], "counter"})
    Driver.sources_for("examples/counter")[1].should eq "counter"
  end
end
