require "spec"
require "file_utils"
require "../src/sparkle/driver"
require "../src/sparkle/cap_stats"

ROOT = File.expand_path("..", __DIR__)

RULE_HOME = Sparkle::Driver.find_ponyc(exe_path: File.join(ROOT, "bin", "sparkle"), cwd: ROOT).try { |ponyc| File.dirname(File.dirname(ponyc)) }

# Pins one translation rule: the lowerer builds the tree ponyc parses from `pony`.
# `calls` holds the positions of the bare `x.name`s that are method calls.
# Pending when ponyc is not found.
def rule(sparkle : String, pony : String, calls : Set({Int32, Int32}) = Set({Int32, Int32}).new) : Nil
  program = Sparkle::Parser.parse(sparkle)
  primed = Sparkle::Rules.primed_params([program])
  predicates = Sparkle::Rules.enum_predicates([program])
  lowers_as(program, sparkle, pony, calls, primed, predicates)
end

# Lowers `sparkle` and returns the tree text. Pending when ponyc is not found.
def lower(sparkle : String) : String
  home = RULE_HOME || pending!("ponyc not found")
  program = Sparkle::Parser.parse(sparkle)
  primed = Sparkle::Rules.primed_params([program])
  predicates = Sparkle::Rules.enum_predicates([program])
  Sparkle::Ponyc.tree_text(home) { |packages| Sparkle::Lowerer.new(packages.root, Set({Int32, Int32}).new, primed, predicates).lower(program, "main.spk", sparkle) }
end

# Asserts that the lowerer builds the tree ponyc parses from `pony`.
# Pending when ponyc is not found.
def lowers_as(program : Sparkle::Program, sparkle : String, pony : String, calls : Set({Int32, Int32}) = Set({Int32, Int32}).new, primed : Hash(String, Set(String)) = Hash(String, Set(String)).new, predicates : Sparkle::Rules::Predicates = Sparkle::Rules::Predicates.new) : Nil
  home = RULE_HOME || pending!("ponyc not found")
  dir = File.tempname("rule")
  Dir.mkdir_p(dir)
  begin
    File.write(File.join(dir, "main.pony"), pony)
    lowered = Sparkle::Ponyc.tree_text(home) { |packages| Sparkle::Lowerer.new(packages.root, calls, primed, predicates).lower(program, "main.spk", sparkle) }
    lowered.should eq Sparkle::Ponyc.parse_text(dir, home)
  ensure
    FileUtils.rm_rf(dir)
  end
end

def lex(source : String) : Array(Sparkle::Token)
  Sparkle::Lexer.new(source).tokenize
end
