# Spike: can a type-check round tell the type of a block's value? The site
# `xs.map { |x| x * 2 }` is lowered, for one round, as a loop whose body binds
# the block's value to a probe local; after ponyc's expression pass the
# local's type is read from its declaration.
# Run: crystal run spike/enumerable/probe.cr
require "../../src/sparkle/driver"

SOURCE = <<-PONY
  actor Main
    new create(env: Env) =>
      let xs: Array[U32] = [1; 2; 3]
      let names = ["a"; "bb"]
      for x in xs.values() do
        let probe_1 = x * 2
      end
      for n in names.values() do
        let probe_2 = n.size() > 1
      end
      for n in names.values() do
        let probe_3 = (n, n.size())
      end
  PONY

def find_probes(ast : LibPonyc::Ast, strtab, found : Hash(String, String)) : Nil
  child = LibPonyc.ast_child(ast)
  until child.null?
    if LibPonyc.ast_id(child) == Sparkle::Ponyc::Tk::LET.value
      id = LibPonyc.ast_child(child)
      text = LibPonyc.spk_ast_text(id)
      name = String.new(text).strip
      type = LibPonyc.ast_type(child)
      found[name] = String.new(LibPonyc.ast_print_type(type, strtab)) unless type.null?
    end
    find_probes(child, strtab, found)
    child = LibPonyc.ast_sibling(child)
  end
end

home = Sparkle::Driver.find_pony_home || raise "no ponyc"
opt = Sparkle::Ponyc.options("", "probe", home)
raise "init" unless LibPonyc.spk_ponyc_init(opt)
strtab = LibPonyc.spk_opt_strtab(opt)
path = LibPonyc.stringtab(strtab, "probe")
LibPonyc.module_add_magic_src(path, SOURCE, opt)
LibPonyc.spk_opt_set_limit(opt, LibPonyc.spk_pass_expr)
program = LibPonyc.program_load(path, opt)
raise "load failed: #{String.new(LibPonyc.spk_errors_text(opt))}" if program.null?
found = {} of String => String
find_probes(program, strtab, found)
found.each { |name, type| puts "#{name} : #{type}" }
