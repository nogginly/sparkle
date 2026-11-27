require "./ast"
require "./rules"
require "./pony_type"

module Sparkle
  # Rewrites contract clauses (`expects`, `guarantees`, `maintains`) into
  # plain methods, before lowering. A method with clauses becomes a wrapper
  # that checks them around its body, renamed `_spk_name`; a constructor
  # checks them before and after its own body; a type's `maintains` becomes
  # the `box` method `_spk_maintains`. A failed check calls
  # `_SpkContract.fail`, which `ContractSupport` declares. Raises a
  # `ParseError` at a clause the rules forbid.
  class Contracts
    SUPPORT     = "_SpkContract"
    VIEW        = "spk_view"
    RESULT      = "spk_result"
    RESULT_VIEW = "spk_result_view"
    MAINTAINS   = "_spk_maintains"
    AFTER       = "spk_after"
    WITH_STATE  = %w[class actor struct]

    # Rewrites the types of `program`, read from the file named `file`.
    # Keeps every clause when `all` is set, otherwise only `expects`.
    # Returns whether any check was generated.
    def self.apply(program : Program, file : String, all : Bool = true) : Bool
      program.items.select(TypeDecl).map { |decl| new(File.basename(file), decl, all).apply }.includes?(true)
    end

    # The declarations `_SpkContract.fail` needs, added to one program of a package.
    def self.support(program : Program) : Nil
      program.items << ContractSupport.new(1, 1)
    end

    @args = Hash(String, String).new
    @olds = [] of {String, Old, Expr}
    @result_used = false
    @view_used = false

    def initialize(@file : String, @decl : TypeDecl, @all : Bool)
    end

    def apply : Bool
      maintains = @decl.maintains
      first = maintains.first?
      if first && !WITH_STATE.includes?(@decl.kind)
        raise ParseError.new("`maintains` is not supported in a #{@decl.kind} yet", first.line, first.col)
      end
      maintains = [] of Clause unless @all
      used = !maintains.empty?
      methods = [] of Method
      @decl.methods.each do |method|
        validate(method)
        guarantees = @all ? method.guarantees : [] of Clause
        checked = !maintains.empty? && maintained?(method)
        if method.expects.empty? && guarantees.empty? && !checked
          methods << method
          next
        end
        used = true
        if method.self_recv
          methods << constructor(method, guarantees, checked)
        else
          methods.concat(wrapped(method, guarantees, checked))
        end
      end
      methods << maintains_method(maintains) unless maintains.empty?
      @decl.methods = methods
      used
    end

    private def validate(m : Method) : Nil
      first = m.expects.first? || m.guarantees.first?
      return unless first
      unsupported(first, "a yielding method") if yields?(m)
      unsupported(first, "a `tag` method") if m.cap == "tag"
      if (g = m.guarantees.first?) && m.kind == "be"
        raise ParseError.new("a message handler cannot have `guarantees`: no caller sees its end", g.line, g.col)
      end
    end

    private def unsupported(at : Clause, what : String) : NoReturn
      raise ParseError.new("clauses on #{what} are not supported yet", at.line, at.col)
    end

    private def reset : Nil
      @args = Hash(String, String).new
      @olds = [] of {String, Old, Expr}
      @result_used = false
      @view_used = false
    end

    # Whether `maintains` is checked after `m`: a constructor, a handler,
    # or a public `ref` method that does not yield.
    private def maintained?(m : Method) : Bool
      return false if m.name.starts_with?('_') || m.kind == "abstract" || yields?(m)
      m.self_recv || m.kind == "be" || cap(m) == "ref"
    end

    private def cap(m : Method) : String?
      m.cap || (Rules.mutating_name?(m.name) ? "ref" : nil)
    end

    private def label(m : Method) : String
      "#{@decl.name}.#{m.name}"
    end

    private def returns_value?(m : Method) : Bool
      ret = m.ret
      !m.self_recv && m.kind != "be" && !ret.nil? && PonyType.to_pony(ret) != "None"
    end

    # The wrapper, then the body under its new name.
    private def wrapped(m : Method, guarantees : Array(Clause), checked : Bool) : Array(Method)
      partial = m.name.ends_with?('!')
      body_name = "_spk_#{Rules.pony_method_name(m.name, false)}#{partial ? "!" : ""}"
      body_cap = m.kind == "be" ? "ref" : cap(m)
      params = m.params.map { |param| Param.new(param.line, param.col, param.name, param.type, nil) }
      body = Method.new(m.line, m.col, "def", body_cap, false, body_name, params, m.ret, m.body, m.name_line, m.name_col)

      value = returns_value?(m)
      reset
      expects = conditions(m, m.expects)
      promises = conditions(m, guarantees)
      if @result_used && !value
        raise ParseError.new("`result` in a method that returns nothing", guarantees.first.line, guarantees.first.col)
      end

      stmts = views(m, !(m.expects.empty? && guarantees.empty?))
      stmts.concat(expects)
      stmts.concat(old_values)
      call = Call.new(m.line, m.col, nil, body_name, m.params.map { |param| argument(param) }, [] of NamedArg, nil, true, m.line, m.col)
      ret = m.ret
      if value && ret
        stmts << Assign.new(m.line, m.col, ident(m, RESULT), call, nil)
        stmts << Assign.new(m.line, m.col, ident(m, RESULT_VIEW), ident(m, RESULT), box_of(ret)) if @result_used
      else
        stmts << call
      end
      stmts.concat(promises)
      stmts << maintains_call(m) if checked
      stmts << Consume.new(m.line, m.col, ident(m, RESULT)) if value
      wrapper = Method.new(m.line, m.col, m.kind, m.cap, false, m.name, m.params, m.ret, stmts, m.name_line, m.name_col)
      [wrapper, body]
    end

    # Checks before and after the body, which a constructor cannot delegate.
    private def constructor(m : Method, guarantees : Array(Clause), checked : Bool) : Method
      body = m.body || [] of Expr
      if (checked || !guarantees.empty?) && (ret = find(body, &.is_a?(Return)))
        raise ParseError.new("`return` in a constructor with contracts is not supported yet", ret.line, ret.col)
      end
      reset
      expects = conditions(m, m.expects)
      if @view_used && (first = m.expects.first?)
        raise ParseError.new("a constructor's `expects` can only read its arguments", first.line, first.col)
      end
      promises = conditions(m, guarantees)
      if (word = @olds.first? ? "old" : (@result_used ? "result" : nil)) && (g = guarantees.first?)
        raise ParseError.new("`#{word}` cannot be used in a constructor's `guarantees`", g.line, g.col)
      end
      stmts = views(m, false)
      stmts.concat(expects)
      stmts.concat(body)
      stmts << Assign.new(m.line, m.col, ident(m, VIEW), SelfRef.new(m.line, m.col), view_type(m)) unless guarantees.empty?
      stmts.concat(promises)
      stmts << maintains_call(m) if checked
      Method.new(m.line, m.col, m.kind, m.cap, true, m.name, m.params, m.ret, stmts, m.name_line, m.name_col)
    end

    private def maintains_method(clauses : Array(Clause)) : Method
      first = clauses.first
      checks = clauses.map do |clause|
        message = StrLit.new(clause.line, clause.col, ["#{place(clause)}: contract failed after ", ident(clause, AFTER), ": maintains #{escape(clause.text)}"] of String | Expr)
        check(clause, clause.cond, message).as(Expr)
      end
      param = Param.new(first.line, first.col, AFTER, NamedType.new(first.line, first.col, "String"), nil)
      Method.new(first.line, first.col, "def", "box", false, MAINTAINS, [param], nil, checks, first.line, first.col)
    end

    private def maintains_call(m : Method) : Expr
      Call.new(m.line, m.col, nil, MAINTAINS, [StrLit.new(m.line, m.col, [label(m)] of String | Expr)] of Expr, [] of NamedArg, nil, true, m.line, m.col)
    end

    # `spk_view` and the argument aliases the conditions use.
    private def views(m : Method, view : Bool) : Array(Expr)
      stmts = [] of Expr
      stmts << Assign.new(m.line, m.col, ident(m, VIEW), SelfRef.new(m.line, m.col), view_type(m)) if view
      m.params.each do |param|
        name = @args[param.name]?
        type = param.type
        stmts << Assign.new(param.line, param.col, ident(param, name), ident(param, param.name), box_of(type)) if name && type
      end
      stmts
    end

    private def old_values : Array(Expr)
      @olds.flat_map do |name, old, value|
        keep = Call.new(old.line, old.col, TypeRef.new(old.line, old.col, NamedType.new(old.line, old.col, SUPPORT)), "keep", [ident(old, name)] of Expr, [] of NamedArg, nil, true, old.line, old.col)
        [Assign.new(old.line, old.col, ident(old, name), value, nil), keep] of Expr
      end
    end

    private def view_type(m : Method) : TypeNode
      args = @decl.tparams.map { |tparam| NamedType.new(m.line, m.col, tparam.name).as(TypeNode) }
      NamedType.new(m.line, m.col, @decl.name, args, "box")
    end

    private def box_of(t : TypeNode) : TypeNode
      ArrowType.new(t.line, t.col, CapType.new(t.line, t.col, "box"), t)
    end

    private def argument(param : Param) : Expr
      arg = ident(param, param.name)
      type = param.type
      type.is_a?(NamedType) && (type.cap == "iso" || type.cap == "trn") ? Consume.new(param.line, param.col, arg) : arg
    end

    # One check per condition, each seeing `self` and the arguments read-only.
    private def conditions(m : Method, clauses : Array(Clause)) : Array(Expr)
      params = m.params.map(&.name).to_set
      clauses.map do |clause|
        message = StrLit.new(clause.line, clause.col, ["#{place(clause)}: contract failed in #{label(m)}: #{clause.kind} #{escape(clause.text)}"] of String | Expr)
        check(clause, view(clause.cond.clone, params, Set(String).new), message).as(Expr)
      end
    end

    private def check(clause : Clause, cond : Expr, message : StrLit) : Expr
      fail = Call.new(clause.line, clause.col, TypeRef.new(clause.line, clause.col, NamedType.new(clause.line, clause.col, SUPPORT)), "fail", [message] of Expr, [] of NamedArg, nil, true, clause.line, clause.col)
      If.new(clause.line, clause.col, cond, [fail] of Expr, nil, true)
    end

    private def place(clause : Clause) : String
      "#{@file}:#{clause.line}:#{clause.col}"
    end

    private def escape(text : String) : String
      text.gsub('\\', "\\\\").gsub('"', "\\\"")
    end

    private def ident(at : Node, name : String) : Ident
      Ident.new(at.line, at.col, name)
    end

    # `e` with `self`, fields and calls on `self` read through `spk_view`,
    # arguments through their aliases, and `result` and `old(...)` replaced
    # by the locals that hold them. `locals` are block parameters in scope.
    private def view(e : Expr, params : Set(String), locals : Set(String)) : Expr
      case e
      when SelfRef then viewed(e)
      when IVarRef then FieldRead.new(e.line, e.col, viewed(e), e.name)
      when ResultRef
        @result_used = true
        ident(e, RESULT_VIEW)
      when Old
        name = "spk_old_#{@olds.size + 1}"
        @olds << {name, e, view(e.expr, params, locals)}
        ident(e, name)
      when Ident
        return e if locals.includes?(e.name)
        if params.includes?(e.name)
          alias_name = @args[e.name] ||= "spk_arg_#{e.name}"
          return ident(e, alias_name)
        end
        Call.new(e.line, e.col, viewed(e), e.name, [] of Expr, [] of NamedArg, nil, true, e.line, e.col)
      when Lambda
        inner = locals + e.params.map(&.name).to_set
        e.body = e.body.map { |stmt| view(stmt, params, inner).as(Expr) }
        e
      else
        e.recv = viewed(e) if e.is_a?(Call) && e.recv.nil? && !locals.includes?(e.name) && !params.includes?(e.name)
        Walk.map_children(e) { |child| view(child, params, locals) }
        e
      end
    end

    private def viewed(at : Node) : Ident
      @view_used = true
      ident(at, VIEW)
    end

    private def yields?(m : Method) : Bool
      body = m.body
      !body.nil? && !find(body) { |e| e.is_a?(Yield) }.nil?
    end

    private def find(body : Array(Expr), &block : Expr -> Bool) : Expr?
      body.each do |stmt|
        found = Walk.find(stmt, &block)
        return found if found
      end
      nil
    end
  end

  # Visits the expressions directly inside an expression.
  module Walk
    # Replaces each expression directly inside `e` with the block's result.
    def self.map_children(e : Expr, &f : Expr -> Expr) : Nil
      case e
      when StrLit
        e.parts = e.parts.map { |part| part.is_a?(Expr) ? f.call(part).as(String | Expr) : part.as(String | Expr) }
      when Paren, Consume, AsCast, Old then e.expr = f.call(e.expr)
      when Call
        e.recv = e.recv.try { |recv| f.call(recv) }
        e.args = e.args.map { |arg| f.call(arg) }
        e.named.each { |arg| arg.value = f.call(arg.value) }
        e.block.try { |block| block.body = block.body.map { |stmt| f.call(stmt) } }
      when FieldRead then e.recv = f.call(e.recv)
      when Index
        e.recv = f.call(e.recv)
        e.args = e.args.map { |arg| f.call(arg) }
      when Assign, OpAssign
        e.target = f.call(e.target)
        e.value = f.call(e.value)
      when Binary
        e.left = f.call(e.left)
        e.right = f.call(e.right)
      when Unary then e.operand = f.call(e.operand)
      when Ternary
        e.cond = f.call(e.cond)
        e.then_ = f.call(e.then_)
        e.else_ = f.call(e.else_)
      when RangeLit
        e.from = f.call(e.from)
        e.to = f.call(e.to)
      else map_statements(e, f)
      end
    end

    # The children of the expressions that hold statements or lists.
    private def self.map_statements(e : Expr, f : Expr -> Expr) : Nil
      block = ->(list : Array(Expr)) { list.map { |stmt| f.call(stmt) } }
      case e
      when Lambda, While, Sequence, RunOnce, Recover
        e.cond = f.call(e.cond) if e.is_a?(While)
        e.body = block.call(e.body)
      when If
        e.cond = f.call(e.cond)
        e.then_ = block.call(e.then_)
        e.else_ = e.else_.try { |list| block.call(list) }
      when Case
        e.subject = f.call(e.subject)
        e.whens.each do |branch|
          branch.patterns = block.call(branch.patterns)
          branch.body = block.call(branch.body)
        end
        e.else_ = e.else_.try { |list| block.call(list) }
      when Begin
        e.body = block.call(e.body)
        e.rescue_body = e.rescue_body.try { |list| block.call(list) }
        e.ensure_body = e.ensure_body.try { |list| block.call(list) }
      when Return                 then e.value = e.value.try { |value| f.call(value) }
      when Yield                  then e.args = block.call(e.args)
      when ArrayLit               then e.elems = block.call(e.elems)
      when TupleLit, TuplePattern then e.items = block.call(e.items)
      end
    end

    # The first expression in `e`, itself included, for which the block is true.
    def self.find(e : Expr, &block : Expr -> Bool) : Expr?
      return e if block.call(e)
      found = nil
      map_children(e) do |child|
        found ||= find(child, &block)
        child
      end
      found
    end
  end
end
