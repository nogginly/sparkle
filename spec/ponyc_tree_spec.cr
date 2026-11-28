require "./spec_helper"

include Sparkle

private HOME = Driver.find_ponyc(exe_path: File.join(ROOT, "bin", "sparkle"), cwd: ROOT).try { |ponyc| File.dirname(File.dirname(ponyc)) }

# Builds `actor Main` whose constructor calls `env.out.<method>("hello from a tree")`.
private def hello(tree : Ponyc::Tree, method : String) : Nil
  tree.open("main.spk", "actor Main\n  def self.new(env : Env)\n    env.out.#{method}(\"hello from a tree\")\n  end\nend\n")
  call = tree.node(Ponyc::Tk::CALL, {3, 14}, [
    tree.node(Ponyc::Tk::DOT, {3, 12}, [
      tree.node(Ponyc::Tk::DOT, {3, 8}, [
        tree.node(Ponyc::Tk::REFERENCE, {3, 5}, [tree.named(Ponyc::Tk::ID, "env", {3, 5})]),
        tree.named(Ponyc::Tk::ID, "out", {3, 9}),
      ]),
      tree.named(Ponyc::Tk::ID, method, {3, 13}),
    ]),
    tree.node(Ponyc::Tk::POSITIONALARGS, {3, 18}, [
      tree.node(Ponyc::Tk::SEQ, {3, 19}, [tree.named(Ponyc::Tk::STRING, "hello from a tree", {3, 19})]),
    ]),
    tree.none, tree.none,
  ])
  param = tree.node(Ponyc::Tk::PARAM, {2, 16}, [
    tree.named(Ponyc::Tk::ID, "env", {2, 16}),
    tree.node(Ponyc::Tk::NOMINAL, {2, 22}, [tree.none, tree.named(Ponyc::Tk::ID, "Env", {2, 22}), tree.none, tree.none, tree.none]),
    tree.none,
  ])
  constructor = tree.node(Ponyc::Tk::NEW, {2, 3}, [
    tree.none, tree.named(Ponyc::Tk::ID, "create", {2, 12}), tree.none,
    tree.node(Ponyc::Tk::PARAMS, {2, 15}, [param]),
    tree.none, tree.none, tree.none,
    tree.node(Ponyc::Tk::SEQ, {3, 5}, [call]),
    tree.none,
  ], scope: true)
  tree.add tree.node(Ponyc::Tk::ACTOR, {1, 1}, [
    tree.named(Ponyc::Tk::ID, "Main", {1, 7}), tree.none, tree.none, tree.none,
    tree.node(Ponyc::Tk::MEMBERS, {2, 3}, [constructor]),
    tree.none, tree.none,
  ], scope: true)
end

describe Ponyc::Tree do
  it "takes token ids from the headers the shim was compiled against" do
    Ponyc::Tk::EOF.value.should eq 0
    Ponyc::Tk::ACTOR.value.should eq LibPonyc.spk_tk_actor
    Ponyc::Tk::TEST_EXTRA.value.should eq LibPonyc.spk_tk_last
    Ponyc::Tk.values.size.should eq LibPonyc.spk_tk_last + 1
  end

  if home = HOME
    out_dir = File.join(ROOT, ".sparkle", "bin")

    it "compiles a program built as an AST" do
      Dir.mkdir_p(out_dir)
      ok, errors = Ponyc.compile_tree(out_dir, "tree_hello", home) { |packages| hello(packages.root, "print") }
      ok.should be_true, errors
      output = IO::Memory.new
      Process.run(File.join(out_dir, "tree_hello"), output: output).success?.should be_true
      output.to_s.should eq "hello from a tree\n"
    end

    it "reports errors at the positions set on the nodes" do
      Dir.mkdir_p(out_dir)
      ok, errors = Ponyc.compile_tree(out_dir, "tree_bad", home) { |packages| hello(packages.root, "prnt") }
      ok.should be_false
      errors.should contain "main.spk:3:12: couldn't find 'prnt' in 'OutStream'"
      errors.should contain "    env.out.prnt(\"hello from a tree\")\n           ^"
    end
  else
    pending "compiles a program built as an AST (ponyc not found)"
  end
end
