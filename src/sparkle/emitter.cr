require "./ast"
require "./pony_type"
require "./source_map"

module Sparkle
  # Streaming writer that tracks the Pony line and column and records
  # source-map marks.
  class Writer
    getter map = SourceMap.new
    property indent = 0

    def initialize
      @io = String::Builder.new
      @line = 1
      @col = 1
      @bol = true
    end

    def write(s : String) : Nil
      return if s.empty?
      if @bol
        @io << "  " * @indent
        @col += 2 * @indent
        @bol = false
      end
      @io << s
      if last = s.rindex('\n')
        @line += s.count('\n')
        @col = s.size - last
      else
        @col += s.size
      end
    end

    def nl : Nil
      @io << '\n'
      @line += 1
      @col = 1
      @bol = true
    end

    def mark(line : Int32, col : Int32) : Nil
      @map.add(@line, @bol ? 1 + 2 * @indent : @col, line, col)
    end

    def text : String
      @io.to_s
    end
  end

  # Translates a `Program` to Pony source and a source map.
  class Emitter
    PONY_RESERVED = Set{
      "actor", "and", "as", "be", "box", "break", "class", "compile_error",
      "compile_intrinsic", "consume", "continue", "do", "else", "elseif", "embed",
      "end", "error", "for", "fun", "if", "ifdef", "iftype", "in", "interface",
      "is", "isnt", "iso", "lib", "let", "match", "new", "not", "object", "or",
      "primitive", "recover", "ref", "repeat", "return", "struct", "tag", "then",
      "this", "trait", "trn", "try", "type", "until", "use", "val", "var", "where",
      "while", "with", "xor",
    }
    OPERATOR_NAMES = {
      "+" => "add", "-" => "sub", "*" => "mul", "/" => "div", "%" => "rem",
      "==" => "eq", "!=" => "ne", "<" => "lt", "<=" => "le", ">" => "gt",
      ">=" => "ge", "<<" => "push", ">>" => "shr", "[]" => "apply",
      "[]!" => "apply", "[]=" => "update",
    }
    REF_BY_DEFAULT = Set{"[]=", "<<"}
    BINARY_WORDS   = {"&&" => "and", "||" => "or"}
    LOOP_METHODS   = Set{"each", "each_with_index", "times"}

    # Returns the Pony text and source map for `program`.
    def self.emit(program : Program) : {String, SourceMap}
      probe = new(program, false)
      probe.run
      return {probe.text, probe.map} unless probe.uses_collections?
      final = new(program, true)
      final.run
      {final.text, final.map}
    end

    getter? uses_collections = false
    @scopes = [] of Set(String)
    @ivars = Set(String).new
    @method_names = Set(String).new

    def initialize(@program : Program, @add_collections : Bool)
      @w = Writer.new
    end

    def text : String
      @w.text
    end

    def map : SourceMap
      @w.map
    end

    def run : Nil
      uses = @program.items.select(UseDecl)
      paths = uses.map(&.path)
      uses.each do |u|
        @w.mark(u.line, u.col)
        @w.write("use #{u.path.inspect}")
        @w.nl
      end
      if @add_collections && !paths.includes?("collections")
        @w.write(%(use "collections"))
        @w.nl
      end
      first = uses.empty? && !@add_collections
      @program.items.each do |item|
        case item
        when TypeDecl
          @w.nl unless first
          first = false
          emit_type_decl(item)
          @w.nl
        when AliasDecl
          @w.nl unless first
          first = false
          @w.mark(item.line, item.col)
          @w.write("type #{item.name} is #{PonyType.to_pony(item.type)}")
          @w.nl
        end
      end
    end

    # --- helpers -----------------------------------------------------------

    private def w(s : String) : Nil
      @w.write(s)
    end

    private def mark(n : Node) : Nil
      @w.mark(n.line, n.col)
    end

    private def scoped(&)
      @scopes.push(Set(String).new)
      yield
      @scopes.pop
    end

    private def declare(name : String) : Nil
      @scopes.last.add(name)
    end

    private def declared?(name : String) : Bool
      @scopes.any?(&.includes?(name))
    end

    private def pony_ident(name : String) : String
      PONY_RESERVED.includes?(name) ? "#{name}_" : name
    end

    # A local, parameter or binding name; primed when it equals a method name
    # of the enclosing type, because Pony forbids that overlap.
    private def local(name : String) : String
      n = pony_ident(name)
      @method_names.includes?(n) ? "#{n}'" : n
    end

    private def pony_method_name(name : String, constructor : Bool) : String
      return(name == "new" ? "create" : pony_ident(name)) if constructor
      if op = OPERATOR_NAMES[name]?
        return op
      end
      if name.ends_with?('?')
        "is_#{name.rchop}"
      elsif name.ends_with?('!')
        pony_ident(name.rchop)
      elsif name.ends_with?('=')
        "set_#{name.rchop}"
      else
        pony_ident(name)
      end
    end

    private def partial_name?(name : String) : Bool
      name.ends_with?('!')
    end

    private def block(stmts : Array(Expr)) : Nil
      @w.indent += 1
      if stmts.empty?
        @w.nl
        w "None"
      else
        stmts.each do |s|
          @w.nl
          emit(s)
        end
      end
      @w.indent -= 1
    end

    private def scoped_block(stmts : Array(Expr), names : Array(String) = [] of String) : Nil
      scoped do
        names.each { |n| declare(n) }
        block(stmts)
      end
    end

    # --- declarations ------------------------------------------------------

    private def emit_type_decl(d : TypeDecl) : Nil
      mark(d)
      w d.kind
      if cap = d.cap
        w " #{cap}"
      end
      w " #{d.name}"
      unless d.tparams.empty?
        w "["
        d.tparams.each_with_index do |tp, i|
          w ", " if i > 0
          w tp.name
          if c = tp.constraint
            w ": "
            w(c.is_a?(CapType) ? "Any #{PonyType.pony_cap(c.cap)}" : PonyType.to_pony(c))
          end
        end
        w "]"
      end
      unless d.includes.empty?
        names = d.includes.map { |t| PonyType.to_pony(t) }
        w(names.size == 1 ? " is #{names[0]}" : " is (#{names.join(" & ")})")
      end
      @ivars = d.fields.map(&.name).to_set
      @method_names = d.methods.map { |m| pony_method_name(m.name, m.self_recv) }.to_set
      @w.indent += 1
      d.fields.each do |f|
        @w.nl
        emit_field(f)
      end
      implicit = implicit_constructor?(d)
      if implicit
        @w.nl
        @w.nl unless d.fields.empty?
        w "new create() =>"
        @w.indent += 1
        @w.nl
        w "None"
        @w.indent -= 1
      end
      d.methods.each_with_index do |m, i|
        @w.nl
        @w.nl unless i == 0 && d.fields.empty? && !implicit
        emit_method(m)
      end
      @w.indent -= 1
    end

    # Classes without a constructor get an explicit `create`, so instances are
    # `ref` (Pony infers `iso` for the implicit one, which cannot be aliased).
    private def implicit_constructor?(d : TypeDecl) : Bool
      (d.kind == "class" || d.kind == "struct") && d.methods.none?(&.self_recv) && d.fields.all?(&.init)
    end

    private def emit_field(f : Field) : Nil
      mark(f)
      @scopes = [Set(String).new]
      w "var _#{f.name}: #{PonyType.to_pony(f.type.not_nil!)}"
      if init = f.init
        w " = "
        emit(init)
      end
    end

    private def mutating_name?(name : String) : Bool
      REF_BY_DEFAULT.includes?(name) || (name.ends_with?('=') && !%w(== != <= >=).includes?(name))
    end

    private def emit_method(m : Method) : Nil
      @scopes = [Set(String).new]
      @w.mark(m.line, m.col)
      constructor = m.self_recv
      word = m.kind == "be" ? "be" : (constructor ? "new" : "fun")
      w word
      cap = m.cap
      cap ||= "ref" if !constructor && m.kind != "be" && mutating_name?(m.name)
      w " #{cap}" if cap
      @w.mark(m.name_line, m.name_col)
      w " #{pony_method_name(m.name, constructor)}("
      m.params.each_with_index do |p, i|
        w ", " if i > 0
        @w.mark(p.line, p.col)
        w local(p.name)
        if t = p.type
          w ": #{PonyType.to_pony(t)}"
        end
        if d = p.default
          w " = "
          emit(d)
        end
      end
      w ")"
      if r = m.ret
        w ": #{PonyType.to_pony(r)}"
      end
      w " ?" if partial_name?(m.name) || m.name == "[]!"
      body = m.body
      return unless body
      w " =>"
      scoped do
        m.params.each { |p| declare(p.name) }
        block(body)
      end
    end

    # --- expressions -------------------------------------------------------

    private def atomic?(e : Expr) : Bool
      case e
      when Ident, IVarRef, SelfRef, IntLit, FloatLit, CharLit, BoolLit, NilLit, TypeRef,
           Index, FieldRead, Paren, ArrayLit, TupleLit, AsCast, AmpMethod, Lambda
        true
      when Call
        true
      when StrLit
        e.parts.size == 1 && e.parts[0].is_a?(String) || e.parts.empty?
      else
        false
      end
    end

    private def emit_operand(e : Expr) : Nil
      if atomic?(e) || e.is_a?(Unary) || e.is_a?(Consume)
        emit(e)
      else
        w "("
        emit(e)
        w ")"
      end
    end

    private def emit_receiver(e : Expr) : Nil
      if atomic?(e)
        emit(e)
      else
        w "("
        emit(e)
        w ")"
      end
    end

    private def emit_list(list : Array(Expr), sep : String = ", ") : Nil
      list.each_with_index do |e, i|
        w sep if i > 0
        emit(e)
      end
    end

    private def emit(e : Expr) : Nil
      mark(e)
      case e
      when IntLit, FloatLit then emit_number(e)
      when StrLit           then emit_string(e)
      when CharLit          then w "'#{e.text}'"
      when BoolLit          then w e.value.to_s
      when NilLit           then w "None"
      when SelfRef          then w "this"
      when Ident            then emit_ident(e)
      when IVarRef          then w "_#{e.name}"
      when TypeRef          then w PonyType.to_pony(e.type)
      when Paren
        w "("
        emit(e.expr)
        w ")"
      when Lambda    then emit_lambda(e)
      when AmpMethod then emit_amp(e)
      when Call      then emit_call(e)
      when FieldRead then emit_field_read(e)
      when Index     then emit_index(e)
      when Assign    then emit_assign(e)
      when OpAssign  then emit_op_assign(e)
      when Binary    then emit_binary(e)
      when Unary
        w(e.op == "!" ? "not " : e.op)
        emit_operand(e.operand)
      when Ternary
        w "if "
        emit(e.cond)
        w " then "
        emit(e.then_)
        w " else "
        emit(e.else_)
        w " end"
      when If    then emit_if(e)
      when While then emit_while(e)
      when Case  then emit_case(e)
      when Begin then emit_begin(e)
      when Raise then w "error"
      when Return
        w "return"
        if v = e.value
          w " "
          emit(v)
        end
      when Break    then w "break"
      when Next     then w "continue"
      when Consume  then (w "consume "; emit_operand(e.expr))
      when Recover  then emit_recover(e)
      when ArrayLit then emit_array(e)
      when TupleLit
        w "("
        emit_list(e.items)
        w ")"
      when RangeLit then emit_range(e.from, e.to, e.exclusive)
      when AsCast
        w "("
        emit_receiver(e.expr)
        w " as #{PonyType.to_pony(e.type)})"
      when TypePattern, TuplePattern then emit_pattern(e)
      else
        raise "cannot emit #{e.class}"
      end
    end

    private def emit_number(e : IntLit | FloatLit) : Nil
      if s = e.suffix
        w "#{s}(#{e.text})"
      else
        w e.text
      end
    end

    private def emit_string(e : StrLit) : Nil
      parts = e.parts
      if parts.all?(String)
        w %("#{parts.join}")
        return
      end
      w %("" + ) if parts.size == 1
      parts.each_with_index do |p, i|
        w " + " if i > 0
        case p
        in String
          w %("#{p}")
        in Expr
          if p.is_a?(StrLit) && p.parts.all?(String)
            emit(p)
          else
            emit_receiver(p)
            w ".string()"
          end
        end
      end
    end

    private def emit_ident(e : Ident) : Nil
      if declared?(e.name)
        w local(e.name)
      else
        w "#{pony_method_name(e.name, false)}()"
        w "?" if partial_name?(e.name)
      end
    end

    private def emit_field_read(e : FieldRead) : Nil
      emit_receiver(e.recv)
      @w.mark(e.line, e.col)
      w ".#{@ivars.includes?(e.name) ? "_" : ""}#{pony_ident(e.name)}"
    end

    private def emit_index(e : Index) : Nil
      emit_receiver(e.recv)
      w "("
      emit_list(e.args)
      w ")"
      w "?" if e.bang
    end

    private def emit_assign(a : Assign) : Nil
      t = a.target
      case t
      when Ident
        name = local(t.name)
        if declared?(t.name)
          w "#{name} = "
          emit(a.value)
        else
          w "var #{name}"
          if ty = a.type
            w ": #{PonyType.to_pony(ty)}"
          elsif default = default_literal_type(a.value)
            w ": #{default}"
          end
          w " = "
          emit(a.value)
          declare(t.name)
        end
      when Call
        emit_receiver(t.recv.not_nil!)
        @w.mark(t.name_line, t.name_col)
        w ".set_#{t.name}("
        emit(a.value)
        w ")"
      else
        emit_lvalue(t)
        w " = "
        emit(a.value)
      end
    end

    # Pony cannot infer the type of a bare numeric literal bound to a variable.
    private def default_literal_type(v : Expr) : String?
      case v
      when IntLit   then v.suffix ? nil : "I32"
      when FloatLit then v.suffix ? nil : "F64"
      end
    end

    private def emit_lvalue(t : Expr) : Nil
      mark(t)
      case t
      when IVarRef then w "_#{t.name}"
      when Ident   then w local(t.name)
      when Index   then emit_index(t)
      when Call
        emit_receiver(t.recv.not_nil!)
        w ".#{pony_method_name(t.name, false)}()"
      when FieldRead then emit_field_read(t)
      else                raise "bad assignment target"
      end
    end

    private def emit_op_assign(a : OpAssign) : Nil
      t = a.target
      if t.is_a?(Call)
        emit_receiver(t.recv.not_nil!)
        w ".set_#{t.name}("
        emit_receiver(t.recv.not_nil!)
        w ".#{pony_method_name(t.name, false)}() #{a.op} "
        emit_operand(a.value)
        w ")"
      else
        emit_lvalue(t)
        w " = "
        emit_lvalue(t)
        w " #{a.op} "
        emit_operand(a.value)
      end
    end

    private def emit_binary(b : Binary) : Nil
      if b.op == "<<"
        emit_receiver(b.left)
        @w.mark(b.line, b.col)
        w ".push("
        emit(b.right)
        w ")"
        return
      end
      emit_operand(b.left)
      w " #{BINARY_WORDS[b.op]? || b.op} "
      emit_operand(b.right)
    end

    private def emit_if(n : If) : Nil
      keyword = "if"
      cur = n
      if n.modifier && n.else_.nil? && inline_body?(n.then_)
        w "if "
        emit_cond(n)
        w " then "
        scoped { emit(n.then_[0]) }
        w " end"
        return
      end
      loop do
        w "#{keyword} "
        emit_cond(cur)
        w " then"
        scoped_block(cur.then_)
        @w.nl
        els = cur.else_
        if els && els.size == 1 && (nxt = els[0]).is_a?(If) && nxt.is_elsif
          keyword = "elseif"
          cur = nxt
        elsif els
          w "else"
          scoped_block(els)
          @w.nl
          w "end"
          break
        else
          w "end"
          break
        end
      end
    end

    private def inline_body?(body : Array(Expr)) : Bool
      body.size == 1 && simple?(body[0])
    end

    private def simple?(e : Expr) : Bool
      !(e.is_a?(If) || e.is_a?(While) || e.is_a?(Case) || e.is_a?(Begin) || e.is_a?(Recover) || e.is_a?(Call) && !e.as(Call).block.nil?)
    end

    private def emit_cond(n : If) : Nil
      if n.negate
        w "not ("
        emit(n.cond)
        w ")"
      else
        emit(n.cond)
      end
    end

    private def emit_while(n : While) : Nil
      w "while "
      if n.inverted
        w "not ("
        emit(n.cond)
        w ")"
      else
        emit(n.cond)
      end
      w " do"
      scoped_block(n.body)
      @w.nl
      w "end"
    end

    private def emit_loop(body : Array(Expr)) : Nil
      w "while true do"
      scoped_block(body)
      @w.nl
      w "end"
    end

    private def emit_case(c : Case) : Nil
      w "match "
      w "\\exhaustive\\ " if c.exhaustive
      emit(c.subject)
      c.whens.each do |wh|
        @w.nl
        mark(wh)
        scoped do
          wh.patterns.each_with_index do |p, i|
            w " | " if i > 0
            w "| " if i == 0
            emit_pattern(p)
          end
          w " =>"
          block(wh.body)
        end
      end
      if els = c.else_
        @w.nl
        w "else"
        scoped_block(els)
      end
      @w.nl
      w "end"
    end

    private def emit_pattern(p : Expr) : Nil
      mark(p)
      case p
      when TypePattern
        declare(p.name)
        w "let #{local(p.name)}: #{PonyType.to_pony(p.type)}"
      when TuplePattern
        w "("
        p.items.each_with_index do |item, i|
          w ", " if i > 0
          emit_pattern(item)
        end
        w ")"
      when Ident
        w(p.name == "_" ? "_" : local(p.name))
      else
        emit(p)
      end
    end

    private def emit_begin(b : Begin) : Nil
      w "try"
      scoped_block(b.body)
      if r = b.rescue_body
        @w.nl
        w "else"
        scoped_block(r)
      end
      if en = b.ensure_body
        @w.nl
        w "then"
        scoped_block(en)
      end
      @w.nl
      w "end"
    end

    private def emit_recover(r : Recover) : Nil
      w "recover"
      w " #{r.cap}" if r.cap
      scoped_block(r.body)
      @w.nl
      w "end"
    end

    private def emit_array(a : ArrayLit) : Nil
      of_type = a.of_type
      if a.elems.empty?
        w "Array[#{PonyType.to_pony(of_type.not_nil!)}].create()"
        return
      end
      w "["
      w "as #{PonyType.to_pony(of_type)}: " if of_type
      emit_list(a.elems, "; ")
      w "]"
    end

    private def emit_range(from : Expr, to : Expr, exclusive : Bool) : Nil
      @uses_collections = true
      w exclusive ? "Range[USize].till(" : "Range[USize].through("
      emit(from)
      w ", "
      emit(to)
      w ")"
    end

    private def emit_lambda(l : Lambda) : Nil
      w "{("
      emit_params(l.params)
      w ") =>"
      if inline_body?(l.body)
        w " "
        scoped do
          l.params.each { |p| declare(p.name) }
          emit(l.body[0])
        end
        w "}"
      else
        scoped_block(l.body, l.params.map(&.name))
        @w.nl
        w "}"
      end
    end

    private def emit_params(params : Array(Param)) : Nil
      params.each_with_index do |p, i|
        w ", " if i > 0
        w local(p.name)
        if t = p.type
          w ": #{PonyType.to_pony(t)}"
        end
      end
    end

    private def emit_amp(a : AmpMethod) : Nil
      var = "x"
      n = 1
      while declared?(var)
        var = "x#{n}"
        n += 1
      end
      w "{(#{var}) => #{var}.#{pony_method_name(a.name, false)}()#{partial_name?(a.name) ? "?" : ""}}"
    end

    # --- calls -------------------------------------------------------------

    private def emit_call(c : Call) : Nil
      if blk = c.block
        return if emit_loop_sugar(c, blk)
      end
      recv = c.recv
      if recv && c.name == "nil?" && c.args.empty?
        w "("
        emit_receiver(recv)
        w " is None)"
        return
      end
      constructor = recv.is_a?(TypeRef) && c.name == "new"
      if recv
        emit_receiver(recv)
        @w.mark(c.name_line, c.name_col)
        w "."
        @w.mark(c.name_line, c.name_col)
      end
      w pony_method_name(c.name, constructor)
      w "("
      first = true
      c.args.each do |a|
        w ", " unless first
        first = false
        emit(a)
      end
      if blk = c.block
        w ", " unless first
        first = false
        emit_lambda(blk)
      end
      unless c.named.empty?
        w " " unless first
        w "where "
        c.named.each_with_index do |n, i|
          w ", " if i > 0
          w "#{pony_ident(n.name)} = "
          emit(n.value)
        end
      end
      w ")"
      w "?" if partial_name?(c.name)
    end

    # Emits loop sugar (`each`, `each_with_index`, `times`, `loop`); returns
    # false when the call is an ordinary call taking a lambda.
    private def emit_loop_sugar(c : Call, blk : Lambda) : Bool
      recv = c.recv
      if recv.nil?
        return false unless c.name == "loop" && c.args.empty? && c.named.empty?
        emit_loop(blk.body)
        return true
      end
      return false unless LOOP_METHODS.includes?(c.name) && c.args.empty? && c.named.empty?
      params = blk.params.map(&.name)
      case c.name
      when "each"
        return false if params.size > 1
        w "for #{params.empty? ? "_" : local(params[0])} in "
        emit_iterable(recv)
        w ".values()" unless range_receiver(recv)
      when "each_with_index"
        return false unless params.size == 2
        w "for (#{local(params[1])}, #{local(params[0])}) in "
        emit_receiver(recv)
        w ".pairs()"
      else
        return false if params.size > 1
        w "for #{params.empty? ? "_" : local(params[0])} in Range[USize].till(0, "
        @uses_collections = true
        emit(recv)
        w ")"
      end
      w " do"
      scoped_block(blk.body, params)
      @w.nl
      w "end"
      true
    end

    private def range_receiver(recv : Expr) : RangeLit?
      r = recv
      while r.is_a?(Paren)
        r = r.expr
      end
      r.as?(RangeLit)
    end

    private def emit_iterable(recv : Expr) : Nil
      if r = range_receiver(recv)
        emit_range(r.from, r.to, r.exclusive)
      else
        emit_receiver(recv)
      end
    end
  end
end
