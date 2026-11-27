require "./spec_helper"

PONYC = Sparkle::Driver.find_ponyc(exe_path: File.join(ROOT, "bin", "sparkle"), cwd: ROOT)

private def build_and_run(path : String) : {Int32, String, String}
  err = IO::Memory.new
  Dir.cd(ROOT) do
    code, binary = Sparkle::Driver.build(path, File.join(".sparkle", "bin"), err)
    return {code, "", err.to_s} unless code == 0
    stdout = IO::Memory.new
    status = Process.run(File.expand_path(binary || raise "build produced no binary"), output: stdout, error: err)
    {status.exit_code, stdout.to_s, err.to_s}
  end
end

# Builds `source` as a one-file package and runs it.
private def run_source(source : String, release : Bool = false) : {Int32, String, String}
  dir = File.join(Dir.tempdir, "sparkle-e2e-#{Process.pid}-#{source.hash}")
  Dir.mkdir_p(dir)
  begin
    File.write(File.join(dir, "main.spk"), source)
    err = IO::Memory.new
    code, binary = Sparkle::Driver.build(dir, File.join(dir, "bin"), err, release: release)
    return {code, "", err.to_s} unless code == 0
    stdout = IO::Memory.new
    status = Process.run(binary || raise("no binary"), output: stdout, error: err)
    {status.exit_code, stdout.to_s, err.to_s}
  ensure
    FileUtils.rm_rf(dir)
  end
end

private CONTRACTED = <<-SPK
  class Counter
    @n : Int32 = 0

    def ref add(by : Int32) : Int32
      expects by > 0
      guarantees result == 99

      @n += by
      @n
    end
  end

  actor Main
    def self.new(env : Env)
      c = Counter.new
      c.add(ARG)
    end
  end
  SPK

private def golden(path : String, actual : String) : Nil
  File.write(path, actual) if ENV["UPDATE_GOLDEN"]? == "1"
  actual.should eq File.read(path)
end

describe "end to end" do
  examples = Dir.glob(File.join(ROOT, "examples", "*", "main.spk")).sort
  if PONYC.nil?
    examples.each do |spk|
      pending "runs examples/#{File.basename(File.dirname(spk))} (ponyc not found)"
    end
    pending "reports errors at the Sparkle line (ponyc not found)"
  else
    examples.each do |spk|
      dir = File.dirname(spk)
      it "runs examples/#{File.basename(dir)}" do
        relative = File.join("examples", File.basename(dir), "main.spk")
        code, stdout, err = build_and_run(relative)
        code.should eq(0), err
        stdout.should eq File.read(File.join(dir, "expected.out"))

        tree_err = IO::Memory.new
        tree_code, tree = Dir.cd(ROOT) { Sparkle::Driver.tree_text(relative, tree_err) }
        tree_code.should eq(0), tree_err.to_s
        golden(File.join(dir, "expected.ast"), tree || "")
      end
    end

    it "builds an example with optimised code when asked" do
      err = IO::Memory.new
      code, binary = Dir.cd(ROOT) { Sparkle::Driver.build("examples/ring/main.spk", File.join(".sparkle", "release"), err, release: true) }
      code.should eq(0), err.to_s
      stdout = IO::Memory.new
      Process.run(File.join(ROOT, binary || raise("no binary")), output: stdout).success?.should be_true
      stdout.to_s.should eq File.read(File.join(ROOT, "examples", "ring", "expected.out"))
    end

    it "checks an example without generating code" do
      Dir.cd(ROOT) { Sparkle::Driver.check("examples/ring/main.spk", IO::Memory.new) }.should eq 0
    end

    Dir.glob(File.join(ROOT, "spec", "fixtures", "*", "main.spk")).sort.each do |spk|
      fixture = Path[spk].relative_to(ROOT).to_s
      it "reports the same errors for #{fixture} from check as from build" do
        built = IO::Memory.new
        checked = IO::Memory.new
        Dir.cd(ROOT) { Sparkle::Driver.build(fixture, File.join(".sparkle", "bin"), built) }
        Dir.cd(ROOT) { Sparkle::Driver.check(fixture, checked) }.should eq 1
        checked.to_s.should eq built.to_s
      end
    end

    it "reports errors at the Sparkle line" do
      err = IO::Memory.new
      code = Dir.cd(ROOT) { Sparkle::Driver.build("spec/fixtures/undefined_name/main.spk", File.join(".sparkle", "bin"), err)[0] }
      code.should_not eq 0
      text = err.to_s
      text.should contain "spec/fixtures/undefined_name/main.spk:4:"
      text.should contain "    env.out <~ print(missing_name)"
    end

    it "stops at a failed contract, naming the clause and its place" do
      code, _, err = run_source(CONTRACTED.sub("ARG", "0"))
      code.should eq 1
      err.should eq "main.spk:5:13: contract failed in Counter.add: expects by > 0\n"
      code, _, err = run_source(CONTRACTED.sub("ARG", "1"))
      code.should eq 1
      err.should eq "main.spk:6:16: contract failed in Counter.add: guarantees result == 99\n"
    end

    it "checks only expects in a release build" do
      code, _, err = run_source(CONTRACTED.sub("ARG", "1"), release: true)
      code.should eq(0), err
    end

    it "runs the parts of an interpolated string left to right" do
      source = <<-'SPK'
        class Log
          @text : String = ""

          def ref add(s : String) : String
            @text = @text + s
            s
          end

          def text : String = @text
        end

        actor Main
          def self.new(env : Env)
            log = Log.new
            env.out <~ print("#{log.add("a")}#{log.add("b")}#{log.add("c")} #{log.text}")
          end
        end
        SPK
      code, stdout, err = run_source(source)
      code.should eq(0), err
      stdout.should eq "abc abc\n"
    end

    it "requires <~ for a behaviour, and only for one" do
      err = IO::Memory.new
      Dir.cd(ROOT) { Sparkle::Driver.check("spec/fixtures/behaviour_calls/main.spk", err) }.should eq 1
      err.to_s.lines.select(&.matches?(/\A\S+:\d+:\d+: /)).should eq [
        "spec/fixtures/behaviour_calls/main.spk:13:13: `print` is a behaviour: post it with `<~`",
        "spec/fixtures/behaviour_calls/main.spk:17:7: `tick` is a behaviour: post it with `self <~`",
        "spec/fixtures/behaviour_calls/main.spk:19:13: `<~` posts to a behaviour, and `size` is not one: call it with `.`",
      ]
    end

    it "rejects a contract that would change state" do
      err = IO::Memory.new
      Dir.cd(ROOT) { Sparkle::Driver.check("spec/fixtures/contract_ref_call/main.spk", err) }.should eq 1
      text = err.to_s
      text.should contain "spec/fixtures/contract_ref_call/main.spk:5:20: receiver type is not a subtype of target type"
      text.should contain "receiver type: box Array(val String)"
    end

    it "prints types in ponyc messages in Sparkle syntax" do
      err = IO::Memory.new
      Dir.cd(ROOT) { Sparkle::Driver.build("spec/fixtures/iso_mismatch/main.spk", File.join(".sparkle", "bin"), err) }
      text = err.to_s
      text.should contain "spec/fixtures/iso_mismatch/main.spk:10:23: argument not assignable to parameter"
      text.should contain "argument type is ref Array(val String)"
      text.should contain "parameter type requires iso^ Array(val String)"
      text.should contain "spec/fixtures/iso_mismatch/main.spk:11:5: right side must be a subtype of left side"
      text.should_not contain "Array[String"
    end
  end
end
