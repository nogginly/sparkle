{% begin %}
  {% root = "#{__DIR__.id}/../../.." %}
  {% tools = "#{root.id}/.tools/ponyc" %}
  {% headers = "#{root.id}/vendor/ponyc/src" %}
  {% shim = "#{root.id}/bin/ponyc_shim.o" %}
  {% found = system("ls -d #{tools.id}/lib/*/libponyc-standalone.a 2>/dev/null | head -n 1").stringify.strip %}
  {% if found.empty? %}
    {% raise "Sparkle links the Pony compiler from .tools/ponyc: run `make ponyc` first" %}
  {% end %}
  {% unless file_exists?("#{headers.id}/libponyc/ponyc.h") %}
    {% raise "Sparkle needs the Pony headers from vendor/ponyc: run `git submodule update --init` first" %}
  {% end %}
  {% lib_dir = found.gsub(/\/libponyc-standalone\.a$/, "") %}
  {% arch = lib_dir.split("/").last %}
  {% runtime = file_exists?("#{lib_dir.id}/libponyrt-pic.a") ? "#{lib_dir.id}/libponyrt-pic.a" : "#{lib_dir.id}/libponyrt.a" %}
  {% system_libs = flag?(:darwin) ? "-lc++ -lz" : "-fuse-ld=lld -lz -ldl -lpthread -lm" %}
  {% system("mkdir -p #{root.id}/bin && cc -c -O1 -I#{headers.id}/libponyc -I#{headers.id}/common #{__DIR__.id}/shim.c -o #{shim.id}") %}

  # Bindings to the Pony compiler, linked in from the prebuilt release
  # that `make ponyc` installs.
  @[Link(ldflags: "{{ shim.id }} {{ found.id }} {{ runtime.id }} {{ system_libs.id }}")]
  lib LibPonyc
    type PassOpt = Void*
    type Ast = Void*
    type Errors = Void*
    type Strtab = Void*
    type Source = Void*

    struct ErrorMsg
      file : LibC::Char*
      line : LibC::SizeT
      pos : LibC::SizeT
      msg : LibC::Char*
      source : LibC::Char*
      frame : ErrorMsg*
      next : ErrorMsg*
    end

    $spk_pass_expr : LibC::Int
    fun spk_opt_set_limit(opt : PassOpt, limit : LibC::Int)
    fun spk_opt_errors(opt : PassOpt) : Errors
    fun errors_get_first(errors : Errors) : ErrorMsg*

    fun spk_opt_new(output : LibC::Char*, bin_name : LibC::Char*, search_paths : LibC::Char*) : PassOpt
    fun spk_opt_free(opt : PassOpt)
    fun spk_errors_text(opt : PassOpt) : LibC::Char*
    fun spk_ponyc_init(opt : PassOpt) : Bool
    fun ponyc_shutdown(opt : PassOpt)
    fun program_load(path : LibC::Char*, opt : PassOpt) : Ast
    fun generate_passes(program : Ast, opt : PassOpt) : Bool
    fun ast_free(ast : Ast)

    struct LexInt
      low : UInt64
      high : UInt64
    end

    fun ast_int(ast : Ast) : LexInt*
    fun ast_from_float(ast : Ast, value : Float64) : Ast

    $spk_pass_parse : LibC::Int
    $spk_pass_all : LibC::Int
    $spk_flag_preserve : LibC::UInt
    fun ast_setflag(ast : Ast, flag : UInt32)
    fun ast_checkflag(ast : Ast, flag : UInt32) : LibC::Int
    fun ast_sibling(ast : Ast) : Ast
    $spk_tk_actor : LibC::Int
    $spk_tk_last : LibC::Int
    fun spk_opt_strtab(opt : PassOpt) : Strtab
    fun spk_ast_text(ast : Ast) : LibC::Char*
    fun spk_source_new(opt : PassOpt, file : LibC::Char*, text : LibC::Char*) : Source
    fun stringtab(strtab : Strtab, string : LibC::Char*) : LibC::Char*
    fun module_add_magic_src(path : LibC::Char*, src : LibC::Char*, opt : PassOpt)
    fun ast_passes_program(program : Ast, opt : PassOpt) : Bool
    fun ast_blank(id : LibC::Int) : Ast
    fun ast_append(parent : Ast, child : Ast) : Ast
    fun ast_add(parent : Ast, child : Ast) : Ast
    fun ast_child(ast : Ast) : Ast
    fun ast_scope(ast : Ast)
    fun ast_setannotation(ast : Ast, annotation : Ast)
    fun ast_set_name(ast : Ast, name : LibC::Char*, strtab : Strtab)
    fun ast_setpos(ast : Ast, source : Source, line : LibC::SizeT, pos : LibC::SizeT)
  end

  {{ run("./token_ids", "#{headers.id}/libponyc/ast/token.h") }}

  module Sparkle::Ponyc
    # The architecture directory under a Pony installation's `lib/`,
    # as named by the release that was linked in.
    LIB_ARCH = {{ arch }}
  end
{% end %}
