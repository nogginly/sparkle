require "spec"
require "../src/sparkle/driver"
require "../src/sparkle/cap_stats"

ROOT = File.expand_path("..", __DIR__)

def translate(source : String) : String
  Sparkle::Driver.translate(source).pony
end

# Wraps statements in `Main.new` and returns the generated constructor lines.
def main_body(statements : String) : Array(String)
  src = "actor Main\n  def self.new(env : Env)\n" + statements.lines.map { |l| "    #{l}\n" }.join + "  end\nend\n"
  lines = translate(src).lines.skip(1)
  lines[0] = lines[0].lstrip
  lines
end

def lex(source : String) : Array(Sparkle::Token)
  Sparkle::Lexer.new(source).tokenize
end
