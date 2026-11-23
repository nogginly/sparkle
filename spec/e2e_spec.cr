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
      text.should contain "    env.out.print(missing_name)"
    end

    it "prints types in ponyc messages in Sparkle syntax" do
      err = IO::Memory.new
      Dir.cd(ROOT) { Sparkle::Driver.build("spec/fixtures/iso_mismatch/main.spk", File.join(".sparkle", "bin"), err) }
      text = err.to_s
      text.should contain "spec/fixtures/iso_mismatch/main.spk:10:20: argument not assignable to parameter"
      text.should contain "argument type is ref Array(val String)"
      text.should contain "parameter type requires iso^ Array(val String)"
      text.should contain "spec/fixtures/iso_mismatch/main.spk:11:5: right side must be a subtype of left side"
      text.should_not contain "Array[String"
    end
  end
end
