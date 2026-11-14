module Sparkle
  enum Kind
    Ident
    Const
    InstVar
    Int
    Float
    Str
    Char
    Kw
    Op
    Newline
    EOF
  end

  alias StrPart = String | Array(Token)

  # A lexical token. `parts` is set for strings (literal text and interpolated
  # token streams); `suffix` is set for numbers with a Crystal type suffix.
  class Token
    getter kind : Kind
    getter text : String
    getter line : Int32
    getter col : Int32
    getter? space_before : Bool
    property parts : Array(StrPart)?
    property suffix : String?

    def initialize(@kind, @text, @line, @col, @space_before = false)
    end

    def op?(s : String) : Bool
      @kind.op? && @text == s
    end

    def kw?(s : String) : Bool
      @kind.kw? && @text == s
    end

    def to_s(io : IO) : Nil
      io << (@kind.newline? ? "end of line" : @kind.eof? ? "end of file" : "'#{@text}'")
    end
  end

  class ParseError < Exception
    getter line : Int32
    getter col : Int32

    def initialize(message : String, @line : Int32, @col : Int32)
      super(message)
    end
  end
end
