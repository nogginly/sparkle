require "./spec_helper"

describe "golden translations" do
  Dir.glob(File.join(ROOT, "examples", "*", "main.spk")).sort.each do |spk|
    dir = File.dirname(spk)
    name = File.basename(dir)
    it "translates examples/#{name}" do
      actual = translate(File.read(spk))
      expected_path = File.join(dir, "expected.pony")
      if ENV["UPDATE_GOLDEN"]? == "1"
        File.write(expected_path, actual)
      end
      actual.should eq File.read(expected_path)
    end
  end
end
