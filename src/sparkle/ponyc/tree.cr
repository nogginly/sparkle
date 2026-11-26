require "./lib_ponyc"

module Sparkle::Ponyc
  # Builds ponyc AST nodes for one package, in the shape ponyc's parser
  # produces (`ponyc --pass=parse --astmodule` prints it). Nodes take their
  # positions from the source last given to `open`.
  class Tree
    alias Node = LibPonyc::Ast

    def initialize(@opt : LibPonyc::PassOpt, @file : Node)
      @strtab = LibPonyc.spk_opt_strtab(@opt)
      @source = Pointer(Void).null.as(LibPonyc::Source)
      @uses = Set(String).new
    end

    # Makes `text`, named `file` in error messages, the source of the
    # positions of the nodes built from here on.
    def open(file : String, text : String) : Nil
      @source = LibPonyc.spk_source_new(@opt, file, text)
    end

    # A node of kind `id` at line and column `at`, with `children` in order.
    # `scope` marks a node that holds a symbol table: a type or a method.
    def node(id : Tk, at : {Int32, Int32}? = nil, children : Array(Node) = [] of Node, scope : Bool = false) : Node
      n = LibPonyc.ast_blank(id.value)
      LibPonyc.ast_setpos(n, @source, at[0], at[1]) if at
      children.each { |child| LibPonyc.ast_append(n, child) }
      LibPonyc.ast_scope(n) if scope
      n
    end

    # A leaf that carries text: an identifier, or a string literal's value.
    def named(id : Tk, name : String, at : {Int32, Int32}? = nil) : Node
      n = node(id, at)
      LibPonyc.ast_set_name(n, name, @strtab)
      n
    end

    # An integer literal with `value`.
    def int(value : UInt64, at : {Int32, Int32}? = nil) : Node
      n = node(Tk::INT, at)
      LibPonyc.ast_int(n).value = LibPonyc::LexInt.new(low: value, high: 0_u64)
      n
    end

    # A float literal with `value`.
    def float(value : Float64, at : {Int32, Int32}? = nil) : Node
      template = node(Tk::FLOAT, at)
      n = LibPonyc.ast_from_float(template, value)
      LibPonyc.ast_free(template)
      n
    end

    # A named type: `name`, its type arguments, and an optional capability and
    # ephemeral (`^`) or aliased (`!`) marker, given as token kinds.
    def nominal(name : String, at : {Int32, Int32}, args : Array(Node) = [] of Node, cap : Tk? = nil, eph : Tk? = nil) : Node
      node(Tk::NOMINAL, at, [
        none, named(Tk::ID, name, at),
        args.empty? ? none : node(Tk::TYPEARGS, at, args),
        cap ? node(cap, at) : none,
        eph ? node(eph, at) : none,
      ])
    end

    # Marks `target` with the annotation `\name\`.
    def annotate(target : Node, name : String, at : {Int32, Int32}) : Nil
      elem = named(Tk::ID, name, at)
      LibPonyc.ast_append(elem, none)
      LibPonyc.ast_setannotation(target, node(Tk::ANNOTATION, at, [elem]))
    end

    # The placeholder for an absent optional child.
    # Marks `n` for ponyc's passes to leave as written, as its parser marks a
    # lambda's parameters, return type and body; returns `n`.
    def preserve(n : Node) : Node
      LibPonyc.ast_setflag(n, LibPonyc.spk_flag_preserve)
      n
    end

    def none : Node
      node(Tk::NONE)
    end

    # Puts `use "path"` before everything else in the package, once per path.
    def use(path : String) : Nil
      return unless @uses.add?(path)
      LibPonyc.ast_add(@file, node(Tk::USE, nil, [none, named(Tk::STRING, path), none]))
    end

    # Puts `use @decl` before everything else in the package.
    def use_ffi(decl : Node) : Nil
      LibPonyc.ast_add(@file, node(Tk::USE, nil, [none, decl, none]))
    end

    # Appends a type declaration to the package.
    def add(entity : Node) : Nil
      LibPonyc.ast_append(@file, entity)
    end
  end
end
