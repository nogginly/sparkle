require "./token"

module Sparkle
  # Converts Sparkle source text into tokens. Newlines are emitted as
  # `Newline` tokens except where the line obviously continues.
  class Lexer
    KEYWORDS = Set{
      "class", "actor", "struct", "primitive", "trait", "interface", "def", "be",
      "end", "if", "elsif", "else", "unless", "while", "until", "do", "case",
      "when", "in", "then", "begin", "rescue", "ensure", "raise", "return",
      "break", "next", "self", "nil", "true", "false", "consume", "recover",
      "use", "alias", "include", "abstract", "is", "isnt", "of",
    }

    OPERATORS = [
      "...", "..", "&.", "->", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||",
      "+=", "-=", "*=", "/=", "%=",
    ]
    SINGLE = "+-*/%=<>!&|?:,.()[]{};^~"

    CONTINUATION = Set{
      ",", ".", "(", "[", "{", "+", "-", "*", "/", "%", "=", "==", "!=", "<",
      "<=", ">", ">=", "&&", "||", "&", "<<", ">>", "+=", "-=", "*=", "/=",
      "%=", "?", ":", "..", "...", "&.", "->",
    }

    SUFFIX     = /_?([iuf])(8|16|32|64|128)\z/
    HEX_SUFFIX = /_?([iu])(8|16|32|64|128)\z/

    @chars : Array(Char)
    @pos = 0
    @tokens = [] of Token

    def initialize(source : String, @line : Int32 = 1, @col : Int32 = 1)
      @chars = source.chars
    end

    def tokenize : Array(Token)
      space = false
      while @pos < @chars.size
        c = @chars[@pos]
        if c == ' ' || c == '\t' || c == '\r'
          advance
          space = true
        elsif c == '#'
          while @pos < @chars.size && @chars[@pos] != '\n'
            advance
          end
        elsif c == '\n'
          newline
          space = true
        else
          lex_token(c, space)
          space = false
        end
      end
      @tokens << Token.new(Kind::Newline, "\n", @line, @col) unless @tokens.empty? || @tokens.last.kind.newline?
      @tokens << Token.new(Kind::EOF, "", @line, @col)
      @tokens
    end

    private def advance : Nil
      if @chars[@pos] == '\n'
        @line += 1
        @col = 1
      else
        @col += 1
      end
      @pos += 1
    end

    private def peek(n = 0) : Char
      @chars[@pos + n]? || '\0'
    end

    private def newline : Nil
      line, col = @line, @col
      advance
      return if @tokens.empty? || @tokens.last.kind.newline?
      last = @tokens.last
      return if last.kind.op? && CONTINUATION.includes?(last.text)
      return if next_line_starts_with_dot?
      @tokens << Token.new(Kind::Newline, "\n", line, col)
    end

    private def next_line_starts_with_dot? : Bool
      i = @pos
      loop do
        while i < @chars.size && (@chars[i] == ' ' || @chars[i] == '\t' || @chars[i] == '\r' || @chars[i] == '\n')
          i += 1
        end
        if i < @chars.size && @chars[i] == '#'
          while i < @chars.size && @chars[i] != '\n'
            i += 1
          end
          next
        end
        break
      end
      i < @chars.size && @chars[i] == '.' && @chars[i + 1]? != '.'
    end

    private def lex_token(c : Char, space : Bool) : Nil
      line, col = @line, @col
      if c.ascii_lowercase? || c == '_'
        lex_ident(line, col, space)
      elsif c.ascii_uppercase?
        text = take_while { |ch| ch.ascii_alphanumeric? || ch == '_' }
        @tokens << Token.new(Kind::Const, text, line, col, space)
      elsif c == '@' && (peek(1).ascii_letter? || peek(1) == '_')
        advance
        text = take_while { |ch| ch.ascii_alphanumeric? || ch == '_' }
        @tokens << Token.new(Kind::InstVar, text, line, col, space)
      elsif c.ascii_number?
        lex_number(line, col, space)
      elsif c == '"'
        lex_string(line, col, space)
      elsif c == '\''
        lex_char(line, col, space)
      else
        lex_operator(c, line, col, space)
      end
    end

    private def take_while(&) : String
      String.build do |s|
        while @pos < @chars.size && yield(@chars[@pos])
          s << @chars[@pos]
          advance
        end
      end
    end

    private def lex_ident(line, col, space) : Nil
      text = take_while { |ch| ch.ascii_alphanumeric? || ch == '_' }
      if (peek == '?' || peek == '!') && peek(1) != '='
        text += peek.to_s
        advance
        @tokens << Token.new(Kind::Ident, text, line, col, space)
      elsif KEYWORDS.includes?(text)
        @tokens << Token.new(Kind::Kw, text, line, col, space)
      else
        @tokens << Token.new(Kind::Ident, text, line, col, space)
      end
    end

    private def lex_number(line, col, space) : Nil
      float = false
      text = String.build do |s|
        if peek == '0' && (peek(1) == 'x' || peek(1) == 'b')
          hex = peek(1) == 'x'
          s << peek << peek(1)
          advance
          advance
          while @pos < @chars.size
            ch = peek
            break unless ch == '_' || (hex ? ch.hex? : (ch == '0' || ch == '1'))
            break if ch == '_' && (peek(1) == 'i' || peek(1) == 'u')
            s << ch
            advance
          end
        else
          digits(s)
          if peek == '.' && peek(1).ascii_number?
            float = true
            s << '.'
            advance
            digits(s)
          end
          if (peek == 'e' || peek == 'E') && (peek(1).ascii_number? || ((peek(1) == '-' || peek(1) == '+') && peek(2).ascii_number?))
            float = true
            s << peek
            advance
            if peek == '-' || peek == '+'
              s << peek
              advance
            end
            digits(s)
          end
        end
        take_suffix(s)
      end
      suffix = nil
      if m = (text.starts_with?("0x") ? HEX_SUFFIX : SUFFIX).match(text)
        suffix = "#{m[1].upcase}#{m[2]}"
        text = text[0, m.begin(0)]
        float = true if m[1] == "f"
      end
      tok = Token.new(float ? Kind::Float : Kind::Int, text, line, col, space)
      tok.suffix = suffix
      @tokens << tok
    end

    private def take_suffix(s : String::Builder) : Nil
      if peek == '_' && (peek(1) == 'i' || peek(1) == 'u' || peek(1) == 'f') && peek(2).ascii_number?
        s << '_'
        advance
      end
      if (peek == 'i' || peek == 'u' || peek == 'f') && peek(1).ascii_number?
        while peek.ascii_alphanumeric?
          s << peek
          advance
        end
      end
    end

    private def digits(s : String::Builder) : Nil
      while @pos < @chars.size
        ch = peek
        break unless ch.ascii_number? || (ch == '_' && peek(1).ascii_number?)
        s << ch
        advance
      end
    end

    private def lex_char(line, col, space) : Nil
      advance
      text = String.build do |s|
        while @pos < @chars.size && peek != '\''
          if peek == '\\'
            s << peek
            advance
          end
          s << peek
          advance
        end
      end
      raise ParseError.new("unterminated character literal", line, col) if @pos >= @chars.size
      advance
      @tokens << Token.new(Kind::Char, text, line, col, space)
    end

    private def lex_string(line, col, space) : Nil
      advance
      parts = [] of StrPart
      buf = String::Builder.new
      closed = false
      while @pos < @chars.size
        ch = peek
        if ch == '"'
          advance
          closed = true
          break
        elsif ch == '\\'
          if peek(1) == '#'
            buf << '#'
          else
            buf << ch << peek(1)
          end
          advance
          advance
        elsif ch == '#' && peek(1) == '{'
          parts << buf.to_s unless buf.empty?
          buf = String::Builder.new
          advance
          advance
          start = @pos
          stop = interpolation_end(start)
          raise ParseError.new("unterminated string interpolation", line, col) unless stop
          inner = @chars[start...stop].join
          sub = Lexer.new(inner, @line, @col)
          toks = sub.tokenize
          parts << toks
          (stop - start).times { advance }
          advance
        else
          buf << ch
          advance
        end
      end
      raise ParseError.new("unterminated string literal", line, col) unless closed
      parts << buf.to_s unless buf.empty?
      tok = Token.new(Kind::Str, "", line, col, space)
      tok.parts = parts
      @tokens << tok
    end

    # Returns the index of the `}` closing an interpolation that starts at `i`.
    private def interpolation_end(i : Int32) : Int32?
      depth = 1
      while i < @chars.size
        case @chars[i]
        when '{'
          depth += 1
        when '}'
          depth -= 1
          return i if depth == 0
        when '"'
          i = skip_string(i + 1)
          return nil unless i
          next
        end
        i += 1
      end
      nil
    end

    private def skip_string(i : Int32) : Int32?
      while i < @chars.size
        case @chars[i]
        when '\\'
          i += 1
        when '"'
          return i + 1
        when '#'
          if @chars[i + 1]? == '{'
            stop = interpolation_end(i + 2)
            return nil unless stop
            i = stop
          end
        end
        i += 1
      end
      nil
    end

    private def lex_operator(c : Char, line, col, space) : Nil
      OPERATORS.each do |op|
        if op.each_char.with_index.all? { |ch, k| peek(k) == ch }
          op.size.times { advance }
          @tokens << Token.new(Kind::Op, op, line, col, space)
          return
        end
      end
      if SINGLE.includes?(c)
        advance
        @tokens << Token.new(Kind::Op, c.to_s, line, col, space)
        return
      end
      raise ParseError.new("unexpected character '#{c}'", line, col)
    end
  end
end
