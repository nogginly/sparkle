require "./token"
require "./lexer"
require "./ast"

module Sparkle
  # Recursive-descent parser producing a `Program`. Raises `ParseError`.
  class Parser
    TYPE_KINDS  = %w(class actor struct primitive trait interface)
    TERMINATORS = %w(end else elsif when rescue ensure)
    BINARY_PREC = {
      "||" => 1, "&&" => 2,
      "==" => 3, "!=" => 3, "<" => 3, "<=" => 3, ">" => 3, ">=" => 3, "is" => 3, "isnt" => 3,
      "<<" => 4, ">>" => 4,
      "+" => 5, "-" => 5,
      "*" => 6, "/" => 6, "%" => 6,
    }
    OP_ASSIGN       = {"+=" => "+", "-=" => "-", "*=" => "*", "/=" => "/", "%=" => "%"}
    OPERATOR_METHOD = %w(+ - * / % == != < <= > >= << >>)

    @i = 0
    @caps = [] of CapUse

    def self.parse(source : String) : Program
      new(Lexer.new(source).tokenize).parse_program
    end

    def initialize(@tokens : Array(Token))
    end

    def parse_program : Program
      items = [] of Node
      loop do
        skip_separators
        break if tok.kind.eof?
        items << parse_toplevel
      end
      Program.new(items, @caps)
    end

    # Parses a token stream that holds exactly one expression (string
    # interpolation).
    def parse_standalone : Expr
      skip_separators
      e = parse_expr
      skip_separators
      error("unexpected #{tok} in interpolation") unless tok.kind.eof?
      e
    end

    private def tok : Token
      @tokens[@i]
    end

    private def peek(n = 1) : Token
      @tokens[Math.min(@i + n, @tokens.size - 1)]
    end

    private def advance : Token
      t = @tokens[@i]
      @i += 1 if @i < @tokens.size - 1
      t
    end

    private def error(msg : String, t : Token = tok) : NoReturn
      raise ParseError.new(msg, t.line, t.col)
    end

    private def accept_op(s : String) : Bool
      return false unless tok.op?(s)
      advance
      true
    end

    private def accept_kw(s : String) : Bool
      return false unless tok.kw?(s)
      advance
      true
    end

    private def expect_op(s : String) : Token
      error("expected '#{s}' but found #{tok}") unless tok.op?(s)
      advance
    end

    private def expect_kw(s : String) : Token
      error("expected '#{s}' but found #{tok}") unless tok.kw?(s)
      advance
    end

    private def expect_kind(kind : Kind, what : String) : Token
      error("expected #{what} but found #{tok}") unless tok.kind == kind
      advance
    end

    private def skip_nl : Nil
      while tok.kind.newline?
        advance
      end
    end

    private def skip_separators : Nil
      while tok.kind.newline? || tok.op?(";")
        advance
      end
    end

    private def cap_use(position : String, cap : String, t : Token) : Nil
      @caps << CapUse.new(position, cap, t.line, t.col)
    end

    private def parse_toplevel : Node
      t = tok
      if t.kw?("use")
        advance
        s = expect_kind(Kind::Str, "a string")
        UseDecl.new(t.line, t.col, plain_string(s))
      elsif t.kw?("alias")
        advance
        name = expect_kind(Kind::Const, "a type name").text
        expect_op("=")
        AliasDecl.new(t.line, t.col, name, parse_type)
      elsif t.kind.kw? && TYPE_KINDS.includes?(t.text)
        parse_type_decl
      else
        error("expected a type declaration (class, actor, ...) but found #{t}")
      end
    end

    private def plain_string(t : Token) : String
      parts = t.parts.not_nil!
      error("interpolation is not allowed here", t) unless parts.all?(String)
      parts.join
    end

    private def parse_type_decl : TypeDecl
      kw = advance
      cap = nil
      if tok.kind.ident? && CAPABILITIES.includes?(tok.text) && peek.kind.const?
        cap = tok.text
        cap_use("type declaration", cap, tok)
        advance
      end
      name = expect_kind(Kind::Const, "a type name").text
      tparams = [] of TypeParam
      tparams = parse_type_params if tok.op?("(") && !tok.space_before?
      decl = TypeDecl.new(kw.line, kw.col, kw.text, cap, name, tparams, [] of TypeNode, [] of Field, [] of Method)
      loop do
        skip_separators
        t = tok
        if t.kw?("end")
          advance
          break
        elsif t.kw?("include")
          advance
          decl.includes << parse_type
        elsif t.kind.inst_var?
          decl.fields << parse_field
        elsif t.kw?("def") || t.kw?("be") || t.kw?("abstract")
          decl.methods << parse_method
        else
          error("unexpected #{t} in #{kw.text} body")
        end
      end
      decl
    end

    private def parse_type_params : Array(TypeParam)
      expect_op("(")
      list = [] of TypeParam
      loop do
        skip_nl
        n = expect_kind(Kind::Const, "a type parameter name")
        constraint = nil
        if accept_op(":")
          constraint = parse_type
        end
        list << TypeParam.new(n.line, n.col, n.text, constraint)
        skip_nl
        break unless accept_op(",")
      end
      expect_op(")")
      list
    end

    private def parse_field : Field
      t = advance
      error("an instance variable needs a type: '@#{t.text} : Type'", t) unless tok.op?(":")
      advance
      type = parse_type
      init = accept_op("=") ? parse_expr : nil
      Field.new(t.line, t.col, t.text, type, init)
    end

    private def cap_follows? : Bool
      return false unless tok.kind.ident? && CAPABILITIES.includes?(tok.text)
      n = peek
      return true if n.kind.ident? || n.kw?("self")
      n.kind.op? && !%w[= ( : . ,].includes?(n.text)
    end

    private def parse_method : Method
      start = advance
      kind = start.text
      if kind == "abstract"
        expect_kw("def")
      end
      cap = nil
      if kind != "be" && cap_follows?
        cap = tok.text
        cap_use("def", cap, tok)
        advance
      end
      self_recv = false
      if tok.kw?("self") && peek.op?(".")
        self_recv = true
        advance
        advance
      end
      nt = tok
      name = parse_method_name
      params = tok.op?("(") ? parse_params : [] of Param
      ret = nil
      if accept_op(":")
        ret = parse_type
      end
      body = nil
      if kind != "abstract"
        if accept_op("=")
          body = [parse_stmt]
        else
          body = parse_stmts
          expect_kw("end")
        end
      end
      Method.new(start.line, start.col, kind, cap, self_recv, name, params, ret, body, nt.line, nt.col)
    end

    private def parse_method_name : String
      t = tok
      case t.kind
      when Kind::Ident
        advance
        if tok.op?("=") && !tok.space_before? && peek.op?("(")
          advance
          return t.text + "="
        end
        t.text
      when Kind::Op
        if t.text == "["
          advance
          expect_op("]")
          if (tok.op?("!") || tok.op?("=")) && !tok.space_before?
            return "[]" + advance.text
          end
          "[]"
        elsif OPERATOR_METHOD.includes?(t.text)
          advance
          t.text
        else
          error("expected a method name but found #{t}")
        end
      else
        error("expected a method name but found #{t}")
      end
    end

    private def parse_params : Array(Param)
      expect_op("(")
      list = [] of Param
      skip_nl
      until tok.op?(")")
        n = expect_kind(Kind::Ident, "a parameter name")
        type = nil
        if accept_op(":")
          type = parse_type
        end
        default = accept_op("=") ? parse_expr : nil
        list << Param.new(n.line, n.col, n.text, type, default)
        skip_nl
        break unless accept_op(",")
        skip_nl
      end
      expect_op(")")
      list
    end

    # --- types -----------------------------------------------------------

    def parse_type : TypeNode
      first = parse_type_isect
      return first unless tok.op?("|")
      types = [first]
      while accept_op("|")
        types << parse_type_isect
      end
      UnionType.new(first.line, first.col, types)
    end

    private def parse_type_isect : TypeNode
      first = parse_type_arrow
      return first unless tok.op?("&")
      types = [first]
      while accept_op("&")
        types << parse_type_arrow
      end
      IsectType.new(first.line, first.col, types)
    end

    private def parse_type_arrow : TypeNode
      left = parse_type_atom
      if tok.op?("->")
        advance
        return ArrowType.new(left.line, left.col, left, parse_type_arrow)
      end
      left
    end

    private def parse_type_atom : TypeNode
      t = tok
      node = if t.op?("(")
               advance
               inner = parse_type
               expect_op(")")
               inner
             elsif t.op?("{")
               advance
               types = [parse_type]
               while accept_op(",")
                 types << parse_type
               end
               expect_op("}")
               TupleType.new(t.line, t.col, types)
             elsif t.kind.ident? && t.text == "this"
               advance
               NamedType.new(t.line, t.col, "this")
             elsif t.kind.ident? && ALL_CAPS.includes?(t.text)
               parse_cap_type
             elsif t.kind.const?
               parse_named_type(nil)
             else
               error("expected a type but found #{t}")
             end
      if tok.op?("?") && !tok.space_before?
        q = advance
        node = UnionType.new(node.line, node.col, [node, NamedType.new(q.line, q.col, "Nil")] of TypeNode)
      end
      node
    end

    private def parse_cap_type : TypeNode
      t = advance
      cap_use("type", t.text, t)
      return CapType.new(t.line, t.col, t.text) if tok.op?("->")
      eph = nil
      if (tok.op?("^") || tok.op?("!")) && !tok.space_before?
        eph = advance.text
      end
      if tok.kind.const?
        n = parse_named_type(t.text)
        case n
        when NamedType then n.eph = eph || n.eph
        when ProcType  then n.eph = eph || n.eph
        end
        n
      else
        CapType.new(t.line, t.col, t.text)
      end
    end

    private def parse_named_type(cap : String?) : TypeNode
      t = expect_kind(Kind::Const, "a type name")
      args = [] of TypeNode
      if tok.op?("(") && !tok.space_before?
        advance
        skip_nl
        until tok.op?(")")
          args << parse_type
          skip_nl
          break unless accept_op(",")
          skip_nl
        end
        expect_op(")")
      end
      eph = nil
      if (tok.op?("^") || tok.op?("!")) && !tok.space_before?
        eph = advance.text
      end
      if t.text == "Proc" && !args.empty?
        return ProcType.new(t.line, t.col, args[0...-1], args.last, cap, eph)
      end
      NamedType.new(t.line, t.col, t.text, args, cap, eph)
    end

    # --- statements ------------------------------------------------------

    private def at_terminator? : Bool
      tok.kind.eof? || (tok.kind.kw? && TERMINATORS.includes?(tok.text)) || tok.op?("}")
    end

    private def parse_stmts : Array(Expr)
      stmts = [] of Expr
      loop do
        skip_separators
        break if at_terminator?
        stmts << parse_stmt
        unless tok.kind.newline? || tok.op?(";") || at_terminator?
          error("unexpected #{tok}")
        end
      end
      stmts
    end

    private def parse_stmt : Expr
      t = tok
      e = if t.kind.ident? && peek.op?(":")
            advance
            advance
            type = parse_type
            expect_op("=")
            Assign.new(t.line, t.col, Ident.new(t.line, t.col, t.text), parse_expr, type)
          else
            parse_expr
          end
      while tok.kw?("if") || tok.kw?("unless")
        m = advance
        cond = parse_expr
        e = If.new(e.line, e.col, cond, [e], nil, m.text == "unless", false, true)
      end
      e
    end

    def parse_expr : Expr
      left = parse_ternary
      t = tok
      if t.op?("=")
        check_target(left)
        advance
        skip_nl
        return Assign.new(left.line, left.col, left, parse_expr, nil)
      elsif t.kind.op? && (op = OP_ASSIGN[t.text]?)
        check_target(left)
        advance
        skip_nl
        return OpAssign.new(left.line, left.col, left, op, parse_expr)
      end
      left
    end

    private def check_target(e : Expr) : Nil
      ok = case e
           when Ident, IVarRef, Index, FieldRead then true
           when Call                             then !e.recv.nil? && e.args.empty? && !e.parens && e.block.nil?
           else                                       false
           end
      raise ParseError.new("invalid assignment target", e.line, e.col) unless ok
    end

    private def parse_ternary : Expr
      cond = parse_range
      if tok.op?("?")
        advance
        skip_nl
        a = parse_ternary
        skip_nl
        expect_op(":")
        skip_nl
        b = parse_ternary
        return Ternary.new(cond.line, cond.col, cond, a, b)
      end
      cond
    end

    private def parse_range : Expr
      left = parse_binary(1)
      if tok.op?("..") || tok.op?("...")
        op = advance
        right = parse_binary(1)
        return RangeLit.new(left.line, left.col, left, right, op.text == "...")
      end
      left
    end

    private def binary_op : {String, Int32}?
      t = tok
      return nil unless t.kind.op? || t.kw?("is") || t.kw?("isnt")
      prec = BINARY_PREC[t.text]?
      prec ? {t.text, prec} : nil
    end

    private def parse_binary(min : Int32) : Expr
      left = parse_unary
      while (info = binary_op) && info[1] >= min
        advance
        skip_nl
        right = parse_binary(info[1] + 1)
        left = Binary.new(left.line, left.col, info[0], left, right)
      end
      left
    end

    private def parse_unary : Expr
      t = tok
      if t.op?("!")
        advance
        Unary.new(t.line, t.col, "!", parse_unary)
      elsif t.op?("-")
        advance
        n = tok
        if (n.kind.int? || n.kind.float?) && !n.space_before?
          advance
          text = "-" + n.text
          lit = n.kind.int? ? IntLit.new(t.line, t.col, text, n.suffix) : FloatLit.new(t.line, t.col, text, n.suffix)
          parse_postfix(lit)
        else
          Unary.new(t.line, t.col, "-", parse_unary)
        end
      elsif t.kw?("consume")
        advance
        Consume.new(t.line, t.col, parse_unary)
      elsif t.op?("&.")
        advance
        n = advance
        error("expected a method name after '&.'", n) unless n.kind.ident? || n.kind.kw?
        AmpMethod.new(t.line, t.col, n.text)
      else
        parse_postfix(parse_primary)
      end
    end

    private def number(t : Token) : Expr
      if t.kind.int?
        IntLit.new(t.line, t.col, t.text, t.suffix)
      else
        FloatLit.new(t.line, t.col, t.text, t.suffix)
      end
    end

    private def parse_postfix(e : Expr) : Expr
      loop do
        t = tok
        if t.op?(".")
          advance
          n = advance
          if n.kind.inst_var?
            e = FieldRead.new(e.line, e.col, e, n.text)
            next
          end
          error("expected a method name after '.' but found #{n}", n) unless n.kind.ident? || n.kind.const? || n.kind.kw?
          e = parse_call_rest(e, n)
        elsif t.op?("[") && !t.space_before?
          advance
          skip_nl
          args = [] of Expr
          until tok.op?("]")
            args << parse_expr
            skip_nl
            break unless accept_op(",")
            skip_nl
          end
          expect_op("]")
          bang = false
          if tok.op?("!") && !tok.space_before?
            advance
            bang = true
          end
          e = Index.new(e.line, e.col, e, args, bang)
        elsif t.op?("(") && !t.space_before? && e.is_a?(Ident)
          call = parse_call_rest(nil, Token.new(Kind::Ident, e.name, e.line, e.col))
          e = call
        elsif (t.kw?("do") || (t.op?("{") && peek.op?("|"))) && callish?(e)
          blk = parse_block
          c = e.is_a?(Ident) ? Call.new(e.line, e.col, nil, e.name, [] of Expr, [] of NamedArg, nil, false, e.line, e.col) : e.as(Call)
          c.block = blk
          e = c
        else
          break
        end
      end
      e
    end

    private def callish?(e : Expr) : Bool
      case e
      when Ident then true
      when Call  then e.block.nil?
      else            false
      end
    end

    # Parses arguments and an optional block after a method name token `n`.
    private def parse_call_rest(recv : Expr?, n : Token) : Expr
      args = [] of Expr
      named = [] of NamedArg
      parens = false
      if tok.op?("(") && !tok.space_before?
        parens = true
        advance
        if n.text == "as!"
          error("'as!' needs a receiver", n) unless recv
          type = parse_type
          expect_op(")")
          return AsCast.new(recv.line, recv.col, recv, type)
        end
        skip_nl
        until tok.op?(")")
          if tok.kind.ident? && peek.op?(":") && !peek.space_before?
            nt = advance
            advance
            skip_nl
            named << NamedArg.new(nt.line, nt.col, nt.text, parse_expr)
          else
            args << parse_expr
          end
          skip_nl
          break unless accept_op(",")
          skip_nl
        end
        expect_op(")")
      end
      block = nil
      if tok.kw?("do") || (tok.op?("{") && peek.op?("|"))
        block = parse_block
      end
      line = recv ? recv.line : n.line
      col = recv ? recv.col : n.col
      Call.new(line, col, recv, n.text, args, named, block, parens, n.line, n.col)
    end

    private def parse_block : Lambda
      t = advance
      brace = t.op?("{")
      params = [] of Param
      if accept_op("|")
        until tok.op?("|")
          n = expect_kind(Kind::Ident, "a block parameter name")
          params << Param.new(n.line, n.col, n.text, nil, nil)
          break unless accept_op(",")
        end
        expect_op("|")
      end
      body = parse_stmts
      if brace
        expect_op("}")
      else
        expect_kw("end")
      end
      Lambda.new(t.line, t.col, params, body, brace)
    end

    # --- primaries -------------------------------------------------------

    private def parse_primary : Expr
      t = tok
      case t.kind
      when Kind::Int, Kind::Float
        advance
        number(t)
      when Kind::Str
        advance
        parse_string(t)
      when Kind::Char
        advance
        CharLit.new(t.line, t.col, t.text)
      when Kind::Ident
        advance
        Ident.new(t.line, t.col, t.text)
      when Kind::InstVar
        advance
        IVarRef.new(t.line, t.col, t.text)
      when Kind::Const
        parse_const_ref
      when Kind::Kw
        parse_keyword
      when Kind::Op
        parse_op_primary
      else
        error("unexpected #{t}")
      end
    end

    private def parse_string(t : Token) : Expr
      parts = [] of String | Expr
      t.parts.not_nil!.each do |p|
        case p
        in String
          parts << p
        in Array(Token)
          parts << Parser.new(p).parse_standalone
        end
      end
      StrLit.new(t.line, t.col, parts)
    end

    private def parse_const_ref : Expr
      t = advance
      args = [] of TypeNode
      if tok.op?("(") && !tok.space_before?
        advance
        skip_nl
        until tok.op?(")")
          args << parse_type
          skip_nl
          break unless accept_op(",")
          skip_nl
        end
        expect_op(")")
      end
      TypeRef.new(t.line, t.col, NamedType.new(t.line, t.col, t.text, args))
    end

    private def parse_op_primary : Expr
      t = tok
      case t.text
      when "("
        advance
        skip_nl
        e = parse_expr
        skip_nl
        expect_op(")")
        Paren.new(t.line, t.col, e)
      when "["
        advance
        skip_nl
        elems = [] of Expr
        until tok.op?("]")
          elems << parse_expr
          skip_nl
          break unless accept_op(",")
          skip_nl
        end
        expect_op("]")
        of_type = nil
        if accept_kw("of")
          of_type = parse_type
        end
        error("an empty array literal needs 'of Type'", t) if elems.empty? && of_type.nil?
        ArrayLit.new(t.line, t.col, elems, of_type)
      when "{"
        advance
        skip_nl
        items = [] of Expr
        loop do
          items << parse_expr
          skip_nl
          break unless accept_op(",")
          skip_nl
        end
        expect_op("}")
        TupleLit.new(t.line, t.col, items)
      else
        error("unexpected #{t}")
      end
    end

    private def parse_keyword : Expr
      t = tok
      case t.text
      when "self"
        advance
        SelfRef.new(t.line, t.col)
      when "nil"
        advance
        NilLit.new(t.line, t.col)
      when "true", "false"
        advance
        BoolLit.new(t.line, t.col, t.text == "true")
      when "if", "unless"
        advance
        parse_if(t, t.text == "unless")
      when "while", "until"
        advance
        cond = parse_expr
        body = parse_stmts
        expect_kw("end")
        While.new(t.line, t.col, cond, body, t.text == "until")
      when "case"
        parse_case
      when "begin"
        parse_begin
      when "raise"
        advance
        error("'raise' takes no argument", tok) unless tok.kind.newline? || tok.kw?("if") || tok.kw?("unless") || at_terminator? || tok.op?(";")
        Raise.new(t.line, t.col)
      when "return"
        advance
        value = value_follows? ? parse_expr : nil
        Return.new(t.line, t.col, value)
      when "break"
        advance
        Break.new(t.line, t.col)
      when "next"
        advance
        Next.new(t.line, t.col)
      when "recover"
        advance
        cap = nil
        if tok.kind.ident? && CAPABILITIES.includes?(tok.text)
          cap = tok.text
          cap_use("recover", cap, tok)
          advance
        end
        expect_kw("do")
        body = parse_stmts
        expect_kw("end")
        Recover.new(t.line, t.col, cap, body)
      else
        error("unexpected #{t}")
      end
    end

    private def value_follows? : Bool
      !(tok.kind.newline? || tok.kw?("if") || tok.kw?("unless") || at_terminator? || tok.op?(";"))
    end

    private def parse_if(start : Token, negate : Bool, is_elsif : Bool = false) : If
      cond = parse_expr
      accept_kw("then")
      body = parse_stmts
      else_body = nil
      if tok.kw?("elsif")
        e = advance
        else_body = [parse_if(e, false, true).as(Expr)]
        return If.new(start.line, start.col, cond, body, else_body, negate, is_elsif)
      elsif accept_kw("else")
        else_body = parse_stmts
      end
      expect_kw("end")
      If.new(start.line, start.col, cond, body, else_body, negate, is_elsif)
    end

    private def parse_case : Expr
      t = advance
      subject = parse_expr
      exhaustive = accept_kw("in")
      whens = [] of When
      else_body = nil
      skip_separators
      while tok.kw?("when")
        w = advance
        pats = [parse_pattern]
        while accept_op(",")
          skip_nl
          pats << parse_pattern
        end
        accept_kw("then")
        whens << When.new(w.line, w.col, pats, parse_stmts)
      end
      error("expected 'when' but found #{tok}") if whens.empty?
      else_body = parse_stmts if accept_kw("else")
      expect_kw("end")
      Case.new(t.line, t.col, subject, whens, else_body, exhaustive)
    end

    private def parse_pattern : Expr
      t = tok
      if t.op?("{")
        advance
        items = [parse_pattern]
        while accept_op(",")
          items << parse_pattern
        end
        expect_op("}")
        TuplePattern.new(t.line, t.col, items)
      elsif t.kind.ident? && peek.op?(":")
        advance
        advance
        TypePattern.new(t.line, t.col, t.text, parse_type)
      else
        parse_ternary
      end
    end

    private def parse_begin : Expr
      t = advance
      body = parse_stmts
      rescue_body = nil
      ensure_body = nil
      rescue_body = parse_stmts if accept_kw("rescue")
      ensure_body = parse_stmts if accept_kw("ensure")
      expect_kw("end")
      Begin.new(t.line, t.col, body, rescue_body, ensure_body)
    end
  end
end
