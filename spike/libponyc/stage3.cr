require "./libponyc"

# The Sparkle source the nodes below claim to come from.
SPK = <<-SPK
  actor Main
    def self.new(env : Env)
      env.@out.#{ARGV[0]? == "bad" ? "prnt" : "print"}("hello from an AST built in Crystal")
    end
  end
  SPK

ENV["PONYPATH"] = "#{__DIR__}/../../.tools/ponyc/packages:#{__DIR__}/../../.tools/ponyc/lib/x86-64"
OPT    = LibPonyc.spk_opt_new("#{__DIR__}/build", "stage3_hello")
STRTAB = LibPonyc.spk_opt_strtab(OPT)
SOURCE = LibPonyc.source_open_string(SPK)
SOURCE.as(LibPonyc::SourceT*).value.file = LibPonyc.stringtab(STRTAB, "main.spk")

# Builds a node of kind `id` at Sparkle line and column `at`, with `children` in order.
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

def build_main : LibPonyc::Ast
  call = tree(LibPonyc.spk_tk_call, {3, 14}, [
    tree(LibPonyc.spk_tk_dot, {3, 13}, [
      tree(LibPonyc.spk_tk_dot, {3, 8}, [
        tree(LibPonyc.spk_tk_reference, {3, 5}, [named(LibPonyc.spk_tk_id, "env", {3, 5})]),
        named(LibPonyc.spk_tk_id, "out", {3, 9}),
      ]),
      named(LibPonyc.spk_tk_id, ARGV[0]? == "bad" ? "prnt" : "print", {3, 14}),
    ]),
    tree(LibPonyc.spk_tk_positionalargs, {3, 19}, [
      tree(LibPonyc.spk_tk_seq, {3, 20}, [named(LibPonyc.spk_tk_string, "hello from an AST built in Crystal", {3, 20})]),
    ]),
    none, none,
  ])
  param = tree(LibPonyc.spk_tk_param, {2, 17}, [
    named(LibPonyc.spk_tk_id, "env", {2, 17}),
    tree(LibPonyc.spk_tk_nominal, {2, 23}, [none, named(LibPonyc.spk_tk_id, "Env", {2, 23}), none, none, none]),
    none,
  ])
  ctor = tree(LibPonyc.spk_tk_new, {2, 3}, [
    none, named(LibPonyc.spk_tk_id, "create", {2, 12}), none,
    tree(LibPonyc.spk_tk_params, {2, 16}, [param]),
    none, none, none,
    tree(LibPonyc.spk_tk_seq, {3, 5}, [call]),
    none,
  ])
  LibPonyc.ast_scope(ctor)
  actor = tree(LibPonyc.spk_tk_actor, {1, 1}, [
    named(LibPonyc.spk_tk_id, "Main", {1, 7}), none, none, none,
    tree(LibPonyc.spk_tk_members, {2, 3}, [ctor]),
    none, none,
  ])
  LibPonyc.ast_scope(actor)
  actor
end

ok = LibPonyc.ponyc_init(OPT)
if ok
  path = LibPonyc.stringtab(STRTAB, "sparkle-main")
  LibPonyc.module_add_magic_src(path, "", OPT)
  LibPonyc.spk_opt_set_limit(OPT, LibPonyc.spk_pass_parse)
  program = LibPonyc.program_load(path, OPT)
  ok = !program.null?
  if ok
    file = LibPonyc.ast_child(LibPonyc.ast_child(program))
    LibPonyc.ast_add(file, build_main)
    if ENV["SPK_PRINT_AST"]?
      LibPonyc.ast_fprint(LibPonyc.fdopen(2, "w"), LibPonyc.ast_child(program), 100)
    end
    LibPonyc.spk_opt_set_limit(OPT, LibPonyc.spk_pass_all)
    ok = LibPonyc.ast_passes_program(program, OPT) && LibPonyc.generate_passes(program, OPT)
    LibPonyc.ast_free(program)
  end
end
LibPonyc.errors_print(LibPonyc.spk_opt_errors(OPT))
LibPonyc.ponyc_shutdown(OPT)
LibPonyc.spk_opt_free(OPT)
puts "compiled: #{ok}"
exit(ok ? 0 : 1)
