require "file_utils"
require "./spec_helper"

include Sparkle

private PACKAGES_PONYC = Driver.find_ponyc(exe_path: File.join(ROOT, "bin", "sparkle"), cwd: ROOT)

private MAIN_SPK = "actor Main\n  def self.new(env : Env)\n  end\nend\n"

# Writes `files` (path => content) under a fresh temporary directory, yields
# its real path, and removes it afterwards.
private def with_tree(files : Hash(String, String), &)
  dir = File.join(Dir.tempdir, "sparkle-pkg-#{Process.pid}-#{Random.rand(1_000_000)}")
  files.each do |path, content|
    full = File.join(dir, path)
    Dir.mkdir_p(File.dirname(full))
    File.write(full, content)
  end
  begin
    yield File.realpath(dir)
  ensure
    FileUtils.rm_rf(dir)
  end
end

private def load_app(dir : String, library : String? = nil) : PackageSet
  app = File.join(dir, "app")
  PackageSet.new(library).load(app, PackageSet.spk_files(app))
end

describe PackageSet do
  it "loads packages before the packages that require them" do
    with_tree({
      "app/main.spk"      => "require \"./a\"\nrequire \"../shared\"\n#{MAIN_SPK}",
      "app/a/a.spk"       => "require \"../../shared\"\nclass A\nend\n",
      "shared/shared.spk" => "class S\nend\n",
    }) do |dir|
      set = load_app(dir)
      set.units.map(&.name).should eq ["shared", "a", "app"]
      set.units.map(&.dir).should eq [File.join(dir, "shared"), File.join(dir, "app/a"), File.join(dir, "app")]
      set.units[0].requires.should be_empty
      set.units[1].requires.should eq({"../../shared" => File.join(dir, "shared")})
      set.units[2].requires.should eq({"./a" => File.join(dir, "app/a"), "../shared" => File.join(dir, "shared")})
      set.units.each(&.implicit.should(be_empty))
      set.units.map { |unit| unit.files.map { |index| File.basename(set.files[index]) } }.should eq [["shared.spk"], ["a.spk"], ["main.spk"]]
    end
  end

  it "numbers a second directory with the same name" do
    with_tree({
      "app/main.spk"   => "require \"./util\"\nrequire \"../util\"\n#{MAIN_SPK}",
      "app/util/u.spk" => "class U1\nend\n",
      "util/u.spk"     => "class U2\nend\n",
    }) do |dir|
      load_app(dir).units.map(&.name).should eq ["util", "util_2", "app"]
    end
  end

  it "finds a package of the library by name" do
    with_tree({
      "app/main.spk"   => "require \"json\"\n#{MAIN_SPK}",
      "lib/json/j.spk" => "class J\nend\n",
    }) do |dir|
      library = File.join(dir, "lib")
      set = load_app(dir, library)
      set.units.map(&.name).should eq ["json", "app"]
      set.units.last.requires.should eq({"json" => File.join(library, "json")})
    end
  end

  it "leaves a name with no library package to Pony" do
    with_tree({
      "app/main.spk"   => "require \"collections\"\n#{MAIN_SPK}",
      "lib/json/j.spk" => "class J\nend\n",
    }) do |dir|
      set = load_app(dir, File.join(dir, "lib"))
      set.units.map(&.name).should eq ["app"]
      set.units.last.requires.should be_empty
    end
  end

  it "requires the prelude from every package outside it" do
    with_tree({
      "app/main.spk"            => "require \"./a\"\n#{MAIN_SPK}",
      "app/a/a.spk"             => "class A\nend\n",
      "lib/prelude/prelude.spk" => "primitive Greeting\nend\n",
    }) do |dir|
      library = File.join(dir, "lib")
      set = load_app(dir, library)
      set.units.map(&.name).should eq ["prelude", "a", "app"]
      set.units[0].implicit.should be_empty
      set.units[1].implicit.should eq [File.join(library, "prelude")]
      set.units[2].implicit.should eq [File.join(library, "prelude")]
    end
  end

  it "fails at a require of a missing package" do
    with_tree({"app/main.spk" => "require \"./x\"\n#{MAIN_SPK}"}) do |dir|
      error = expect_raises(PackageSet::Failure) { load_app(dir) }
      error.message.should eq "no Sparkle package at \"./x\": a directory of .spk files"
      error.file.should end_with "main.spk"
      error.error.line.should eq 1
    end
  end

  it "fails at the require that closes a cycle" do
    with_tree({
      "app/main.spk" => "require \"./a\"\n#{MAIN_SPK}",
      "app/a/a.spk"  => "require \"../b\"\nclass A\nend\n",
      "app/b/b.spk"  => "require \"../a\"\nclass B\nend\n",
    }) do |dir|
      error = expect_raises(PackageSet::Failure) { load_app(dir) }
      error.message.should eq "packages require each other: app -> a -> b -> a"
      error.file.should end_with "b.spk"
      error.error.line.should eq 1
    end
  end

  it "reports a parse error in a required file at that file" do
    with_tree({
      "app/main.spk" => "require \"./a\"\n#{MAIN_SPK}",
      "app/a/a.spk"  => "class A\n  def f\n    1 +\n  end\nend\n",
    }) do |dir|
      error = expect_raises(PackageSet::Failure) { load_app(dir) }
      error.file.should end_with "a.spk"
      error.source.should contain "def f"
    end
  end
end

describe "Driver.find_library" do
  it "prefers a non-empty environment value" do
    with_tree({"prefix/share/sparkle/stdlib/.keep" => ""}) do |dir|
      Driver.find_library("/opt/lib", File.join(dir, "prefix/bin/sparkle"), dir).should eq "/opt/lib"
      Driver.find_library("", File.join(dir, "prefix/bin/sparkle"), dir).should eq File.join(dir, "prefix/share/sparkle/stdlib")
    end
  end

  it "finds the library installed beside the executable" do
    with_tree({"prefix/share/sparkle/stdlib/.keep" => "", "prefix/bin/.keep" => ""}) do |dir|
      Driver.find_library(nil, File.join(dir, "prefix/bin/sparkle"), "/").should eq File.join(dir, "prefix/share/sparkle/stdlib")
    end
  end

  it "searches upward from the executable's prefix" do
    with_tree({"repo/stdlib/.keep" => "", "repo/bin/.keep" => ""}) do |dir|
      Driver.find_library(nil, File.join(dir, "repo/bin/sparkle"), "/").should eq File.join(dir, "repo/stdlib")
    end
  end

  it "searches upward from the working directory" do
    with_tree({"repo/stdlib/.keep" => "", "repo/sub/deeper/.keep" => ""}) do |dir|
      Driver.find_library(nil, nil, File.join(dir, "repo/sub/deeper")).should eq File.join(dir, "repo/stdlib")
    end
  end

  it "finds nothing when there is no library" do
    with_tree({"repo/sub/.keep" => ""}) do |dir|
      Driver.find_library(nil, nil, File.join(dir, "repo/sub")).should be_nil
    end
  end
end

describe "packages end to end" do
  if PACKAGES_PONYC.nil?
    pending "puts the library's prelude in scope without a require (ponyc not found)"
  else
    it "puts the library's prelude in scope without a require" do
      with_tree({
        "lib/prelude/prelude.spk" => "primitive Greeting\n  def text : String = \"hi from prelude\"\nend\n",
        "app/main.spk"            => "actor Main\n  def self.new(env : Env)\n    env.out <~ print(Greeting.text)\n  end\nend\n",
      }) do |dir|
        old = ENV["SPARKLE_LIB"]?
        ENV["SPARKLE_LIB"] = File.join(dir, "lib")
        begin
          err = IO::Memory.new
          code, binary = Driver.build(File.join(dir, "app"), File.join(dir, "bin"), err)
          code.should eq(0), err.to_s
          stdout = IO::Memory.new
          Process.run(binary || raise("no binary"), output: stdout, error: err).success?.should be_true
          stdout.to_s.should eq "hi from prelude\n"
        ensure
          ENV["SPARKLE_LIB"] = old
        end
      end
    end
  end
end
