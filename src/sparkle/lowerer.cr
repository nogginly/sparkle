require "./ast"
require "./emitter"
require "./pony_type"
require "./ponyc/tree"

module Sparkle
  # Lowers a Sparkle program to ponyc AST nodes, in the shape ponyc's parser
  # builds for the Pony that `Emitter` writes. Constructs it cannot lower yet
  # raise a `ParseError` at their position.
  class Lowerer
    alias Node = Ponyc::Tree::Node
    alias Tk = Ponyc::Tk

    ENTITIES = {"actor" => Tk::ACTOR, "class" => Tk::CLASS, "struct" => Tk::STRUCT, "primitive" => Tk::PRIMITIVE, "trait" => Tk::TRAIT, "interface" => Tk::INTERFACE}

    @scope = Set(String).new

    # `calls` holds the positions of the bare `x.name`s that are method calls.
    def initialize(@tree : Ponyc::Tree, @calls : Set({Int32, Int32}) = Set({Int32, Int32}).new)
    end

    # Appends the type declarations of `program`, read from `source` and
    # named `file` in error messages, to the tree.
    def lower(program : Program, file : String, source : String) : Nil
      @tree.open(file, source)
      program.items.each do |item|
        case item
        when TypeDecl then @tree.add(entity(item))
        else               unsupported(item, "this declaration")
        end
      end
    end

    private def unsupported(node : ::Sparkle::Node, what : String) : NoReturn
      raise ParseError.new("the AST path does not lower #{what} yet", node.line, node.col)
    end

    private def at(node : ::Sparkle::Node) : {Int32, Int32}
      {node.line, node.col}
    end

    private def none : Node
      @tree.none
    end

    private def id(name : String, at : {Int32, Int32}) : Node
      @tree.named(Tk::ID, name, at)
    end

    private def entity(d : TypeDecl) : Node
      unsupported(d, "capabilities, type parameters, includes or fields on a type") if d.cap || !d.tparams.empty? || !d.includes.empty? || !d.fields.empty?
      members = d.methods.map { |method| method(method) }
      @tree.node(ENTITIES[d.kind], at(d), [
        id(d.name, at(d)), none, none, none, @tree.node(Tk::MEMBERS, at(d), members), none, none,
      ], scope: true)
    end

    private def method(m : Method) : Node
      unsupported(m, "this kind of method") if m.cap || m.ret || m.body.nil? || m.name.ends_with?('!')
      kind = m.kind == "be" ? Tk::BE : (m.self_recv ? Tk::NEW : Tk::FUN)
      name_at = {m.name_line, m.name_col}
      @scope = m.params.map(&.name).to_set
      params = m.params.map do |param|
        type = param.type || unsupported(param, "a parameter without a type")
        unsupported(param, "a default value") if param.default
        @tree.node(Tk::PARAM, at(param), [id(Emitter.pony_ident(param.name), at(param)), type(type), none])
      end
      body = (m.body || [] of Expr).map { |stmt| statement(stmt) }
      body << @tree.node(Tk::REFERENCE, at(m), [id("None", at(m))]) if body.empty?
      @tree.node(kind, at(m), [
        none, id(Emitter.pony_method_name(m.name, m.self_recv), name_at), none,
        params.empty? ? none : @tree.node(Tk::PARAMS, at(m), params),
        none, none, none, @tree.node(Tk::SEQ, at(m), body), none,
      ], scope: true)
    end

    private def type(t : TypeNode) : Node
      unsupported(t, "this type") unless t.is_a?(NamedType) && t.args.empty? && t.cap.nil? && t.eph.nil?
      @tree.node(Tk::NOMINAL, at(t), [none, id(PonyType::TO_PONY[t.name]? || t.name, at(t)), none, none, none])
    end

    private def statement(e : Expr) : Node
      return expr(e) unless e.is_a?(Assign)
      target = e.target
      unsupported(e, "this assignment") unless target.is_a?(Ident) && e.type.nil?
      value = expr(e.value)
      name = id(Emitter.pony_ident(target.name), at(target))
      left = if @scope.includes?(target.name)
               @tree.node(Tk::REFERENCE, at(target), [name])
             else
               @scope << target.name
               @tree.node(Tk::VAR, at(target), [name, none])
             end
      @tree.node(Tk::ASSIGN, at(e), [left, value])
    end

    private def expr(e : Expr) : Node
      case e
      when Ident     then ident(e)
      when Call      then call(e)
      when FieldRead then @tree.node(Tk::DOT, at(e), [expr(e.recv), id(e.name, at(e))])
      when StrLit    then string(e)
      when ArrayLit  then array(e)
      else                unsupported(e, "this expression")
      end
    end

    private def ident(e : Ident) : Node
      reference = @tree.node(Tk::REFERENCE, at(e), [id(Emitter.pony_ident(e.name), at(e))])
      @scope.includes?(e.name) ? reference : @tree.node(Tk::CALL, at(e), [reference, none, none, none])
    end

    private def call(c : Call) : Node
      recv = c.recv
      unsupported(c, "this call") if recv.is_a?(TypeRef) || !c.named.empty? || c.block || c.name.ends_with?('!') || c.name == "nil?"
      name_at = {c.name_line, c.name_col}
      name = id(Emitter.pony_method_name(c.name, false), name_at)
      callee = recv ? @tree.node(Tk::DOT, name_at, [expr(recv), name]) : @tree.node(Tk::REFERENCE, name_at, [name])
      return callee if recv && bare?(c) && !@calls.includes?(name_at)
      args = c.args.map { |arg| @tree.node(Tk::SEQ, at(arg), [expr(arg)]) }
      @tree.node(Tk::CALL, name_at, [callee, args.empty? ? none : @tree.node(Tk::POSITIONALARGS, name_at, args), none, none])
    end

    private def bare?(c : Call) : Bool
      c.args.empty? && !c.parens && !c.name.ends_with?('?')
    end

    # Parts joined with `+`; an interpolated expression has `string` called on it.
    private def string(e : StrLit) : Node
      parts = e.parts.map do |part|
        case part
        in String
          unsupported(e, "an escape in a string") if part.includes?('\\')
          @tree.named(Tk::STRING, part, at(e))
        in Expr
          next expr(part) if part.is_a?(StrLit) && part.parts.all?(String)
          @tree.node(Tk::CALL, at(part), [@tree.node(Tk::DOT, at(part), [expr(part), id("string", at(part))]), none, none, none])
        end
      end
      return @tree.named(Tk::STRING, e.parts.join, at(e)) if e.parts.all?(String)
      parts.unshift(@tree.named(Tk::STRING, "", at(e))) if parts.size == 1
      parts.reduce { |left, right| @tree.node(Tk::PLUS, at(e), [left, right, none]) }
    end

    private def array(e : ArrayLit) : Node
      unsupported(e, "a typed or empty array literal") if e.of_type || e.elems.empty?
      # The parser keeps each `;` between elements as a leaf, which the sugar pass removes.
      elems = e.elems.flat_map { |elem| [@tree.node(Tk::SEMI, at(elem)), expr(elem)] }.skip(1)
      @tree.node(Tk::ARRAY, at(e), [none, @tree.node(Tk::SEQ, at(e), elems)])
    end
  end
end
