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

    # Type-checks the package built by the block, up to the expression pass;
    # returns each error's file, line, column and message.
    def check(& : Tree -> Nil) : Array({String, Int32, Int32, String})
      check(Set({String, Int32, Int32}).new) { |tree| yield tree }[0]
    end

    # As `check`, and also the printed type of the receiver of each call
    # whose method name is at one of `receivers` (file, line, column), such
    # as `Bag ref` or `Box[String val] ref`.
    def check(receivers : Set({String, Int32, Int32}), & : Tree -> Nil) : {Array({String, Int32, Int32, String}), Hash({String, Int32, Int32}, String)}
      types = {} of {String, Int32, Int32} => String
      round(LibPonyc.spk_pass_expr, receivers.empty? ? nil : ->(package : LibPonyc::Ast) { receiver_types(package, receivers, types) }) { |tree| yield tree }
      {Ponyc.errors(@opt), types}
    end

    # Runs every pass but code generation on the package built by the block;
    # returns whether it passed and ponyc's error text. Call it last: it
    # takes the loaded packages through the later passes too.
    def verify(& : Tree -> Nil) : {Bool, String}
      ok = round(LibPonyc.spk_pass_finaliser) { |tree| yield tree }
      text = LibPonyc.spk_errors_text(@opt)
      errors = text.null? ? "" : String.new(text)
      LibC.free(text.as(Void*)) unless text.null?
      {ok && errors.empty?, errors}
    end

    # Loads a new package, lets the block build it, runs the passes up to
    # `limit` over the program, and removes the package again.
    # After the expression pass a call is `(call (funref receiver name) ...)`.
    private def receiver_types(ast : LibPonyc::Ast, receivers : Set({String, Int32, Int32}), types : Hash({String, Int32, Int32}, String)) : Nil
      child = LibPonyc.ast_child(ast)
      until child.null?
        if LibPonyc.ast_id(child) == Tk::CALL.value
          file = LibPonyc.spk_ast_file(child)
          at = {file.null? ? "" : String.new(file), LibPonyc.ast_line(child).to_i32, LibPonyc.ast_pos(child).to_i32}
          if receivers.includes?(at) && !types.has_key?(at)
            callee = LibPonyc.ast_child(child)
            receiver = callee.null? ? callee : LibPonyc.ast_child(callee)
            type = receiver.null? ? receiver : LibPonyc.ast_type(receiver)
            types[at] = String.new(LibPonyc.ast_print_type(type, LibPonyc.spk_opt_strtab(@opt))) unless type.null?
          end
        end
        receiver_types(child, receivers, types)
        child = LibPonyc.ast_sibling(child)
      end
    end

    private def round(limit : LibC::Int, inspect : (LibPonyc::Ast -> Nil)? = nil, & : Tree -> Nil) : Bool
      @round += 1
      path = LibPonyc.stringtab(LibPonyc.spk_opt_strtab(@opt), "spk_round_#{@round}")
      LibPonyc.module_add_magic_src(path, "", @opt)
      LibPonyc.spk_errors_reset(@opt)
      package = LibPonyc.spk_module_load_parsed(@program, path, @opt)
      raise "ponyc failed to load a package" if package.null?
      begin
        yield Tree.new(@opt, LibPonyc.ast_child(package))
        LibPonyc.spk_opt_set_limit(@opt, limit)
        passed = LibPonyc.spk_program_passes(@program, @opt)
        inspect.try &.call(package)
        passed
      ensure
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
