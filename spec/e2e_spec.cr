require "./spec_helper"

PONYC = Sparkle::Driver.find_ponyc(exe_path: File.join(ROOT, "bin", "sparkle"), cwd: ROOT)

private def build_and_run(path : String) : {Int32, String, String}
  err = IO::Memory.new
  Dir.cd(ROOT) do
    code, binary = Sparkle::Driver.build(path, File.join(".sparkle", "bin"), err)
    return {code, "", err.to_s} unless code == 0
    stdout = IO::Memory.new
    status = Process.run(File.expand_path(binary.not_nil!), output: stdout, error: err)
    {status.exit_code, stdout.to_s, err.to_s}
  end
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
        code, stdout, err = build_and_run(File.join("examples", File.basename(dir), "main.spk"))
        code.should eq(0), err
        stdout.should eq File.read(File.join(dir, "expected.stdout"))
      end
    end

    it "reports errors at the Sparkle line" do
      err = IO::Memory.new
      code = Dir.cd(ROOT) { Sparkle::Driver.build("spec/fixtures/undefined_name/main.spk", File.join(".sparkle", "bin"), err)[0] }
      code.should_not eq 0
      text = err.to_s
      text.should contain "spec/fixtures/undefined_name/main.spk:4:"
      text.should contain "    env.@stdout.print(missing_name)"
    end
  end
end
