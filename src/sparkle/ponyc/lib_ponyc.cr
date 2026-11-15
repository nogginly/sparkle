{% begin %}
  {% arch = flag?(:aarch64) ? "arm64" : "x86-64" %}
  {% tools = "#{__DIR__.id}/../../../.tools/ponyc" %}
  {% shim = "#{__DIR__.id}/../../../bin/ponyc_shim.o" %}
  {% headers = "#{__DIR__.id}/../../../vendor/ponyc/src" %}
  {% shim_cmd = "mkdir -p #{__DIR__.id}/../../../bin && cc -c -O1 -I#{headers.id}/libponyc -I#{headers.id}/common #{__DIR__.id}/shim.c -o #{shim.id}" %}
  {% system_libs = flag?(:darwin) ? "-lc++ -lz" : "-lz -ldl -lpthread -lm" %}
  {% unless file_exists?("#{tools.id}/lib/#{arch.id}/libponyc-standalone.a") %}
    {% raise "Sparkle links the Pony compiler from .tools/ponyc: run `make ponyc` first" %}
  {% end %}
  {% unless file_exists?("#{headers.id}/libponyc/ponyc.h") %}
    {% raise "Sparkle needs the Pony headers from vendor/ponyc: run `git submodule update --init` first" %}
  {% end %}
  {% system(shim_cmd) %}

  # Bindings to the Pony compiler, linked in from the prebuilt release
  # that `make ponyc` installs.
  @[Link(ldflags: "{{ shim.id }} {{ tools.id }}/lib/{{ arch.id }}/libponyc-standalone.a {{ tools.id }}/lib/{{ arch.id }}/libponyrt-pic.a {{ system_libs.id }}")]
  lib LibPonyc
    type PassOpt = Void*
    type Ast = Void*

    fun spk_opt_new(output : LibC::Char*, bin_name : LibC::Char*, search_paths : LibC::Char*) : PassOpt
    fun spk_opt_free(opt : PassOpt)
    fun spk_errors_text(opt : PassOpt) : LibC::Char*
    fun ponyc_init(opt : PassOpt) : Bool
    fun ponyc_shutdown(opt : PassOpt)
    fun program_load(path : LibC::Char*, opt : PassOpt) : Ast
    fun generate_passes(program : Ast, opt : PassOpt) : Bool
    fun ast_free(ast : Ast)
  end

  module Sparkle::Ponyc
    # The architecture directory under a Pony installation's `lib/`.
    LIB_ARCH = {{ arch }}
  end
{% end %}
