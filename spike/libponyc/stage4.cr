require "./libponyc"

# A typeless front end's view of `env.out.print(env.args.size.string)`:
# every bare `x.name` might be a field or a method.
SPK = <<-SPK
  actor Main
    def self.new(env : Env)
      env.out.print(env.args.size.string)
    end
  end
  SPK

abstract class Expr
  getter line : Int32, col : Int32

  def initialize(@line, @col)
  end
end

class Ref < Expr
  getter name : String

  def initialize(line, col, @name)
    super(line, col)
  end
end

# `recv.name` with no parentheses; `col` is the dot's column, where ponyc reports.
class Dot < Expr
  getter recv : Expr, name : String

  def initialize(line, col, @recv, @name)
    super(line, col)
  end
end

class Call < Expr
  getter dot : Dot, args : Array(Expr)

  def initialize(line, col, @dot, @args)
    super(line, col)
  end
end

ROOT = Call.new(3, 13,
  Dot.new(3, 12, Dot.new(3, 8, Ref.new(3, 5, "env"), "out"), "print"),
  [Dot.new(3, 32, Dot.new(3, 27, Dot.new(3, 22, Ref.new(3, 19, "env"), "args"), "size"), "string")] of Expr)

ENV["PONYPATH"] = "#{__DIR__}/../../.tools/ponyc/packages:#{__DIR__}/../../.tools/ponyc/lib/x86-64"
OPT          = LibPonyc.spk_opt_new("#{__DIR__}/build", "stage4_hello")
STRTAB       = LibPonyc.spk_opt_strtab(OPT)
SOURCE       = LibPonyc.source_open_string(SPK)
SOURCE.as(LibPonyc::SourceT*).value.file = LibPonyc.stringtab(STRTAB, "main.spk")
METHOD_ERROR = "can't reference a method without calling it"

def tree(id : Int32, at : {Int32, Int32}?, children = [] of LibPonyc::Ast) : LibPonyc::Ast
  n = LibPonyc.ast_blank(id)
  LibPonyc.ast_setpos(n, SOURCE, at[0], at[1]) if at
  children.each { |child| LibPonyc.ast_append(n, child) }
  n
end

def named(id : Int32, name : String, at : {Int32, Int32}? = nil) : LibPonyc::Ast
  n = tree(id, at)
  LibPonyc.ast_set_name(n, name, STRTAB)
  n
end

def none : LibPonyc::Ast
  tree(LibPonyc.spk_tk_none, nil)
end

# Lowers `e`, emitting a bare dot as a call when its position is in `calls`.
def lower(e : Expr, calls : Set({Int32, Int32})) : LibPonyc::Ast
  case e
  when Ref
    tree(LibPonyc.spk_tk_reference, {e.line, e.col}, [named(LibPonyc.spk_tk_id, e.name, {e.line, e.col})])
  when Dot
    dot = lower_dot(e, calls)
    calls.includes?({e.line, e.col}) ? tree(LibPonyc.spk_tk_call, {e.line, e.col}, [dot, none, none, none]) : dot
  when Call
    args = e.args.map { |arg| tree(LibPonyc.spk_tk_seq, {arg.line, arg.col}, [lower(arg, calls)]) }
    tree(LibPonyc.spk_tk_call, {e.line, e.col}, [
      lower_dot(e.dot, calls), tree(LibPonyc.spk_tk_positionalargs, {e.line, e.col}, args), none, none,
    ])
  else
    raise "unknown node"
  end
end

def lower_dot(d : Dot, calls : Set({Int32, Int32})) : LibPonyc::Ast
  tree(LibPonyc.spk_tk_dot, {d.line, d.col}, [lower(d.recv, calls), named(LibPonyc.spk_tk_id, d.name, {d.line, d.col + 1})])
end

def actor(calls : Set({Int32, Int32})) : LibPonyc::Ast
  param = tree(LibPonyc.spk_tk_param, {2, 17}, [
    named(LibPonyc.spk_tk_id, "env", {2, 17}),
    tree(LibPonyc.spk_tk_nominal, {2, 23}, [none, named(LibPonyc.spk_tk_id, "Env", {2, 23}), none, none, none]),
    none,
  ])
  ctor = tree(LibPonyc.spk_tk_new, {2, 3}, [
    none, named(LibPonyc.spk_tk_id, "create", {2, 12}), none,
    tree(LibPonyc.spk_tk_params, {2, 16}, [param]),
    none, none, none,
    tree(LibPonyc.spk_tk_seq, {3, 5}, [lower(ROOT, calls)]),
    none,
  ])
  LibPonyc.ast_scope(ctor)
  a = tree(LibPonyc.spk_tk_actor, {1, 1}, [
    named(LibPonyc.spk_tk_id, "Main", {1, 7}), none, none, none,
    tree(LibPonyc.spk_tk_members, {2, 3}, [ctor]),
    none, none,
  ])
  LibPonyc.ast_scope(a)
  a
end

# Loads a program whose main module holds the actor, type-checked up to `limit`.
def check(calls : Set({Int32, Int32}), path : LibC::Char*) : {LibPonyc::Ast, Array(LibPonyc::ErrorMsg)}
  LibPonyc.spk_opt_reset_errors(OPT)
  LibPonyc.spk_opt_set_limit(OPT, LibPonyc.spk_pass_parse)
  program = LibPonyc.program_load(path, OPT)
  raise "program_load failed" if program.null?
  LibPonyc.ast_add(LibPonyc.ast_child(LibPonyc.ast_child(program)), actor(calls))
  LibPonyc.spk_opt_set_limit(OPT, LibPonyc.spk_pass_expr)
  LibPonyc.ast_passes_program(program, OPT)
  errors = [] of LibPonyc::ErrorMsg
  e = LibPonyc.errors_get_first(LibPonyc.spk_opt_errors(OPT))
  until e.null?
    errors << e.value
    e = e.value.next
  end
  {program, errors}
end

def each_call(ast : LibPonyc::Ast, &block : LibPonyc::Ast ->)
  return if ast.null?
  yield ast if LibPonyc.ast_id(ast) == LibPonyc.spk_tk_call
  child = LibPonyc.ast_child(ast)
  until child.null?
    each_call(child, &block)
    child = LibPonyc.ast_sibling(child)
  end
end

abort "ponyc_init failed" unless LibPonyc.ponyc_init(OPT)
path = LibPonyc.stringtab(STRTAB, "sparkle-main")
LibPonyc.module_add_magic_src(path, "", OPT)

calls = Set({Int32, Int32}).new
round = 0
loop do
  round += 1
  started = Time.instant
  program, errors = check(calls, path)
  elapsed = (Time.instant - started).total_seconds.round(2)
  found = errors.select { |e| String.new(e.msg) == METHOD_ERROR }.map { |e| {e.line.to_i, e.pos.to_i} }
  puts "round #{round} (#{elapsed}s): #{errors.size} errors; methods at #{found.empty? ? "none" : found.map { |l, c| "#{l}:#{c}" }.join(", ")}"
  if found.empty?
    unless errors.empty?
      LibPonyc.errors_print(LibPonyc.spk_opt_errors(OPT))
      abort "other errors"
    end
    each_call(LibPonyc.ast_child(LibPonyc.ast_child(program))) do |c|
      type = LibPonyc.ast_type(c)
      puts "  call at #{LibPonyc.ast_line(c)}:#{LibPonyc.ast_pos(c)} has type #{type.null? ? "?" : String.new(LibPonyc.ast_print_type(type, STRTAB))}"
    end
    LibPonyc.spk_opt_set_limit(OPT, LibPonyc.spk_pass_all)
    ok = LibPonyc.ast_passes_program(program, OPT) && LibPonyc.generate_passes(program, OPT)
    LibPonyc.errors_print(LibPonyc.spk_opt_errors(OPT))
    puts "compiled: #{ok}"
    break
  end
  LibPonyc.ast_free(program)
  calls.concat(found)
  abort "no progress" if round > 10
end
LibPonyc.ponyc_shutdown(OPT)
