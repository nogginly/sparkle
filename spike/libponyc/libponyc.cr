@[Link(ldflags: "#{__DIR__}/build/shim.o #{__DIR__}/../../.tools/ponyc/lib/x86-64/libponyc-standalone.a #{__DIR__}/../../.tools/ponyc/lib/x86-64/libponyrt-pic.a -lz -ldl -lpthread -lm")]
lib LibPonyc
  type PassOpt = Void*
  type Ast = Void*
  type Errors = Void*
  type Strtab = Void*
  type Source = Void*

  fun spk_opt_new(output : LibC::Char*, bin_name : LibC::Char*) : PassOpt
  fun spk_opt_free(opt : PassOpt)
  fun spk_opt_set_limit(opt : PassOpt, limit : LibC::Int)
  fun spk_opt_errors(opt : PassOpt) : Errors
  fun spk_opt_strtab(opt : PassOpt) : Strtab
  fun spk_opt_reset_errors(opt : PassOpt)

  $spk_pass_parse : LibC::Int
  $spk_pass_all : LibC::Int
  $spk_pass_expr : LibC::Int
  $spk_tk_none : LibC::Int
  $spk_tk_actor : LibC::Int
  $spk_tk_members : LibC::Int
  $spk_tk_new : LibC::Int
  $spk_tk_id : LibC::Int
  $spk_tk_params : LibC::Int
  $spk_tk_param : LibC::Int
  $spk_tk_nominal : LibC::Int
  $spk_tk_seq : LibC::Int
  $spk_tk_call : LibC::Int
  $spk_tk_dot : LibC::Int
  $spk_tk_reference : LibC::Int
  $spk_tk_positionalargs : LibC::Int
  $spk_tk_string : LibC::Int
  $spk_tk_module : LibC::Int
  $spk_tk_file : LibC::Int

  fun ponyc_init(opt : PassOpt) : Bool
  fun ponyc_shutdown(opt : PassOpt)
  fun module_add_magic_src(path : LibC::Char*, src : LibC::Char*, opt : PassOpt)
  fun program_load(path : LibC::Char*, opt : PassOpt) : Ast
  fun ast_passes_program(program : Ast, opt : PassOpt) : Bool
  fun generate_passes(program : Ast, opt : PassOpt) : Bool
  fun ast_free(ast : Ast)
  fun errors_print(errors : Errors)
  fun errors_get_count(errors : Errors) : LibC::SizeT
  fun errors_get_first(errors : Errors) : ErrorMsg*

  struct ErrorMsg
    file : LibC::Char*
    line : LibC::SizeT
    pos : LibC::SizeT
    msg : LibC::Char*
    source : LibC::Char*
    frame : ErrorMsg*
    next : ErrorMsg*
  end

  fun ast_type(ast : Ast) : Ast
  fun ast_print_type(type : Ast, strtab : Strtab) : LibC::Char*
  fun ast_sibling(ast : Ast) : Ast
  fun ast_line(ast : Ast) : LibC::SizeT
  fun ast_pos(ast : Ast) : LibC::SizeT

  fun ast_blank(id : LibC::Int) : Ast
  fun ast_add(parent : Ast, child : Ast) : Ast
  fun ast_append(parent : Ast, child : Ast) : Ast
  fun ast_child(ast : Ast) : Ast
  fun ast_set_name(ast : Ast, name : LibC::Char*, strtab : Strtab)
  fun ast_setpos(ast : Ast, source : Source, line : LibC::SizeT, pos : LibC::SizeT)
  fun ast_source(ast : Ast) : Source
  fun ast_fprint(fp : Void*, ast : Ast, width : LibC::SizeT)
  fun ast_id(ast : Ast) : LibC::Int

  struct SourceT
    file : LibC::Char*
    m : LibC::Char*
    len : LibC::SizeT
  end

  fun fdopen(fd : LibC::Int, mode : LibC::Char*) : Void*
  fun source_open_string(src : LibC::Char*) : Source
  fun ast_scope(ast : Ast)
  fun stringtab(strtab : Strtab, s : LibC::Char*) : LibC::Char*
end
