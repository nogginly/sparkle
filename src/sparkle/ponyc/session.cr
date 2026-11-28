require "./compiler"

module Sparkle::Ponyc
  # One compiler instance kept for many type checks. The standard library
  # packages a check uses are loaded and checked once; each later check
  # loads only the package built by its block, as a package of its own,
  # which is removed again afterwards. Call `close` when done.
  class Session
    @opt : LibPonyc::PassOpt
    @program : LibPonyc::Ast
    @round = 0

    # Starts ponyc with the Pony installation at `home`, and loads `builtin`.
    def initialize(home : String)
      @opt = Ponyc.options("", "check", home)
      raise "ponyc failed to start" unless LibPonyc.spk_ponyc_init(@opt)
      LibPonyc.spk_opt_set_limit(@opt, LibPonyc.spk_pass_expr)
      root = LibPonyc.stringtab(LibPonyc.spk_opt_strtab(@opt), "spk_session")
      LibPonyc.module_add_magic_src(root, "", @opt)
      @program = LibPonyc.program_load(root, @opt)
      raise "ponyc failed to load builtin" if @program.null?
    end

    # Type-checks the packages built by the block, up to the expression
    # pass; returns each error's file, line, column and message.
    def check(& : Packages -> Nil) : Array({String, Int32, Int32, String})
      check(Set({String, Int32, Int32}).new) { |packages| yield packages }.errors
    end

    # As `check`, and also the printed type of the receiver of each call
    # whose method name is at one of `receivers` (file, line, column), such
    # as `Bag ref` or `Box[String val] ref`, the positions of the calls
    # that reach a message handler (Pony's behaviour), and the printed type
    # of each local whose name starts with `spk_probe_`.
    def check(receivers : Set({String, Int32, Int32}), & : Packages -> Nil) : Report
      report = Report.new
      round(LibPonyc.spk_pass_expr, ->(package : LibPonyc::Ast) { inspect_calls(package, receivers, report) }) { |packages| yield packages }
      report.errors.concat(Ponyc.errors(@opt))
      report
    end

    # What one type check found; see `check`.
    class Report
      getter errors = [] of {String, Int32, Int32, String}
      getter types = {} of {String, Int32, Int32} => String
      getter handled = Set({String, Int32, Int32}).new
      getter probes = {} of String => String
    end

    # Runs every pass but code generation on the packages built by the block;
    # returns whether it passed and ponyc's error text. Call it last: it
    # takes the loaded packages through the later passes too.
    def verify(& : Packages -> Nil) : {Bool, String}
      ok = round(LibPonyc.spk_pass_finaliser) { |packages| yield packages }
      text = LibPonyc.spk_errors_text(@opt)
      errors = text.null? ? "" : String.new(text)
      LibC.free(text.as(Void*)) unless text.null?
      {ok && errors.empty?, errors}
    end

    # Loads a new root package, lets the block build it and add the packages
    # it requires, runs the passes up to `limit` over the program, lets
    # `inspect` read each of those packages, and removes them again.
    # After the expression pass a call is `(call (funref receiver name) ...)`,
    # or `(call (beref receiver name) ...)` for a message handler.
    private def inspect_calls(ast : LibPonyc::Ast, receivers : Set({String, Int32, Int32}), report : Report) : Nil
      types = report.types
      handled = report.handled
      child = LibPonyc.ast_child(ast)
      until child.null?
        id = LibPonyc.ast_id(child)
        if id == Tk::VAR.value || id == Tk::LET.value
          name = String.new(LibPonyc.ast_name(LibPonyc.ast_child(child)))
          type = LibPonyc.ast_type(child)
          report.probes[name] = String.new(LibPonyc.ast_print_type(type, LibPonyc.spk_opt_strtab(@opt))) if name.starts_with?("spk_probe_") && !type.null?
        end
        if id == Tk::CALL.value
          file = LibPonyc.spk_ast_file(child)
          at = {file.null? ? "" : String.new(file), LibPonyc.ast_line(child).to_i32, LibPonyc.ast_pos(child).to_i32}
          callee = LibPonyc.ast_child(child)
          handled << at if !callee.null? && LibPonyc.ast_id(callee) == Tk::BEREF.value
          if receivers.includes?(at) && !types.has_key?(at)
            receiver = callee.null? ? callee : LibPonyc.ast_child(callee)
            type = receiver.null? ? receiver : LibPonyc.ast_type(receiver)
            types[at] = String.new(LibPonyc.ast_print_type(type, LibPonyc.spk_opt_strtab(@opt))) unless type.null?
          end
        end
        inspect_calls(child, receivers, report)
        child = LibPonyc.ast_sibling(child)
      end
    end

    private def round(limit : LibC::Int, inspect : (LibPonyc::Ast -> Nil)? = nil, & : Packages -> Nil) : Bool
      @round += 1
      path = LibPonyc.stringtab(LibPonyc.spk_opt_strtab(@opt), "spk_round_#{@round}")
      LibPonyc.module_add_magic_src(path, "", @opt)
      LibPonyc.spk_errors_reset(@opt)
      package = LibPonyc.spk_module_load_parsed(@program, path, @opt)
      raise "ponyc failed to load a package" if package.null?
      packages = Packages.new(@opt, @program, Tree.new(@opt, LibPonyc.ast_child(package)), "spk_round_#{@round}_")
      begin
        yield packages
        LibPonyc.spk_opt_set_limit(@opt, limit)
        passed = LibPonyc.spk_program_passes(@program, @opt)
        inspect.try { |read| ([package] + packages.added).each { |each| read.call(each) } }
        passed
      ensure
        packages.added.each { |added| LibPonyc.ast_remove(added) }
        LibPonyc.ast_remove(package)
      end
    end

    def close : Nil
      LibPonyc.ast_free(@program) unless @program.null?
      LibPonyc.ponyc_shutdown(@opt)
      LibPonyc.spk_opt_free(@opt)
    end
  end
end
