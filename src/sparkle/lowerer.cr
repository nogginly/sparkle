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

    BINARY = {
      "+" => Tk::PLUS, "-" => Tk::MINUS, "*" => Tk::MULTIPLY, "/" => Tk::DIVIDE, "%" => Tk::REM,
      "==" => Tk::EQ, "!=" => Tk::NE, "<" => Tk::LT, "<=" => Tk::LE, ">" => Tk::GT, ">=" => Tk::GE,
    }

    @scope = Set(String).new
    @ivars = Set(String).new
    @method_names = Set(String).new
    @collections = false

    # `calls` holds the positions of the bare `x.name`s that are method calls;
    # `primed` is `Emitter.primed_params` over the package.
    def initialize(@tree : Ponyc::Tree, @calls : Set({Int32, Int32}) = Set({Int32, Int32}).new, @primed : Hash(String, Set(String)) = Hash(String, Set(String)).new)
    end

    # Appends the type declarations of `program`, read from `source` and
    # named `file` in error messages, to the tree.
    def lower(program : Program, file : String, source : String) : Nil
      @tree.open(file, source)
      @collections = false
      program.items.each do |item|
        case item
        when TypeDecl then @tree.add(entity(item))
        when EnumDecl then enum_decl(item).each { |node| @tree.add(node) }
        else               unsupported(item, "this declaration")
        end
      end
      @tree.use("collections") if @collections
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

    # One primitive per member, then the type alias that unions them, as in `Emitter#emit_enum`.
    private def enum_decl(d : EnumDecl) : Array(Node)
      nodes = d.members.map { |member| enum_member(d, member) }
      pos = at(d)
      union = d.members.map { |member| nominal("#{d.name}#{member.name}", pos) }.reduce { |left, right| @tree.node(Tk::UNIONTYPE, pos, [left, right]) }
      nodes << @tree.node(Tk::TYPE, pos, [id(d.name, pos), none, none, @tree.node(Tk::PROVIDES, pos, [union]), @tree.node(Tk::MEMBERS, pos), none, none], scope: true)
    end

    private def enum_member(d : EnumDecl, member : EnumMember) : Node
      unsupported(member, "a negative enum value") if member.value < 0
      pos = at(member)
      text = @tree.node(Tk::CALL, pos, [@tree.node(Tk::DOT, pos, [@tree.named(Tk::STRING, member.name, pos), id("clone", pos)]), none, none, none])
      methods = [
        enum_fun("value", nominal("I32", pos), @tree.int(member.value.to_u64, pos), pos),
        enum_fun("string", @tree.nominal("String", pos, Array(Node).new, Tk::ISO, Tk::EPHEMERAL), text, pos),
        enum_comparison("eq", d, false, pos),
        enum_comparison("ne", d, true, pos),
      ]
      @tree.node(Tk::PRIMITIVE, pos, [id("#{d.name}#{member.name}", pos), none, none, none, @tree.node(Tk::MEMBERS, pos, methods), none, none], scope: true)
    end

    # `fun eq(that: E): Bool => that is this`, or its negation.
    private def enum_comparison(name : String, d : EnumDecl, negated : Bool, pos : {Int32, Int32}) : Node
      same = @tree.node(Tk::IS, pos, [reference("that", pos), @tree.node(Tk::THIS, pos)])
      body = negated ? @tree.node(Tk::NOT, pos, [@tree.node(Tk::SEQ, pos, [same])]) : same
      params = @tree.node(Tk::PARAMS, pos, [@tree.node(Tk::PARAM, pos, [id("that", pos), nominal(d.name, pos), none])])
      enum_fun(name, nominal("Bool", pos), body, pos, params)
    end

    private def enum_fun(name : String, ret : Node, body : Node, pos : {Int32, Int32}, params : Node = none) : Node
      @tree.node(Tk::FUN, pos, [none, id(name, pos), none, params, ret, none, none, @tree.node(Tk::SEQ, pos, [body]), none], scope: true)
    end

    private def entity(d : TypeDecl) : Node
      unsupported(d, "more than one include") if d.includes.size > 1
      @ivars = d.fields.map(&.name).to_set
      @method_names = d.methods.map { |method| Emitter.pony_method_name(method.name, method.self_recv) }.to_set
      members = d.fields.map { |field| field(field) }
      members << implicit_constructor(d) if Emitter.implicit_constructor?(d)
      members.concat(d.methods.map { |method| method(method) })
      tparams = d.tparams.empty? ? none : @tree.node(Tk::TYPEPARAMS, at(d), d.tparams.map { |tparam| type_param(tparam) })
      provides = d.includes.empty? ? none : @tree.node(Tk::PROVIDES, at(d), d.includes.map { |trait| type(trait) })
      cap = d.cap
      cap_node = cap ? @tree.node(capability(d, cap), at(d)) : none
      @tree.node(ENTITIES[d.kind], at(d), [
        id(d.name, at(d)), tparams, cap_node, provides, @tree.node(Tk::MEMBERS, at(d), members), none, none,
      ], scope: true)
    end

    # A constraint written as a bare capability is `Any` with that capability.
    private def type_param(p : TypeParam) : Node
      constraint = p.constraint
      bound = case constraint
              when nil     then none
              when CapType then @tree.nominal("Any", at(constraint), [] of Node, capability(constraint, constraint.cap))
              else              type(constraint)
              end
      @tree.node(Tk::TYPEPARAM, at(p), [id(p.name, at(p)), bound, none])
    end

    private def capability(at : ::Sparkle::Node, cap : String) : Tk
      GENERIC_CAPS.includes?(cap) ? unsupported(at, "this capability") : (Tk.parse?(cap.upcase) || unsupported(at, "this capability"))
    end

    # A parameter, binding or local; primed when it equals a method name of
    # the enclosing type, because Pony forbids that overlap.
    private def local(name : String) : String
      n = Emitter.pony_ident(name)
      @method_names.includes?(n) ? "#{n}'" : n
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
      constructor = m.self_recv
      kind = m.kind == "be" ? Tk::BE : (constructor ? Tk::NEW : Tk::FUN)
      cap = m.cap
      cap ||= "ref" if !constructor && m.kind != "be" && Emitter.mutating_name?(m.name)
      cap_node = cap ? @tree.node(capability(m, cap), at(m)) : none
      name_at = {m.name_line, m.name_col}
      @scope = m.params.map(&.name).to_set
      params = m.params.map do |param|
        type = param.type || unsupported(param, "a parameter without a type")
        unsupported(param, "a default value") if param.default
        @tree.node(Tk::PARAM, at(param), [id(local(param.name), at(param)), type(type), none])
      end
      ret = m.ret
      returns_value = !constructor && m.kind != "be" && !(ret.nil? || PonyType.to_pony(ret) == "None")
      stmts = m.body
      body = stmts ? seq(m, stmts, returns_value, scope: false) : none
      partial = m.name.ends_with?('!') || m.name == "[]!"
      @tree.node(kind, at(m), [
        cap_node, id(Emitter.pony_method_name(m.name, constructor), name_at), none,
        params.empty? ? none : @tree.node(Tk::PARAMS, at(m), params),
        ret ? type(ret) : none, none, partial ? @tree.node(Tk::QUESTION, at(m)) : none, body, none,
      ], scope: true)
    end

    # A named type with its type arguments, capability and ephemeral marker,
    # or a union of types.
    private def type(t : TypeNode) : Node
      return @tree.node(Tk::UNIONTYPE, at(t), t.types.map { |member| type(member) }) if t.is_a?(UnionType)
      unsupported(t, "this type") unless t.is_a?(NamedType)
      cap = t.cap
      cap_id = cap && capability(t, cap)
      eph_id = case t.eph
               when "^" then Tk::EPHEMERAL
               when "!" then Tk::ALIASED
               end
      @tree.nominal(PonyType::TO_PONY[t.name]? || t.name, at(t), t.args.map { |arg| type(arg) }, cap_id, eph_id)
    end

    private def nominal(name : String, at : {Int32, Int32}) : Node
      @tree.nominal(name, at)
    end

    private def reference(name : String, at : {Int32, Int32}) : Node
      @tree.node(Tk::REFERENCE, at, [id(name, at)])
    end

    # A statement, or the value of the method when `value` is set.
    private def statement(e : Expr, value : Bool) : Node
      case e
      when Assign   then assign(e, value)
      when OpAssign then op_assign(e, value)
      when If       then if_(e, value)
      when Case     then case_(e, value)
      when Begin    then begin_(e, value)
      else               expr(e)
      end
    end

    # Names declared inside the block are forgotten after it.
    private def scoped(names : Array(String) = [] of String, &)
      saved = @scope.dup
      @scope.concat(names)
      result = yield
      @scope = saved
      result
    end

    # A `seq` of `stmts`, `None` when empty; the last is the value when `value` is set.
    private def seq(at : ::Sparkle::Node, stmts : Array(Expr), value : Bool, names : Array(String) = [] of String, scope : Bool = true) : Node
      children = scoped(names) { stmts.map_with_index { |stmt, i| statement(stmt, value && i == stmts.size - 1) } }
      children << reference("None", at(at)) if children.empty?
      @tree.node(Tk::SEQ, at(at), children, scope: scope)
    end

    private def single(e : Expr) : Node
      @tree.node(Tk::SEQ, at(e), [expr(e)])
    end

    private def if_(e : If, value : Bool) : Node
      unsupported(e, "this conditional") if e.negate || e.is_elsif || e.else_
      @tree.node(Tk::IF, at(e), [single(e.cond), seq(e, e.then_, value), none], scope: true)
    end

    private def ternary(e : Ternary) : Node
      @tree.node(Tk::IF, at(e), [single(e.cond), seq(e, [e.then_], true), seq(e, [e.else_], true)], scope: true)
    end

    private def begin_(e : Begin, value : Bool) : Node
      rescue_body = e.rescue_body
      unsupported(e, "this begin block") if rescue_body.nil? || e.ensure_body
      @tree.node(Tk::TRY, at(e), [seq(e, e.body, value), seq(e, rescue_body, value), none])
    end

    private def while_(e : While) : Node
      unsupported(e, "an inverted loop") if e.inverted
      @tree.node(Tk::WHILE, at(e), [single(e.cond), seq(e, e.body, false), none], scope: true)
    end

    private def case_(e : Case, value : Bool) : Node
      subject = e.subject
      head = subject.is_a?(TupleLit) ? tuple(subject, subject.items) : expr(subject)
      cases = e.whens.map { |branch| when_(branch, value) }
      other = e.else_
      match = @tree.node(Tk::MATCH, at(e), [
        @tree.node(Tk::SEQ, at(e), [head]),
        @tree.node(Tk::CASES, at(e), cases, scope: true),
        other ? seq(e, other, value) : none,
      ], scope: true)
      @tree.annotate(match, "exhaustive", at(e)) if e.exhaustive
      match
    end

    private def when_(branch : When, value : Bool) : Node
      unsupported(branch, "this pattern") unless branch.patterns.size == 1
      scoped do
        @tree.node(Tk::CASE, at(branch), [when_pattern(branch.patterns.first), none, seq(branch, branch.body, value, scope: false)], scope: true)
      end
    end

    private def when_pattern(pattern : Expr) : Node
      return pattern(pattern) unless pattern.is_a?(TuplePattern)
      items = pattern.items.map { |item| @tree.node(Tk::SEQ, at(item), [pattern(item)]) }
      @tree.node(Tk::TUPLE, at(pattern), items)
    end

    private def pattern(e : Expr) : Node
      case e
      when IntLit  then int(e)
      when EnumRef then @tree.node(Tk::LET, at(e), [id("_", at(e)), nominal("#{e.enum_name}#{e.member}", at(e))])
      when Ident   then e.name == "_" ? reference("_", at(e)) : unsupported(e, "a pattern that names a value")
      else              unsupported(e, "this pattern")
      end
    end

    private def unparen(e : Expr) : Expr
      e.is_a?(Paren) ? unparen(e.expr) : e
    end

    private def tuple(at : ::Sparkle::Node, items : Array(Expr)) : Node
      @tree.node(Tk::TUPLE, at(at), items.map { |item| single(item) })
    end

    private def binary(e : Binary) : Node
      return push(e) if e.op == "<<"
      kind = BINARY[e.op]? || unsupported(e, "this operator")
      @tree.node(kind, at(e), [operand(e.left), operand(e.right), none])
    end

    private def push(e : Binary) : Node
      name_at = at(e)
      callee = @tree.node(Tk::DOT, name_at, [expr(e.left), id("push", name_at)])
      args = @tree.node(Tk::POSITIONALARGS, name_at, [@tree.node(Tk::SEQ, at(e.right), [expr(e.right)])])
      @tree.node(Tk::CALL, name_at, [callee, args, none, none])
    end

    private def range(at : {Int32, Int32}, from : Node, to : Node, exclusive : Bool) : Node
      @collections = true
      type = @tree.node(Tk::QUALIFY, at, [reference("Range", at), @tree.node(Tk::TYPEARGS, at, [nominal("USize", at)])])
      callee = @tree.node(Tk::DOT, at, [type, id(exclusive ? "till" : "through", at)])
      args = [from, to].map { |bound| @tree.node(Tk::SEQ, at, [bound]) }
      @tree.node(Tk::CALL, at, [callee, @tree.node(Tk::POSITIONALARGS, at, args), none, none])
    end

    # `each`, `each_with_index` and `times` become `for` loops, as in `Emitter`.
    private def for_loop(c : Call, recv : Expr, block : Lambda) : Node
      names = block.params.map(&.name)
      fits = c.name == "each_with_index" ? names.size == 2 : names.size <= 1
      unsupported(c, "this block") unless Emitter::LOOP_METHODS.includes?(c.name) && c.args.empty? && c.named.empty? && fits
      iterable = @tree.node(Tk::SEQ, at(c), [loop_iterable(c, recv)])
      binding = loop_binding(c, block)
      @tree.node(Tk::FOR, at(c), [binding, iterable, seq(c, block.body, false, names, scope: false), none])
    end

    private def loop_iterable(c : Call, recv : Expr) : Node
      case c.name
      when "each"
        inner = unparen(recv)
        return range(at(c), expr(inner.from), expr(inner.to), inner.exclusive) if inner.is_a?(RangeLit)
        method_call(c, receiver(recv), "values")
      when "each_with_index" then method_call(c, receiver(recv), "pairs")
      else                        range(at(c), @tree.int(0_u64, at(c)), expr(recv), true)
      end
    end

    # `recv.name()`.
    private def method_call(at : ::Sparkle::Node, recv : Node, name : String) : Node
      @tree.node(Tk::CALL, at(at), [@tree.node(Tk::DOT, at(at), [recv, id(name, at(at))]), none, none, none])
    end

    # The loop variable, or `(index, element)` for `each_with_index`.
    private def loop_binding(c : Call, block : Lambda) : Node
      params = block.params
      lets = params.map { |param| @tree.node(Tk::LET, at(c), [id(local(param.name), at(param)), none]) }
      return lets.first? || @tree.node(Tk::LET, at(c), [id("_", at(c)), none]) unless c.name == "each_with_index"
      @tree.node(Tk::TUPLE, at(c), lets.reverse.map { |let| @tree.node(Tk::SEQ, at(c), [let]) })
    end

    # In value position the assignment becomes `(target = value; target)`.
    private def assign(e : Assign, value : Bool) : Node
      target = e.target
      if target.is_a?(IVarRef)
        unsupported(e, "a typed field assignment") if e.type
        name = "_#{target.name}"
        result = @tree.node(Tk::ASSIGN, at(e), [reference(name, at(target)), expr(e.value)])
        return value ? with_value(e, result, reference(name, at(target))) : result
      end
      unsupported(e, "this assignment") unless target.is_a?(Ident)
      rhs = expr(e.value)
      name = local(target.name)
      left = if @scope.includes?(target.name)
               reference(name, at(target))
             else
               @scope << target.name
               default = e.value
               declared = e.type
               type = if declared
                        type(declared)
                      elsif default.is_a?(IntLit) && default.suffix.nil?
                        nominal("I32", at(target))
                      else
                        none
                      end
               @tree.node(Tk::VAR, at(target), [id(name, at(target)), type])
             end
      result = @tree.node(Tk::ASSIGN, at(e), [left, rhs])
      value ? with_value(e, result, reference(name, at(target))) : result
    end

    private def op_assign(e : OpAssign, value : Bool) : Node
      target = e.target
      kind = BINARY[e.op]?
      unsupported(e, "this assignment") unless kind && (target.is_a?(IVarRef) || target.is_a?(Ident))
      name = target.is_a?(IVarRef) ? "_#{target.name}" : local(target.name)
      sum = @tree.node(kind, at(e), [reference(name, at(target)), operand(e.value), none])
      result = @tree.node(Tk::ASSIGN, at(e), [reference(name, at(target)), sum])
      value ? with_value(e, result, reference(name, at(target))) : result
    end

    private def with_value(e : Expr, assignment : Node, read : Node) : Node
      @tree.node(Tk::SEQ, at(e), [assignment, @tree.node(Tk::SEMI, at(e)), read])
    end

    # An operand of an operator, in parentheses unless it stands alone.
    private def operand(e : Expr) : Node
      e.is_a?(Unary | Consume) ? expr(e) : receiver(e)
    end

    # The receiver of a call, in parentheses unless it stands alone.
    private def receiver(e : Expr) : Node
      Emitter.atomic?(e) ? expr(e) : @tree.node(Tk::SEQ, at(e), [expr(e)])
    end

    private def int(e : IntLit) : Node
      value = e.text.delete('_').to_u64? unless e.suffix
      unsupported(e, "this integer literal") unless value
      @tree.int(value, at(e))
    end

    private def expr(e : Expr) : Node
      case e
      when Ident                                        then ident(e)
      when IVarRef                                      then reference("_#{e.name}", at(e))
      when IntLit                                       then int(e)
      when Assign                                       then assign(e, true)
      when OpAssign                                     then op_assign(e, true)
      when TypeRef                                      then type_ref(e)
      when EnumRef                                      then reference("#{e.enum_name}#{e.member}", at(e))
      when Call                                         then call(e)
      when FieldRead                                    then @tree.node(Tk::DOT, at(e), [receiver(e.recv), id("#{@ivars.includes?(e.name) ? "_" : ""}#{Emitter.pony_ident(e.name)}", at(e))])
      when Index                                        then index(e)
      when Paren                                        then paren(e)
      when NilLit                                       then reference("None", at(e))
      when StrLit                                       then string(e)
      when ArrayLit                                     then array(e)
      when Binary                                       then binary(e)
      when Consume                                      then @tree.node(Tk::CONSUME, at(e), [none, expr(e.expr)])
      when Recover                                      then recover(e)
      when Ternary, Begin, If, While, Case, Break, Next then control(e)
      else                                                   unsupported(e, "this expression")
      end
    end

    # An expression that steers the flow of control, in value position.
    private def control(e : Expr) : Node
      case e
      when Ternary then ternary(e)
      when Begin   then begin_(e, true)
      when If      then if_(e, true)
      when While   then while_(e)
      when Case    then case_(e, true)
      when Break   then @tree.node(Tk::BREAK, at(e), [none])
      when Next    then @tree.node(Tk::CONTINUE, at(e), [none])
      else              unsupported(e, "this expression")
      end
    end

    private def recover(e : Recover) : Node
      cap = e.cap
      cap_node = cap ? @tree.node(capability(e, cap), at(e)) : none
      @tree.node(Tk::RECOVER, at(e), [cap_node, seq(e, e.body, true)])
    end

    private def ident(e : Ident) : Node
      return reference(local(e.name), at(e)) if @scope.includes?(e.name)
      partial = e.name.ends_with?('!') ? @tree.node(Tk::QUESTION, at(e)) : none
      @tree.node(Tk::CALL, at(e), [reference(Emitter.pony_method_name(e.name, false), at(e)), none, none, partial])
    end

    private def paren(e : Paren) : Node
      inner = e.expr
      inner.is_a?(Assign | OpAssign) ? expr(inner) : @tree.node(Tk::SEQ, at(e), [expr(inner)])
    end

    # `recv[args]`, or `recv[args]!` when partial.
    private def index(e : Index) : Node
      args = e.args.map { |arg| @tree.node(Tk::SEQ, at(arg), [expr(arg)]) }
      partial = e.bang ? @tree.node(Tk::QUESTION, at(e)) : none
      @tree.node(Tk::CALL, at(e), [receiver(e.recv), args.empty? ? none : @tree.node(Tk::POSITIONALARGS, at(e), args), none, partial])
    end

    private def type_ref(e : TypeRef) : Node
      type = e.type
      unsupported(e, "this type") unless type.is_a?(NamedType) && type.cap.nil? && type.eph.nil?
      name = reference(PonyType::TO_PONY[type.name]? || type.name, at(e))
      return name if type.args.empty?
      args = @tree.node(Tk::TYPEARGS, at(e), type.args.map { |arg| type(arg) })
      @tree.node(Tk::QUALIFY, at(e), [name, args])
    end

    private def call(c : Call) : Node
      recv = c.recv
      if (block = c.block) && recv
        return for_loop(c, recv, block)
      end
      unsupported(c, "this call") if c.block
      name_at = {c.name_line, c.name_col}
      return @tree.node(Tk::SEQ, at(c), [@tree.node(Tk::IS, at(c), [receiver(recv), reference("None", at(c))])]) if recv && c.name == "nil?" && c.args.empty?
      method = Emitter.pony_method_name(c.name, recv.is_a?(TypeRef) && c.name == "new")
      name = id(method, name_at)
      callee = recv ? @tree.node(Tk::DOT, name_at, [receiver(recv), name]) : @tree.node(Tk::REFERENCE, name_at, [name])
      return callee if recv && !recv.is_a?(TypeRef) && bare?(c) && !@calls.includes?(name_at)
      args = c.args.map { |arg| @tree.node(Tk::SEQ, at(arg), [expr(arg)]) }
      partial = c.name.ends_with?('!') ? @tree.node(Tk::QUESTION, name_at) : none
      @tree.node(Tk::CALL, name_at, [callee, args.empty? ? none : @tree.node(Tk::POSITIONALARGS, name_at, args), named_args(c, method), partial])
    end

    # Named arguments, with the names of primed parameters primed as in `Emitter`.
    private def named_args(c : Call, method : String) : Node
      return none if c.named.empty?
      primed = @primed[method]?
      args = c.named.map do |arg|
        n = Emitter.pony_ident(arg.name)
        @tree.node(Tk::NAMEDARG, at(arg), [id(primed && primed.includes?(n) ? "#{n}'" : n, at(arg)), @tree.node(Tk::SEQ, at(arg.value), [expr(arg.value)])])
      end
      @tree.node(Tk::NAMEDARGS, at(c), args)
    end

    private def bare?(c : Call) : Bool
      c.args.empty? && !c.parens && !c.name.ends_with?('?') && !c.name.ends_with?('!')
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
          @tree.node(Tk::CALL, at(part), [@tree.node(Tk::DOT, at(part), [receiver(part), id("string", at(part))]), none, none, none])
        end
      end
      return @tree.named(Tk::STRING, e.parts.join, at(e)) if e.parts.all?(String)
      parts.unshift(@tree.named(Tk::STRING, "", at(e))) if parts.size == 1
      parts.reduce { |left, right| @tree.node(Tk::PLUS, at(e), [left, right, none]) }
    end

    # `Array[T].create()`.
    private def empty_array(e : ArrayLit, of_type : TypeNode) : Node
      type = @tree.node(Tk::QUALIFY, at(e), [reference("Array", at(e)), @tree.node(Tk::TYPEARGS, at(e), [type(of_type)])])
      method_call(e, type, "create")
    end

    private def array(e : ArrayLit) : Node
      of_type = e.of_type
      return empty_array(e, of_type || unsupported(e, "an empty array literal")) if e.elems.empty?
      # The parser keeps each `;` between elements as a leaf, which the sugar pass removes.
      elems = e.elems.flat_map { |elem| [@tree.node(Tk::SEMI, at(elem)), expr(elem)] }.skip(1)
      @tree.node(Tk::ARRAY, at(e), [of_type ? type(of_type) : none, @tree.node(Tk::SEQ, at(e), elems)])
    end
  end
end
