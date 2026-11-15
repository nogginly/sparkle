require "./libponyc"

ENV["PONYPATH"] = "#{__DIR__}/../../.tools/ponyc/packages:#{__DIR__}/../../.tools/ponyc/lib/x86-64"
src = %(actor Main\n  new create(env: Env) =>\n    env.out.print("hello from Pony text, compiled in-process")\n)
opt = LibPonyc.spk_opt_new("#{__DIR__}/build", "stage2_hello")
ok = LibPonyc.ponyc_init(opt)
if ok
  path = LibPonyc.stringtab(LibPonyc.spk_opt_strtab(opt), "sparkle-main")
  LibPonyc.module_add_magic_src(path, src, opt)
  program = LibPonyc.program_load(path, opt)
  ok = !program.null? && LibPonyc.generate_passes(program, opt)
  LibPonyc.ast_free(program) unless program.null?
end
LibPonyc.errors_print(LibPonyc.spk_opt_errors(opt))
LibPonyc.ponyc_shutdown(opt)
LibPonyc.spk_opt_free(opt)
puts "compiled: #{ok}"
exit(ok ? 0 : 1)
