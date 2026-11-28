require "./ast"
require "./parser"
require "./pony_type"

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

    # A call with a block to a method named like a yielding method, inside
    # type `owner` in `file`: the statement `body[index]`, or, when `setter`
    # is given, an expression that `setter` replaces. `chain` lists the
    # yielding methods it was copied out of, to catch one that reaches itself.
    record Site, file : String, call : Call, body : Array(Expr)?, index : Int32, owner : String, chain : Array(Method), setter : Proc(Expr, Nil)? = nil do
      def value? : Bool
        !setter.nil?
      end
    end

    getter origins = {} of {String, Int32, Int32} => Origin

    # Calls, by name position, decided not to reach a yielding method.
    getter plain = Set({String, Int32, Int32}).new

    # The probe that stands for a call, by its name position, for one round:
    # see `decide`.
    getter probes = {} of {String, Int32, Int32} => Expr

    # A method a call can be replaced by: a yielding method, or an inline-only
    # method of a module or a reopened Pony type. `owner` is the type the
    # receiver must have; `params` reads the type variables of the method's
    # declaration in terms of the owner's type parameters.
    record Entry, method : Method, file : String, owner : TypeDecl, params : Hash(String, TypeNode)

    @yielders = {} of {String, String} => Entry
    @inline_names = Set(String).new
    @probed = {} of {String, Int32, Int32} => Hash(String, TypeNode)
    @probe_names = {} of String => {String, Int32, Int32}
    @probe_outputs = {} of {String, Int32, Int32} => String
    @probe_receivers = {} of {String, Int32, Int32} => String
    @types = {} of String => TypeDecl
    @chains = {} of Call => Array(Method)
    @fresh = 0
    @column = SYNTHETIC_COLUMN

    def initialize(files : Array(String), programs : Array(Program))
      modules = {} of String => {TypeDecl, String}
      programs.each_with_index do |program, i|
        program.items.each { |item| modules[item.name] = {item, files[i]} if item.is_a?(TypeDecl) && item.kind == "module" }
      end
      programs.each_with_index do |program, i|
        program.items.each do |item|
          next unless item.is_a?(TypeDecl) && item.kind != "module"
          @types[item.name] = item unless item.reopens
          item.methods.each do |method|
            next unless item.reopens || ((body = method.body) && yields?(body))
            add(item, method, files[i], identity(item))
          end
          next unless item.reopens
          item.includes.each do |included|
            next unless included.is_a?(NamedType) && (found = modules[included.name]?)
            mod, file = found
            params = mod.tparams.each_with_index.to_h { |tparam, k| {tparam.name, included.args[k]? || NamedType.new(tparam.line, tparam.col, tparam.name).as(TypeNode)} }
            mod.methods.each { |method| add(item, method, file, params) unless @yielders[{item.name, method.name}]? }
          end
        end
      end
      @files = files
      @programs = programs
    end

    private def add(owner : TypeDecl, method : Method, file : String, params : Hash(String, TypeNode)) : Nil
      @yielders[{owner.name, method.name}] = Entry.new(method, file, owner, params)
      @inline_names << method.name if owner.reopens
    end

    private def identity(decl : TypeDecl) : Hash(String, TypeNode)
      decl.tparams.to_h { |tparam| {tparam.name, NamedType.new(tparam.line, tparam.col, tparam.name).as(TypeNode)} }
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

    # Replaces the call at `site` with a copy of the method that
    # `receiver_type` (as ponyc prints it; nil for a call on `self`, or
    # when the type is not known yet) has, or marks the call plain when it
    # has none. A method with `forall` types first gets a probe, which the
    # next round lowers in the call's place; the call is decided once the
    # probe's type is read (`probed`). Returns whether the call was decided
    # or probed, so that a call whose receiver's type is unknown waits.
    def decide(site : Site, receiver_type : String?) : Bool
      call = site.call
      key = {site.file, call.name_line, call.name_col}
      receiver_type = nil if receiver_type && unknown?(receiver_type)
      receiver_type ||= @probe_receivers[key]?
      return false if call.recv && receiver_type.nil?
      receiver = receiver_type.try { |printed| PonyType.parse(printed) }
      owner = receiver_type ? type_name(receiver_type) : site.owner
      entry = owner && @yielders[{owner, call.name}]?
      unless entry
        @plain << {site.file, call.name_line, call.name_col}
        return true
      end
      m = entry.method
      if site.chain.includes?(m)
        raise ParseError.new("`#{call.name}` reaches itself through a block; a yielding method cannot", call.name_line, call.name_col)
      end
      types = concrete(entry, receiver)
      unless m.forall.empty?
        if found = @probed[key]?
          types.merge!(found)
        else
          return false if @probes.has_key?(key)
          receiver_type.try { |printed| @probe_receivers[key] = printed }
          return probe(site, entry, types, key)
        end
      end
      @probes.delete(key)
      copier = Copier.new(self, site, m, entry.file, next_tag, types)
      if setter = site.setter
        setter.call(copier.value)
      else
        body = site.body || raise "a statement site has a body"
        body[site.index, 1] = copier.statements
      end
      true
    end

    # Whether ponyc printed `type` for an expression it could not type, as
    # in a round where an earlier call was still stubbed.
    private def unknown?(type : String) : Bool
      type.includes?("<type error>") || type.includes?("to_infer")
    end

    # Marks the undecided `sites` plain, when no round can decide them, so
    # that ponyc reports what is wrong with them.
    def give_up(sites : Array(Site)) : Nil
      sites.each { |site| @plain << {site.file, site.call.name_line, site.call.name_col} }
      @probes.clear
    end

    # Records the type ponyc gave each probe local, by its name.
    def probed(types : Hash(String, String)) : Nil
      types.each do |name, printed|
        key = @probe_names[name]? || next
        found = PonyType.parse(printed) || next
        @probed[key] = {@probe_outputs[key] => found}
      end
    end

    # The method's type variables as the receiver's type arguments give them.
    private def concrete(entry : Entry, receiver : TypeNode?) : Hash(String, TypeNode)
      owner_args = {} of String => TypeNode
      if receiver.is_a?(NamedType)
        entry.owner.tparams.each_with_index { |tparam, k| receiver.args[k]?.try { |arg| owner_args[tparam.name] = arg } }
      end
      return owner_args if entry.params.empty?
      entry.params.transform_values { |type| Types.substitute(type, owner_args) }.merge(owner_args)
    end

    # The probe for `site`: a loop over an empty array of the block's
    # parameter types, whose body binds the block's value to `spk_probe_<n>`.
    private def probe(site : Site, entry : Entry, types : Hash(String, TypeNode), key : {String, Int32, Int32}) : Bool
      call = site.call
      m = entry.method
      block = call.block
      signature = m.block
      unless block && signature && (output = signature.output).is_a?(NamedType) && m.forall.includes?(output.name)
        raise ParseError.new("`#{call.name}` needs a block whose value's type is one of its `forall` names", call.name_line, call.name_col)
      end
      at = {call.line, call.col}
      inputs = signature.inputs.map { |type| Types.substitute(type, types) }
      element = inputs.size == 1 ? inputs[0] : TupleType.new(*at, inputs).as(TypeNode)
      name = "spk_probe_#{@probe_names.size + 1}"
      @probe_names[name] = key
      @probe_outputs[key] = output.name
      binds = [] of Expr
      params = block.params
      if params.size == 1
        loop_param = params[0].name
      else
        loop_param = "spk_p"
        params.each_with_index { |param, k| binds << Assign.new(*at, Ident.new(*at, param.name), FieldRead.new(*at, Ident.new(*at, loop_param), "_#{k + 1}"), nil) }
      end
      binds << Assign.new(*at, Ident.new(*at, name), Sequence.new(*at, block.body.clone), nil)
      binds << NilLit.new(*at)
      empty = Call.new(*at, TypeRef.new(*at, NamedType.new(*at, "Array", [element] of TypeNode)), "new", [] of Expr, [] of NamedArg, nil, true, *at)
      loop_block = Lambda.new(*at, [Param.new(*at, loop_param, nil, nil)], binds)
      @probes[key] = Call.new(*at, empty, "each", [] of Expr, [] of NamedArg, loop_block, false, *at)
      true
    end

    # Drops the yielding methods, once no call to one is left to decide.
    def finish : Nil
      @types.each_value { |decl| decl.methods.reject! { |method| @yielders[{decl.name, method.name}]? } }
      @probes.clear
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

    # `def spk_yf_n : this->T = @n`, with the capability of `m`, added once;
    # public, so that a copy in another package can call it.
    protected def accessor(owner : String, field : String, m : Method, at : Node) : String
      name = "spk_yf_#{field}"
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
        if site?(e, names, file)
          found << Site.new(file, e.as(Call), body, i, owner, @chains[e]? || [] of Method)
        end
        slots(e) do |child, setter|
          if site?(child, names, file)
            found << Site.new(file, child.as(Call), nil, 0, owner, @chains[child]? || [] of Method, setter)
          end
          value_sites(child, names, file, owner, found)
        end
        each_body(e) { |inner| collect(inner, names, file, owner, found) }
      end
    end

    private def value_sites(e : Expr, names : Set(String), file : String, owner : String, found : Array(Site)) : Nil
      slots(e) do |child, setter|
        if site?(child, names, file)
          found << Site.new(file, child.as(Call), nil, 0, owner, @chains[child]? || [] of Method, setter)
        end
        value_sites(child, names, file, owner, found)
      end
    end

    # A call with a block to a yielding method's name, or any call to an
    # inline-only method's name.
    private def site?(e : Expr, names : Set(String), file : String) : Bool
      e.is_a?(Call) && (!e.block.nil? || @inline_names.includes?(e.name)) && names.includes?(e.name) && !@plain.includes?({file, e.name_line, e.name_col})
    end

    # Each expression `e` holds in a value position, with a setter that
    # replaces it there. Statement lists are left to `each_body`.
    private def slots(e : Expr, & : Expr, Proc(Expr, Nil) -> Nil) : Nil
      if one = single_slot(e)
        yield one[0], one[1]
        return
      end
      case e
      when Call
        e.recv.try { |recv| yield recv, ->(x : Expr) { e.recv = x } }
        e.args.each_index { |i| yield e.args[i], ->(x : Expr) { e.args[i] = x } }
        e.named.each { |arg| yield arg.value, ->(x : Expr) { arg.value = x } }
      when Index
        yield e.recv, ->(x : Expr) { e.recv = x }
        e.args.each_index { |i| yield e.args[i], ->(x : Expr) { e.args[i] = x } }
      when Binary
        yield e.left, ->(x : Expr) { e.left = x }
        yield e.right, ->(x : Expr) { e.right = x }
      when Ternary
        yield e.cond, ->(x : Expr) { e.cond = x }
        yield e.then_, ->(x : Expr) { e.then_ = x }
        yield e.else_, ->(x : Expr) { e.else_ = x }
      when RangeLit
        yield e.from, ->(x : Expr) { e.from = x }
        yield e.to, ->(x : Expr) { e.to = x }
      when ArrayLit then e.elems.each_index { |i| yield e.elems[i], ->(x : Expr) { e.elems[i] = x } }
      when TupleLit then e.items.each_index { |i| yield e.items[i], ->(x : Expr) { e.items[i] = x } }
      when StrLit
        e.parts.each_index do |i|
          part = e.parts[i]
          yield part, ->(x : Expr) { e.parts[i] = x } if part.is_a?(Expr)
        end
      end
    end

    # The one value slot of a node that has one, with its setter.
    private def single_slot(e : Expr) : {Expr, Proc(Expr, Nil)}?
      case e
      when Paren     then {e.expr, ->(x : Expr) { e.expr = x }}
      when FieldRead then {e.recv, ->(x : Expr) { e.recv = x }}
      when Assign    then {e.value, ->(x : Expr) { e.value = x }}
      when OpAssign  then {e.value, ->(x : Expr) { e.value = x }}
      when Unary     then {e.operand, ->(x : Expr) { e.operand = x }}
      when If        then {e.cond, ->(x : Expr) { e.cond = x }}
      when While     then {e.cond, ->(x : Expr) { e.cond = x }}
      when Case      then {e.subject, ->(x : Expr) { e.subject = x }}
      when Consume   then {e.expr, ->(x : Expr) { e.expr = x }}
      when AsCast    then {e.expr, ->(x : Expr) { e.expr = x }}
      when Return    then e.value.try { |value| {value, ->(x : Expr) { e.value = x }} }
      end
    end

    private def each_body(e : Expr, & : Array(Expr) -> Nil) : Nil
      case e
      when If                then yield e.then_; e.else_.try { |blk| yield blk }
      when While             then yield e.body
      when Case              then e.whens.each { |branch| yield branch.body }; e.else_.try { |blk| yield blk }
      when Begin             then yield e.body; e.rescue_body.try { |blk| yield blk }; e.ensure_body.try { |blk| yield blk }
      when Recover           then yield e.body
      when Call              then e.block.try { |blk| yield blk.body }
      when Lambda            then yield e.body
      when Sequence, RunOnce then yield e.body
      end
    end

    private def yields?(body : Array(Expr)) : Bool
      body.any? { |e| yields?(e) }
    end

    private def yields?(e : Expr) : Bool
      return true if e.is_a?(Yield)
      found = false
      slots(e) { |child, _| found ||= yields?(child) }
      each_body(e) { |inner| found ||= yields?(inner) }
      found
    end

    # A copy of one yielding method's body for one call.
    private class Copier
      @locals : Set(String)
      @receiver : String
      @loops = 0
      # A local set when the block `break`s or the method `return`s, so the
      # rest of the copy is skipped; nil when neither happens.
      @flag : String? = nil
      @next = false
      @break = false

      # `types` gives the type each type variable of the method stands for.
      def initialize(@inliner : Inliner, @site : Site, @method : Method, @file : String, @tag : String, @types : Hash(String, TypeNode) = {} of String => TypeNode)
        @receiver = "#{@tag}self"
        @locals = @method.params.map(&.name).to_set
        @method.body.try { |body| declared(body) }
      end

      # The copy, for a call whose value is used: a `Sequence` whose last
      # statement gives the method's value.
      def value : Expr
        call = @site.call
        Sequence.new(call.line, call.col, statements)
      end

      # The receiver and arguments bound to fresh locals, then the copied body.
      def statements : Array(Expr)
        call = @site.call
        block = call.block
        check_block(block) if block
        returns = returns?(@method.body || [] of Expr)
        if @site.value? && (@break || returns)
          what = @break ? "`break` in its block" : "`return` in the method"
          raise ParseError.new("a call whose value is used, with #{what}, is not supported yet", call.name_line, call.name_col)
        end
        at = {call.line, call.col}
        flag = (@break || returns) ? "#{@tag}done" : nil
        @flag = flag
        recv = call.recv || SelfRef.new(*at)
        out = [Assign.new(*at, Ident.new(*at, @receiver), recv, nil)] of Expr
        @method.params.each_with_index do |param, i|
          arg = call.args[i]? || param.default || raise ParseError.new("`#{call.name}` needs an argument for `#{param.name}`", call.name_line, call.name_col)
          out << Assign.new(*at, Ident.new(*at, @tag + param.name), arg, ty(param.type))
        end
        if call.args.size > @method.params.size
          raise ParseError.new("`#{call.name}` takes #{@method.params.size} arguments, not #{call.args.size}", call.name_line, call.name_col)
        end
        out << Assign.new(*at, Ident.new(*at, flag), BoolLit.new(*at, false), nil) if flag
        out.concat(stmts(@method.body || [] of Expr))
      end

      # Notes whether the block has `next` or `break` outside a loop of its
      # own. `return` in the block needs nothing: the block runs in the caller.
      private def check_block(block : Lambda) : Nil
        loose_jump(block.body, 0)
        if @site.value? && @next
          raise ParseError.new("`next` in a block whose call's value is used is not supported yet", block.line, block.col)
        end
      end

      private def loose_jump(body : Array(Expr), loops : Int32) : Nil
        body.each do |e|
          case e
          when Next  then @next = true if loops == 0
          when Break then @break = true if loops == 0
          when While then loose_jump(e.body, loops + 1)
          when Call
            e.block.try { |blk| loose_jump(blk.body, Rules::LOOP_METHODS.includes?(e.name) ? loops + 1 : loops) }
          when If then loose_jump(e.then_, loops); e.else_.try { |blk| loose_jump(blk, loops) }
          end
        end
      end

      # Whether `body` has `return`, outside a lambda.
      private def returns?(body : Array(Expr)) : Bool
        body.any? do |e|
          case e
          when Return then true
          when While  then returns?(e.body)
          when If     then returns?(e.then_) || (e.else_.try { |blk| returns?(blk) } || false)
          when Case   then e.whens.any? { |branch| returns?(branch.body) } || (e.else_.try { |blk| returns?(blk) } || false)
          when Call   then Rules::LOOP_METHODS.includes?(e.name) && (e.block.try { |blk| returns?(blk.body) } || false)
          else             false
          end
        end
      end

      # Whether `e` can end the copy early: it yields to a block that
      # `break`s, or it is or holds a `return`.
      private def ends_early?(e : Expr) : Bool
        return false unless @flag
        e.is_a?(Return) || returns?([e]) || (@break && holds_yield?(e))
      end

      private def holds_yield?(e : Expr) : Bool
        return true if e.is_a?(Yield)
        case e
        when While then e.body.any? { |x| holds_yield?(x) }
        when If    then e.then_.any? { |x| holds_yield?(x) } || (e.else_.try { |blk| blk.any? { |x| holds_yield?(x) } } || false)
        when Case  then e.whens.any? { |branch| branch.body.any? { |x| holds_yield?(x) } } || (e.else_.try { |blk| blk.any? { |x| holds_yield?(x) } } || false)
        when Call  then e.block.try { |blk| blk.body.any? { |x| holds_yield?(x) } } || false
        else            false
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

      # Copies a statement list. After a statement that can end the copy
      # early, the rest is skipped once the flag is set: by `break` inside a
      # loop of the copy, or by wrapping the rest in `unless` outside one.
      private def stmts(body : Array(Expr)) : Array(Expr)
        out = [] of Expr
        body.each_with_index do |e, i|
          out.concat(e.is_a?(Yield) ? yield_block(e) : (e.is_a?(Return) ? method_return(e) : [copy(e)]))
          flag = @flag
          next unless flag && ends_early?(e)
          at = {@site.call.line, @site.call.col}
          if @loops > 0
            out << If.new(*at, Ident.new(*at, flag), [Break.new(*at)] of Expr, nil)
          else
            rest = stmts(body[(i + 1)..])
            out << If.new(*at, Ident.new(*at, flag), rest, nil, negate: true) unless rest.empty?
            break
          end
        end
        out
      end

      # `return` in the method ends the copy: the flag is set, and `stmts`
      # skips the rest.
      private def method_return(e : Return) : Array(Expr)
        raise ParseError.new("`return` with a value in a yielding method is not supported yet", e.line, e.col) if e.value
        flag = @flag || raise "a returning method has a flag"
        at = {@site.call.line, @site.call.col}
        [Assign.new(*at, Ident.new(*at, flag), BoolLit.new(*at, true), nil)] of Expr
      end

      # `yield a, b`: the block's parameters bound to `a` and `b`, then a
      # fresh copy of its body.
      private def yield_block(e : Yield) : Array(Expr)
        block = @site.call.block || raise ParseError.new("`#{@site.call.name}` needs a block", @site.call.name_line, @site.call.name_col)
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
        return bind + body unless @next || @break
        # `next` ends this run of the block and `break` the whole call, so the
        # run is a `RunOnce`, whose `continue` leaves it.
        bind + [RunOnce.new(call.line, call.col, loose_breaks(body, 0)).as(Expr)]
      end

      # `break` outside the block's own loops sets the flag and ends the run.
      private def loose_breaks(body : Array(Expr), loops : Int32) : Array(Expr)
        flag = @flag
        body.flat_map do |e|
          case e
          when Break
            next [e.as(Expr)] if loops > 0 || flag.nil?
            [Assign.new(e.line, e.col, Ident.new(e.line, e.col, flag), BoolLit.new(e.line, e.col, true), nil), Next.new(e.line, e.col)] of Expr
          when While
            e.body = loose_breaks(e.body, loops + 1)
            [e.as(Expr)]
          when If
            e.then_ = loose_breaks(e.then_, loops)
            e.else_ = e.else_.try { |blk| loose_breaks(blk, loops) }
            [e.as(Expr)]
          when Call
            e.block.try { |blk| blk.body = loose_breaks(blk.body, Rules::LOOP_METHODS.includes?(e.name) ? loops + 1 : loops) }
            [e.as(Expr)]
          else
            [e]
          end
        end
      end

      # `yield a` used as a value: the block's last statement gives it.
      private def yield_value(e : Yield) : Expr
        if @next || @break
          raise ParseError.new("`next` or `break` in a block whose `yield` value is used is not supported yet", e.line, e.col)
        end
        call = @site.call
        Sequence.new(call.line, call.col, yield_block(e))
      end

      private def copy_all(es : Array(Expr)) : Array(Expr)
        es.map { |x| copy(x) }
      end

      private def copy_lambda(b : Lambda) : Lambda
        pos = at(b)
        params = b.params.map { |param| Param.new(*at(param), @tag + param.name, ty(param.type), param.default.try { |value| copy(value) }) }
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
        in TypeRef   then TypeRef.new(*at(e), ty(e.type))
        in Paren     then Paren.new(*at(e), copy(e.expr))
        in Lambda    then copy_lambda(e)
        in AmpMethod then AmpMethod.new(*at(e), e.name)
        in Call      then copy_call(e)
        in FieldRead then FieldRead.new(*at(e), copy(e.recv), e.name)
        in Index     then Index.new(*at(e), copy(e.recv), copy_all(e.args), e.bang)
        in Assign
          raise ParseError.new("writing a field in a yielding method is not supported yet", e.line, e.col) if e.target.is_a?(IVarRef)
          Assign.new(*at(e), copy(e.target), copy(e.value), ty(e.type))
        in OpAssign
          raise ParseError.new("writing a field in a yielding method is not supported yet", e.line, e.col) if e.target.is_a?(IVarRef)
          OpAssign.new(*at(e), copy(e.target), e.op, copy(e.value))
        in Binary           then Binary.new(*at(e), e.op, copy(e.left), copy(e.right))
        in Unary            then Unary.new(*at(e), e.op, copy(e.operand))
        in Ternary          then Ternary.new(*at(e), copy(e.cond), copy(e.then_), copy(e.else_))
        in If               then If.new(*at(e), copy(e.cond), stmts(e.then_), e.else_.try { |blk| stmts(blk) }, e.negate, e.is_elsif, e.modifier)
        in While            then loop_body { While.new(*at(e), copy(e.cond), stmts(e.body), e.inverted) }
        in TypePattern      then TypePattern.new(*at(e), @tag + e.name, ty(e.type))
        in PredicatePattern then PredicatePattern.new(*at(e), e.name)
        in TuplePattern     then TuplePattern.new(*at(e), copy_all(e.items))
        in Case             then Case.new(*at(e), copy(e.subject), e.whens.map { |branch| When.new(*at(branch), copy_all(branch.patterns), stmts(branch.body)) }, e.else_.try { |blk| stmts(blk) }, e.exhaustive)
        in Begin            then Begin.new(*at(e), stmts(e.body), e.rescue_body.try { |blk| stmts(blk) }, e.ensure_body.try { |blk| stmts(blk) })
        in Raise            then Raise.new(*at(e))
        in Yield            then yield_value(e)
        in Return           then raise ParseError.new("`return` inside an expression in a yielding method is not supported yet", e.line, e.col)
        in Sequence         then Sequence.new(*at(e), stmts(e.body))
        in RunOnce          then RunOnce.new(*at(e), stmts(e.body))
        in Break, Next
          raise ParseError.new("`#{e.class.name.split("::").last.downcase}` outside a loop in a yielding method is not supported yet", e.line, e.col) if @loops == 0
          e.is_a?(Break) ? Break.new(*at(e)) : Next.new(*at(e))
        in Consume  then Consume.new(*at(e), copy(e.expr))
        in Recover  then Recover.new(*at(e), e.cap, stmts(e.body))
        in ArrayLit then ArrayLit.new(*at(e), copy_all(e.elems), ty(e.of_type))
        in TupleLit then TupleLit.new(*at(e), copy_all(e.items))
        in RangeLit then RangeLit.new(*at(e), copy(e.from), copy(e.to), e.exclusive)
        in AsCast   then AsCast.new(*at(e), copy(e.expr), ty(e.type))
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
        copied = Call.new(*pos, recv, e.name, copy_all(e.args), named, block, e.parens || e.recv.nil?, *name_pos, e.post)
        @inliner.chain(copied, @site.chain + [@method])
        copied
      end

      private def ty(t : TypeNode) : TypeNode
        @types.empty? ? t : Types.substitute(t, @types)
      end

      private def ty(t : Nil) : Nil
        nil
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
      @yielders.each { |key, value| return key[0] if value.method.same?(m) }
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

  # Type nodes with type variables replaced.
  module Types
    # `t` with each `NamedType` named in `map`, and with no arguments of its
    # own, replaced by its value; a capability written on the variable is
    # kept when the value has none.
    def self.substitute(t : TypeNode, map : Hash(String, TypeNode)) : TypeNode
      case t
      when NamedType
        if t.args.empty? && (value = map[t.name]?)
          return value unless value.is_a?(NamedType) && t.cap && value.cap.nil?
          return NamedType.new(value.line, value.col, value.name, value.args, t.cap, t.eph)
        end
        NamedType.new(t.line, t.col, t.name, t.args.map { |arg| substitute(arg, map) }, t.cap, t.eph)
      when UnionType then UnionType.new(t.line, t.col, t.types.map { |each| substitute(each, map) })
      when IsectType then IsectType.new(t.line, t.col, t.types.map { |each| substitute(each, map) })
      when TupleType then TupleType.new(t.line, t.col, t.types.map { |each| substitute(each, map) })
      when ArrowType then ArrowType.new(t.line, t.col, substitute(t.left, map), substitute(t.right, map))
      when ProcType  then ProcType.new(t.line, t.col, t.params.map { |each| substitute(each, map) }, t.ret.try { |ret| substitute(ret, map) }, t.cap, t.eph, t.partial)
      else                t
      end
    end
  end
end
