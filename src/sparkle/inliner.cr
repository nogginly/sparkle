require "./ast"
require "./parser"

module Sparkle
  # Inlines `yield` (spec, *yield*). A method whose body yields is never
  # compiled; each call to it with a block, in statement position, is
  # replaced by a copy of its body in which `yield a` binds the block's
  # parameters to `a` and runs the block's body. Which method a call reaches
  # is decided by its receiver's type, which the driver reads from a
  # type-checking round; `sites` lists the calls still to decide.
  #
  # Copied nodes take synthetic positions on the call's line, with columns
  # from `SYNTHETIC_COLUMN` up in program order. They are distinct, so the
  # field-or-method loop can tell them apart, and in order, as ponyc's
  # declaration-before-use check needs. `origins` maps each one back to the
  # yielding method's own position, for error messages.
  class Inliner
    SYNTHETIC_COLUMN = 100_000

    # Where a copied node came from, and the call it was copied into.
    record Origin, file : String, line : Int32, col : Int32, call_file : String, call_line : Int32, call_col : Int32

    # A call with a block to a method named like a yielding method: `body[index]`
    # in `file`, inside type `owner`. `chain` lists the yielding methods it was
    # copied out of, to catch one that reaches itself.
    record Site, file : String, call : Call, body : Array(Expr), index : Int32, owner : String, chain : Array(Method)

    getter origins = {} of {String, Int32, Int32} => Origin

    # Calls, by name position, decided not to reach a yielding method.
    getter plain = Set({String, Int32, Int32}).new

    @yielders = {} of {String, String} => {Method, String}
    @types = {} of String => TypeDecl
    @chains = {} of Call => Array(Method)
    @fresh = 0
    @column = SYNTHETIC_COLUMN

    def initialize(files : Array(String), programs : Array(Program))
      programs.each_with_index do |program, i|
        program.items.each do |item|
          next unless item.is_a?(TypeDecl)
          @types[item.name] = item
          item.methods.each { |method| @yielders[{item.name, method.name}] = {method, files[i]} if (body = method.body) && yields?(body) }
        end
      end
      @files = files
      @programs = programs
    end

    # The names of the yielding methods, which the lowerer stubs while any
    # call to one is undecided.
    def names : Set(String)
      @yielders.keys.map(&.[1]).to_set
    end

    def yielding? : Bool
      !@yielders.empty?
    end

    # The undecided calls, and any call to a yielding method's name used as
    # a value, which `decide` rejects once its type is known.
    def sites : Array(Site)
      names = self.names
      found = [] of Site
      @programs.each_with_index do |program, i|
        program.items.each do |item|
          next unless item.is_a?(TypeDecl)
          item.methods.each do |method|
            next if @yielders[{item.name, method.name}]?
            method.body.try { |body| collect(body, names, @files[i], item.name, found) }
          end
        end
      end
      found
    end

    # Replaces the call at `site` with a copy of the yielding method that
    # `receiver_type` (as ponyc prints it, nil for a call on `self`) has,
    # or marks the call plain when it has none.
    def decide(site : Site, receiver_type : String?) : Nil
      call = site.call
      owner = receiver_type ? type_name(receiver_type) : site.owner
      entry = owner && @yielders[{owner, call.name}]?
      unless entry
        @plain << {site.file, call.name_line, call.name_col}
        return
      end
      m, file = entry
      if site.chain.includes?(m)
        raise ParseError.new("`#{call.name}` reaches itself through a block; a yielding method cannot", call.name_line, call.name_col)
      end
      site.body[site.index, 1] = Copier.new(self, site, m, file, next_tag).statements
    end

    # Drops the yielding methods, once no call to one is left to decide.
    def finish : Nil
      @types.each_value { |decl| decl.methods.reject! { |method| @yielders[{decl.name, method.name}]? } }
    end

    protected def position(file : String, line : Int32, col : Int32, site : Site) : {Int32, Int32}
      @column += 1
      at = {site.call.line, @column}
      @origins[{site.file, at[0], at[1]}] = Origin.new(file, line, col, site.file, site.call.name_line, site.call.name_col)
      at
    end

    protected def chain(call : Call, methods : Array(Method)) : Nil
      @chains[call] = methods
    end

    # `def _yf_n : this->T = @n`, with the capability of `m`, added once.
    protected def accessor(owner : String, field : String, m : Method, at : Node) : String
      name = "_yf_#{field}"
      decl = @types[owner]
      return name if decl.methods.any? { |x| x.name == name }
      f = decl.fields.find { |x| x.name == field } || raise ParseError.new("`@#{field}` is not a field of #{owner}", at.line, at.col)
      type = f.type || raise ParseError.new("`@#{field}` has no type", f.line, f.col)
      ret = ArrowType.new(f.line, f.col, NamedType.new(f.line, f.col, "this"), type)
      decl.methods << Method.new(f.line, f.col, "def", m.cap, false, name, [] of Param, ret, [IVarRef.new(f.line, f.col, field)] of Expr, f.line, f.col)
      name
    end

    private def next_tag : String
      @fresh += 1
      "y#{@fresh}_"
    end

    private def type_name(printed : String) : String?
      name = printed.split("->").last.split(/[\[ ]/).first
      name.empty? ? nil : name
    end

    private def collect(body : Array(Expr), names : Set(String), file : String, owner : String, found : Array(Site)) : Nil
      body.each_with_index do |e, i|
        if e.is_a?(Call) && e.block && names.includes?(e.name) && !@plain.includes?({file, e.name_line, e.name_col})
          found << Site.new(file, e, body, i, owner, @chains[e]? || [] of Method)
        end
        each_body(e) { |inner| collect(inner, names, file, owner, found) }
      end
    end

    private def each_body(e : Expr, & : Array(Expr) -> Nil) : Nil
      case e
      when If      then yield e.then_; e.else_.try { |blk| yield blk }
      when While   then yield e.body
      when Case    then e.whens.each { |branch| yield branch.body }; e.else_.try { |blk| yield blk }
      when Begin   then yield e.body; e.rescue_body.try { |blk| yield blk }; e.ensure_body.try { |blk| yield blk }
      when Recover then yield e.body
      when Call    then e.block.try { |blk| yield blk.body }
      when Lambda  then yield e.body
      end
    end

    private def yields?(body : Array(Expr)) : Bool
      body.any? { |e| yields?(e) }
    end

    private def yields?(e : Expr) : Bool
      return true if e.is_a?(Yield)
      found = false
      each_body(e) { |inner| found ||= yields?(inner) }
      found
    end

    # A copy of one yielding method's body for one call.
    private class Copier
      @locals : Set(String)
      @receiver : String
      @loops = 0

      def initialize(@inliner : Inliner, @site : Site, @method : Method, @file : String, @tag : String)
        @receiver = "#{@tag}self"
        @locals = @method.params.map(&.name).to_set
        @method.body.try { |body| declared(body) }
      end

      # The receiver and arguments bound to fresh locals, then the copied body.
      def statements : Array(Expr)
        call = @site.call
        block = call.block || raise "a site has a block"
        check_block(block)
        at = {call.line, call.col}
        recv = call.recv || SelfRef.new(*at)
        out = [Assign.new(*at, Ident.new(*at, @receiver), recv, nil)] of Expr
        @method.params.each_with_index do |param, i|
          arg = call.args[i]? || param.default || raise ParseError.new("`#{call.name}` needs an argument for `#{param.name}`", call.name_line, call.name_col)
          out << Assign.new(*at, Ident.new(*at, @tag + param.name), arg, param.type)
        end
        if call.args.size > @method.params.size
          raise ParseError.new("`#{call.name}` takes #{@method.params.size} arguments, not #{call.args.size}", call.name_line, call.name_col)
        end
        out.concat(stmts(@method.body || [] of Expr))
      end

      private def check_block(block : Lambda) : Nil
        loose_jump(block.body, 0)
      end

      # `next`, `break` and `return` in the block, outside a loop of its own.
      private def loose_jump(body : Array(Expr), loops : Int32) : Nil
        body.each do |e|
          case e
          when Next, Break, Return
            raise ParseError.new("`#{e.class.name.split("::").last.downcase}` in a block passed to a yielding method is not supported yet", e.line, e.col) if loops == 0 || e.is_a?(Return)
          when While then loose_jump(e.body, loops + 1)
          when Call
            e.block.try { |blk| loose_jump(blk.body, Rules::LOOP_METHODS.includes?(e.name) ? loops + 1 : loops) }
          when If then loose_jump(e.then_, loops); e.else_.try { |blk| loose_jump(blk, loops) }
          end
        end
      end

      private def declared(body : Array(Expr)) : Nil
        body.each do |e|
          case e
          when Assign
            target = e.target
            @locals << target.name if target.is_a?(Ident)
          when OpAssign
            target = e.target
            @locals << target.name if target.is_a?(Ident)
          when Call
            e.block.try { |blk| blk.params.each { |param| @locals << param.name } }
          when Case
            e.whens.each { |branch| branch.patterns.each { |param| @locals << param.name if param.is_a?(TypePattern) } }
          end
          sub = [] of Array(Expr)
          case e
          when If      then sub << e.then_; e.else_.try { |blk| sub << blk }
          when While   then sub << e.body
          when Case    then e.whens.each { |branch| sub << branch.body }; e.else_.try { |blk| sub << blk }
          when Begin   then sub << e.body; e.rescue_body.try { |blk| sub << blk }; e.ensure_body.try { |blk| sub << blk }
          when Recover then sub << e.body
          when Call    then e.block.try { |blk| sub << blk.body }
          when Lambda  then sub << e.body
          end
          sub.each { |blk| declared(blk) }
        end
      end

      private def at(e : Node) : {Int32, Int32}
        @inliner.position(@file, e.line, e.col, @site)
      end

      private def stmts(body : Array(Expr)) : Array(Expr)
        body.flat_map do |e|
          e.is_a?(Yield) ? yield_block(e) : [copy(e)]
        end
      end

      # `yield a, b`: the block's parameters bound to `a` and `b`, then a
      # fresh copy of its body.
      private def yield_block(e : Yield) : Array(Expr)
        block = @site.call.block || raise "a site has a block"
        if block.params.size > e.args.size
          raise ParseError.new("the block takes #{block.params.size} parameters, but `yield` passes #{e.args.size}", block.line, block.col)
        end
        # The binding takes the call's position, which comes before the
        # block's body, however many rounds of inlining it has been through.
        call = @site.call
        bind = block.params.map_with_index do |param, i|
          Assign.new(call.line, call.col, Ident.new(call.line, call.col, param.name), copy(e.args[i]), param.type).as(Expr)
        end
        body = block.body.clone
        body.each { |stmt| @inliner.chain_calls(stmt, @site.chain) }
        bind + body
      end

      private def copy_all(es : Array(Expr)) : Array(Expr)
        es.map { |x| copy(x) }
      end

      private def copy_lambda(b : Lambda) : Lambda
        pos = at(b)
        params = b.params.map { |param| Param.new(*at(param), @tag + param.name, param.type, param.default.try { |value| copy(value) }) }
        Lambda.new(*pos, params, stmts(b.body), b.brace)
      end

      private def self_call(e : Node, name : String, args : Array(Expr), named : Array(NamedArg), block : Lambda?) : Call
        pos = at(e)
        Call.new(*pos, Ident.new(*pos, @receiver), name, args, named, block, true, *pos)
      end

      private def copy(e : Expr) : Expr
        case e
        in IntLit    then IntLit.new(*at(e), e.text, e.suffix)
        in FloatLit  then FloatLit.new(*at(e), e.text, e.suffix)
        in StrLit    then StrLit.new(*at(e), e.parts.map { |part| part.is_a?(Expr) ? copy(part).as(String | Expr) : part.as(String | Expr) })
        in CharLit   then CharLit.new(*at(e), e.text)
        in BoolLit   then BoolLit.new(*at(e), e.value)
        in NilLit    then NilLit.new(*at(e))
        in SelfRef   then Ident.new(*at(e), @receiver)
        in Ident     then @locals.includes?(e.name) ? Ident.new(*at(e), @tag + e.name) : self_call(e, e.name, [] of Expr, [] of NamedArg, nil)
        in IVarRef   then self_call(e, @inliner.accessor(site_owner, e.name, @method, e), [] of Expr, [] of NamedArg, nil)
        in TypeRef   then TypeRef.new(*at(e), e.type)
        in Paren     then Paren.new(*at(e), copy(e.expr))
        in Lambda    then copy_lambda(e)
        in AmpMethod then AmpMethod.new(*at(e), e.name)
        in Call      then copy_call(e)
        in FieldRead then FieldRead.new(*at(e), copy(e.recv), e.name)
        in Index     then Index.new(*at(e), copy(e.recv), copy_all(e.args), e.bang)
        in Assign
          raise ParseError.new("writing a field in a yielding method is not supported yet", e.line, e.col) if e.target.is_a?(IVarRef)
          Assign.new(*at(e), copy(e.target), copy(e.value), e.type)
        in OpAssign
          raise ParseError.new("writing a field in a yielding method is not supported yet", e.line, e.col) if e.target.is_a?(IVarRef)
          OpAssign.new(*at(e), copy(e.target), e.op, copy(e.value))
        in Binary           then Binary.new(*at(e), e.op, copy(e.left), copy(e.right))
        in Unary            then Unary.new(*at(e), e.op, copy(e.operand))
        in Ternary          then Ternary.new(*at(e), copy(e.cond), copy(e.then_), copy(e.else_))
        in If               then If.new(*at(e), copy(e.cond), stmts(e.then_), e.else_.try { |blk| stmts(blk) }, e.negate, e.is_elsif, e.modifier)
        in While            then loop_body { While.new(*at(e), copy(e.cond), stmts(e.body), e.inverted) }
        in TypePattern      then TypePattern.new(*at(e), @tag + e.name, e.type)
        in PredicatePattern then PredicatePattern.new(*at(e), e.name)
        in TuplePattern     then TuplePattern.new(*at(e), copy_all(e.items))
        in Case             then Case.new(*at(e), copy(e.subject), e.whens.map { |branch| When.new(*at(branch), copy_all(branch.patterns), stmts(branch.body)) }, e.else_.try { |blk| stmts(blk) }, e.exhaustive)
        in Begin            then Begin.new(*at(e), stmts(e.body), e.rescue_body.try { |blk| stmts(blk) }, e.ensure_body.try { |blk| stmts(blk) })
        in Raise            then Raise.new(*at(e))
        in Yield            then raise ParseError.new("`yield` used as a value is not supported yet", e.line, e.col)
        in Return           then raise ParseError.new("`return` in a yielding method is not supported yet", e.line, e.col)
        in Break, Next
          raise ParseError.new("`#{e.class.name.split("::").last.downcase}` outside a loop in a yielding method is not supported yet", e.line, e.col) if @loops == 0
          e.is_a?(Break) ? Break.new(*at(e)) : Next.new(*at(e))
        in Consume  then Consume.new(*at(e), copy(e.expr))
        in Recover  then Recover.new(*at(e), e.cap, stmts(e.body))
        in ArrayLit then ArrayLit.new(*at(e), copy_all(e.elems), e.of_type)
        in TupleLit then TupleLit.new(*at(e), copy_all(e.items))
        in RangeLit then RangeLit.new(*at(e), copy(e.from), copy(e.to), e.exclusive)
        in AsCast   then AsCast.new(*at(e), copy(e.expr), e.type)
        in EnumRef  then EnumRef.new(*at(e), e.enum_name, e.member)
        in Expr     then raise "the inliner does not copy #{e.class}"
        end
      end

      private def copy_call(e : Call) : Expr
        pos = at(e)
        name_pos = at(Ident.new(e.name_line, e.name_col, e.name))
        recv = e.recv.try { |value| copy(value) } || Ident.new(*pos, @receiver)
        named = e.named.map { |arg| NamedArg.new(*at(arg), arg.name, copy(arg.value)) }
        block = e.block.try do |blk|
          Rules::LOOP_METHODS.includes?(e.name) ? loop_body { copy_lambda(blk) } : copy_lambda(blk)
        end
        copied = Call.new(*pos, recv, e.name, copy_all(e.args), named, block, e.parens || e.recv.nil?, *name_pos)
        @inliner.chain(copied, @site.chain + [@method])
        copied
      end

      private def loop_body(&)
        @loops += 1
        begin
          yield
        ensure
          @loops -= 1
        end
      end

      private def site_owner : String
        call = @site.call
        @inliner.owner_of(@method) || raise ParseError.new("no type for `#{call.name}`", call.name_line, call.name_col)
      end
    end

    protected def owner_of(m : Method) : String?
      @yielders.each { |key, value| return key[0] if value[0].same?(m) }
      nil
    end

    # Records that calls in `stmt` came from a block run by `chain`.
    protected def chain_calls(stmt : Expr, chain : Array(Method)) : Nil
      if stmt.is_a?(Call)
        @chains[stmt] = chain
        stmt.block.try { |blk| blk.body.each { |inner| chain_calls(inner, chain) } }
      end
      each_body(stmt) { |inner| inner.each { |x| chain_calls(x, chain) } }
    end
  end
end
