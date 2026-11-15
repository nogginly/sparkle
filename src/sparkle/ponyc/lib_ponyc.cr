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
    # The architecture directory under a Pony installation's `lib/`,
    # as named by the release that was linked in.
    LIB_ARCH = {{ arch }}
  end
{% end %}
