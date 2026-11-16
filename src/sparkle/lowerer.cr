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
    @ivars = Set(String).new

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
      unsupported(d, "capabilities, type parameters or includes on a type") if d.cap || !d.tparams.empty? || !d.includes.empty?
      @ivars = d.fields.map(&.name).to_set
      members = d.fields.map { |field| field(field) }
      members << implicit_constructor(d) if Emitter.implicit_constructor?(d)
      members.concat(d.methods.map { |method| method(method) })
      @tree.node(ENTITIES[d.kind], at(d), [
        id(d.name, at(d)), none, none, none, @tree.node(Tk::MEMBERS, at(d), members), none, none,
      ], scope: true)
    end

    private def field(f : Field) : Node
      @scope = Set(String).new
      type = f.type || unsupported(f, "a field without a type")
      init = f.init
      @tree.node(Tk::FVAR, at(f), [id("_#{f.name}", at(f)), type(type), init ? expr(init) : none, none])
    end

    private def implicit_constructor(d : TypeDecl) : Node
      constructor(d, id("create", at(d)), none, [reference("None", at(d))])
    end

    private def constructor(at : ::Sparkle::Node, name : Node, params : Node, body : Array(Node)) : Node
      @tree.node(Tk::NEW, at(at), [none, name, none, params, none, none, none, @tree.node(Tk::SEQ, at(at), body), none], scope: true)
    end

    private def method(m : Method) : Node
      unsupported(m, "this kind of method") if m.body.nil? || m.name.ends_with?('!')
      constructor = m.self_recv
      kind = m.kind == "be" ? Tk::BE : (constructor ? Tk::NEW : Tk::FUN)
      cap = m.cap
      cap ||= "ref" if !constructor && m.kind != "be" && Emitter.mutating_name?(m.name)
      cap_node = cap ? @tree.node(Tk.parse?(cap.upcase) || unsupported(m, "this capability"), at(m)) : none
      name_at = {m.name_line, m.name_col}
      @scope = m.params.map(&.name).to_set
      params = m.params.map do |param|
        type = param.type || unsupported(param, "a parameter without a type")
        unsupported(param, "a default value") if param.default
        @tree.node(Tk::PARAM, at(param), [id(Emitter.pony_ident(param.name), at(param)), type(type), none])
      end
      ret = m.ret
      returns_value = !constructor && m.kind != "be" && !(ret.nil? || PonyType.to_pony(ret) == "None")
      stmts = m.body || [] of Expr
      body = stmts.map_with_index { |stmt, i| statement(stmt, returns_value && i == stmts.size - 1) }
      body << reference("None", at(m)) if body.empty?
      @tree.node(kind, at(m), [
        cap_node, id(Emitter.pony_method_name(m.name, constructor), name_at), none,
        params.empty? ? none : @tree.node(Tk::PARAMS, at(m), params),
        ret ? type(ret) : none, none, none, @tree.node(Tk::SEQ, at(m), body), none,
      ], scope: true)
    end

    private def type(t : TypeNode) : Node
      unsupported(t, "this type") unless t.is_a?(NamedType) && t.args.empty? && t.cap.nil? && t.eph.nil?
      nominal(PonyType::TO_PONY[t.name]? || t.name, at(t))
    end

    private def nominal(name : String, at : {Int32, Int32}) : Node
      @tree.node(Tk::NOMINAL, at, [none, id(name, at), none, none, none])
    end

    private def reference(name : String, at : {Int32, Int32}) : Node
      @tree.node(Tk::REFERENCE, at, [id(name, at)])
    end

    # A statement, or the value of the method when `value` is set.
    private def statement(e : Expr, value : Bool) : Node
      case e
      when Assign   then assign(e, value)
      when OpAssign then op_assign(e, value)
      else               expr(e)
      end
    end

    # In value position the assignment becomes `(target = value; target)`.
    private def assign(e : Assign, value : Bool) : Node
      target = e.target
      unsupported(e, "this assignment") unless target.is_a?(Ident) && e.type.nil?
      rhs = expr(e.value)
      name = Emitter.pony_ident(target.name)
      left = if @scope.includes?(target.name)
               reference(name, at(target))
             else
               @scope << target.name
               default = e.value
               type = default.is_a?(IntLit) && default.suffix.nil? ? nominal("I32", at(target)) : none
               @tree.node(Tk::VAR, at(target), [id(name, at(target)), type])
             end
      result = @tree.node(Tk::ASSIGN, at(e), [left, rhs])
      value ? with_value(e, result, reference(name, at(target))) : result
    end

    private def op_assign(e : OpAssign, value : Bool) : Node
      target = e.target
      unsupported(e, "this assignment") unless target.is_a?(IVarRef) && e.op == "+"
      name = "_#{target.name}"
      sum = @tree.node(Tk::PLUS, at(e), [reference(name, at(target)), operand(e.value), none])
      result = @tree.node(Tk::ASSIGN, at(e), [reference(name, at(target)), sum])
      value ? with_value(e, result, reference(name, at(target))) : result
    end

    private def with_value(e : Expr, assignment : Node, read : Node) : Node
      @tree.node(Tk::SEQ, at(e), [assignment, @tree.node(Tk::SEMI, at(e)), read])
    end

    private def operand(e : Expr) : Node
      unsupported(e, "this operand") unless e.is_a?(IntLit | IVarRef | Ident | Call | FieldRead)
      expr(e)
    end

    private def int(e : IntLit) : Node
      value = e.text.delete('_').to_u64? unless e.suffix
      unsupported(e, "this integer literal") unless value
      @tree.int(value, at(e))
    end

    private def expr(e : Expr) : Node
      case e
      when Ident     then ident(e)
      when IVarRef   then reference("_#{e.name}", at(e))
      when IntLit    then int(e)
      when Assign    then assign(e, true)
      when OpAssign  then op_assign(e, true)
      when TypeRef   then type_ref(e)
      when Call      then call(e)
      when FieldRead then @tree.node(Tk::DOT, at(e), [expr(e.recv), id("#{@ivars.includes?(e.name) ? "_" : ""}#{e.name}", at(e))])
      when StrLit    then string(e)
      when ArrayLit  then array(e)
      else                unsupported(e, "this expression")
      end
    end

    private def ident(e : Ident) : Node
      reference = @tree.node(Tk::REFERENCE, at(e), [id(Emitter.pony_ident(e.name), at(e))])
      @scope.includes?(e.name) ? reference : @tree.node(Tk::CALL, at(e), [reference, none, none, none])
    end

    private def type_ref(e : TypeRef) : Node
      type = e.type
      unsupported(e, "this type") unless type.is_a?(NamedType) && type.args.empty? && type.cap.nil? && type.eph.nil?
      reference(PonyType::TO_PONY[type.name]? || type.name, at(e))
    end

    private def call(c : Call) : Node
      recv = c.recv
      unsupported(c, "this call") if !c.named.empty? || c.block || c.name.ends_with?('!') || c.name == "nil?"
      name_at = {c.name_line, c.name_col}
      name = id(Emitter.pony_method_name(c.name, recv.is_a?(TypeRef) && c.name == "new"), name_at)
      callee = recv ? @tree.node(Tk::DOT, name_at, [expr(recv), name]) : @tree.node(Tk::REFERENCE, name_at, [name])
      return callee if recv && !recv.is_a?(TypeRef) && bare?(c) && !@calls.includes?(name_at)
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
