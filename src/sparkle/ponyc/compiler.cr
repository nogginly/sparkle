require "./lib_ponyc"
require "./tree"
require "./packages"

module Sparkle::Ponyc
  # Compiles a program whose packages are built as ASTs by the block, which
  # appends type declarations to the root's `Tree` and to those of the
  # packages it adds, into the binary `out_dir/bin_name`, using the standard library of the Pony
  # installation at `home`. Returns whether it succeeded and ponyc's error
  # text; errors are reported at the positions set on the nodes.
  def self.compile_tree(out_dir : String, bin_name : String, home : String, release : Bool = false, & : Packages -> Nil) : {Bool, String}
    with_options(out_dir, bin_name, home, release) do |opt|
      program = load_tree(opt, bin_name) { |packages| yield packages }
      next false if program.null?
      # The remaining passes resume from the parse pass on the new nodes.
      LibPonyc.spk_opt_set_limit(opt, LibPonyc.spk_pass_all)
      ok = LibPonyc.ast_passes_program(program, opt) && LibPonyc.generate_passes(program, opt)
      LibPonyc.ast_free(program)
      ok
    end
  end

  # The root package built by the block, printed as `ponyc --astmodule`
  # prints one.
  def self.tree_text(home : String, & : Packages -> Nil) : String
    text = ""
    with_options("", "text", home) do |opt|
      program = load_tree(opt, "text") { |packages| yield packages }
      next false if program.null?
      text = ast_text(LibPonyc.ast_child(program))
      LibPonyc.ast_free(program)
      true
    end
    text
  end

  # The Pony package in `dir` as ponyc's parser builds it, printed as
  # `ponyc --pass=parse --astmodule` prints it.
  def self.parse_text(dir : String, home : String) : String
    text = ""
    with_options("", "text", home) do |opt|
      LibPonyc.spk_opt_set_limit(opt, LibPonyc.spk_pass_parse)
      program = LibPonyc.program_load(File.expand_path(dir), opt)
      next false if program.null?
      text = ast_text(LibPonyc.ast_child(program))
      LibPonyc.ast_free(program)
      true
    end
    text
  end

  # Loads an empty in-memory package named `name`, parsed only, and lets the
  # block build into it and add the packages it requires. Returns the
  # program, or null when loading failed.
  private def self.load_tree(opt : LibPonyc::PassOpt, name : String, & : Packages -> Nil) : LibPonyc::Ast
    path = LibPonyc.stringtab(LibPonyc.spk_opt_strtab(opt), name)
    LibPonyc.module_add_magic_src(path, "", opt)
    LibPonyc.spk_opt_set_limit(opt, LibPonyc.spk_pass_parse)
    program = LibPonyc.program_load(path, opt)
    yield Packages.new(opt, program, Tree.new(opt, LibPonyc.ast_child(LibPonyc.ast_child(program))), "spk_") unless program.null?
    program
  end

  # The tree as ponyc prints it, then, when any node carries ponyc's
  # preserve flag, a `preserved:` line listing their child-index paths, which
  # the printed tree does not show.
  private def self.ast_text(ast : LibPonyc::Ast) : String
    text = LibPonyc.spk_ast_text(ast)
    printed = String.new(text).tap { LibC.free(text.as(Void*)) }
    paths = [] of String
    preserved(ast, "", paths)
    paths.empty? ? printed : "#{printed}preserved: #{paths.join(' ')}\n"
  end

  private def self.preserved(ast : LibPonyc::Ast, path : String, paths : Array(String)) : Nil
    child = LibPonyc.ast_child(ast)
    i = 0
    until child.null?
      at = path.empty? ? i.to_s : "#{path}.#{i}"
      paths << at if LibPonyc.ast_checkflag(child, LibPonyc.spk_flag_preserve) != 0
      preserved(child, at, paths)
      child = LibPonyc.ast_sibling(child)
      i += 1
    end
  end

  # Each error ponyc has reported: its file, line, column and message.
  def self.errors(opt : LibPonyc::PassOpt) : Array({String, Int32, Int32, String})
    found = [] of {String, Int32, Int32, String}
    error = LibPonyc.errors_get_first(LibPonyc.spk_opt_errors(opt))
    until error.null?
      msg = error.value
      file = msg.file.null? ? "" : String.new(msg.file)
      found << {file, msg.line.to_i32, msg.pos.to_i32, String.new(msg.msg)}
      error = msg.next
    end
    found
  end

  # Compiler options that search the standard library and runtime of the
  # Pony installation at `home`. Code generation is unoptimised unless
  # `release` is set.
  def self.options(out_dir : String, bin_name : String, home : String, release : Bool = false) : LibPonyc::PassOpt
    search = {File.join(home, "packages"), File.join(home, "lib", LIB_ARCH)}.join(Process::PATH_DELIMITER)
    opt = LibPonyc.spk_opt_new(out_dir, bin_name, search)
    LibPonyc.spk_opt_set_release(opt, release)
    opt
  end

  # Runs the block with initialised compiler options, then tears them down.
  # Returns the block's result (false when initialisation fails) and ponyc's error text.
  private def self.with_options(out_dir : String, bin_name : String, home : String, release : Bool = false, & : LibPonyc::PassOpt -> Bool) : {Bool, String}
    opt = options(out_dir, bin_name, home, release)
    ok = LibPonyc.spk_ponyc_init(opt)
    begin
      ok = yield opt if ok
      text = LibPonyc.spk_errors_text(opt)
      errors = text.null? ? "" : String.new(text)
      LibC.free(text.as(Void*)) unless text.null?
    ensure
      LibPonyc.ponyc_shutdown(opt)
      LibPonyc.spk_opt_free(opt)
    end
    {ok, errors || ""}
  end
end
