require "./ast"

module Sparkle
  # Converts type nodes to Pony syntax, parses Pony type text and prints it in
  # Sparkle syntax.
  module PonyType
    TO_PONY = {
      "Int8" => "I8", "Int16" => "I16", "Int32" => "I32", "Int64" => "I64", "Int128" => "I128",
      "UInt8" => "U8", "UInt16" => "U16", "UInt32" => "U32", "UInt64" => "U64", "UInt128" => "U128",
      "Float32" => "F32", "Float64" => "F64", "Nil" => "None",
    }
    TO_SPARKLE = TO_PONY.map { |k, v| {v, k} }.to_h

    def self.pony_cap(cap : String) : String
      GENERIC_CAPS.includes?(cap) ? "##{cap}" : cap
    end

    def self.sparkle_cap(cap : String) : String
      cap.starts_with?('#') ? cap[1..] : cap
    end

    # --- Sparkle -> Pony ---------------------------------------------------

    def self.to_pony(t : TypeNode) : String
      case t
      when NamedType
        named_to_pony(t)
      when CapType
        "Any #{pony_cap(t.cap)}"
      when UnionType
        "(" + t.types.map { |member| to_pony(member) }.join(" | ") + ")"
      when IsectType
        "(" + t.types.map { |member| to_pony(member) }.join(" & ") + ")"
      when TupleType
        "(" + t.types.map { |member| to_pony(member) }.join(", ") + ")"
      when ArrowType
        left = t.left.is_a?(CapType) ? pony_cap(t.left.as(CapType).cap) : to_pony(t.left)
        "#{left}->#{to_pony(t.right)}"
      when ProcType
        proc_to_pony(t)
      else
        raise "unknown type node"
      end
    end

    private def self.named_to_pony(t : NamedType) : String
      String.build do |buffer|
        buffer << (TO_PONY[t.name]? || t.name)
        unless t.args.empty?
          buffer << '[' << t.args.map { |arg| to_pony(arg) }.join(", ") << ']'
        end
        if cap = t.cap
          buffer << ' ' << pony_cap(cap)
        end
        buffer << t.eph if t.eph
      end
    end

    private def self.proc_to_pony(t : ProcType) : String
      String.build do |buffer|
        buffer << "{(" << t.params.map { |param| to_pony(param) }.join(", ") << ')'
        ret = t.ret
        unless ret.nil? || (ret.is_a?(NamedType) && ret.name == "Nil" && ret.args.empty?)
          buffer << ": " << to_pony(ret)
        end
        buffer << '?' if t.partial
        buffer << '}'
        if cap = t.cap
          buffer << ' ' << pony_cap(cap)
        end
        buffer << t.eph if t.eph
      end
    end

    # --- Pony text -> type nodes -------------------------------------------

    class PonyParser
      CAP_WORDS = %w(iso trn ref val box tag)

      def initialize(@s : Array(Char), @i : Int32 = 0)
      end

      getter i

      def parse_type : TypeNode?
        left = parse_atom
        return nil unless left
        save = @i
        skip_space
        if peek?("->")
          @i += 2
          skip_space
          right = parse_type
          return nil unless right
          return ArrowType.new(0, 0, left, right)
        end
        @i = save
        left
      end

      private def peek?(str : String) : Bool
        str.each_char.with_index.all? { |char, k| @s[@i + k]? == char }
      end

      private def skip_space : Nil
        while @s[@i]? == ' '
          @i += 1
        end
      end

      private def word : String?
        j = @i
        while (c = @s[j]?) && (c.ascii_alphanumeric? || c == '_')
          j += 1
        end
        j > @i ? @s[@i...j].join : nil
      end

      private def cap : String?
        if peek?("#")
          @i += 1
          w = word
          return nil unless w && GENERIC_CAPS.includes?(w)
          @i += w.size
          return "##{w}"
        end
        w = word
        return nil unless w && CAP_WORDS.includes?(w)
        @i += w.size
        w
      end

      private def parse_atom : TypeNode?
        c = @s[@i]?
        return nil unless c
        return parse_group if c == '('
        return parse_lambda if c == '{'
        w = word
        return nil unless w
        if w == "this"
          @i += 4
          return NamedType.new(0, 0, "this")
        end
        if CAP_WORDS.includes?(w) && @s[@i + w.size]? == '-'
          @i += w.size
          return CapType.new(0, 0, w)
        end
        return nil unless w[0].ascii_uppercase?
        @i += w.size
        if @s[@i]? == '.' && (n = (@i += 1; word))
          @i += n.size
          w = n
        end
        args = parse_type_args
        return nil unless args
        with_cap(NamedType.new(0, 0, w, args))
      end

      # `(A | B)`, `(A & B)`, `(A, B)` or a parenthesised single type.
      private def parse_group : TypeNode?
        @i += 1
        skip_space
        first = parse_type
        return nil unless first
        skip_space
        members = [first] of TypeNode
        sep = @s[@i]?
        case sep
        when '|', '&', ','
          while @s[@i]? == sep
            @i += 1
            skip_space
            m = parse_type
            return nil unless m
            members << m
            skip_space
          end
        end
        return nil unless @s[@i]? == ')'
        @i += 1
        node = case sep
               when '|' then UnionType.new(0, 0, members)
               when '&' then IsectType.new(0, 0, members)
               when ',' then TupleType.new(0, 0, members)
               else          first
               end
        with_cap(node)
      end

      # Optional `[A, B]` type arguments; nil when they are malformed.
      private def parse_type_args : Array(TypeNode)?
        args = [] of TypeNode
        return args unless @s[@i]? == '['
        @i += 1
        loop do
          skip_space
          a = parse_type
          return nil unless a
          args << a
          skip_space
          if @s[@i]? == ','
            @i += 1
          elsif @s[@i]? == ']'
            @i += 1
            return args
          else
            return nil
          end
        end
      end

      private def parse_lambda : TypeNode?
        @i += 1
        return nil unless @s[@i]? == '('
        @i += 1
        params = [] of TypeNode
        skip_space
        until @s[@i]? == ')'
          p = parse_type
          return nil unless p
          params << p
          skip_space
          if @s[@i]? == ','
            @i += 1
            skip_space
          elsif @s[@i]? != ')'
            return nil
          end
        end
        @i += 1
        ret = nil
        if peek?(": ")
          @i += 2
          ret = parse_type
          return nil unless ret
        end
        partial = false
        skip_space
        if @s[@i]? == '?'
          partial = true
          @i += 1
        end
        return nil unless @s[@i]? == '}'
        @i += 1
        node = ProcType.new(0, 0, params, ret, nil, nil, partial)
        with_cap(node)
      end

      # Reads an optional capability and ephemeral/alias marker after a type.
      private def with_cap(node : TypeNode) : TypeNode
        save = @i
        c = nil
        if @s[@i]? == ' '
          skip_space
          c = cap
          @i = save if c.nil?
        end
        eph = nil
        if (ch = @s[@i]?) && (ch == '^' || ch == '!')
          eph = ch.to_s
          @i += 1
        end
        return node if c.nil? && eph.nil?
        case node
        when NamedType
          node.cap = c
          node.eph = eph
          node
        when ProcType
          node.cap = c
          node.eph = eph
          node
        else
          CappedGroup.new(0, 0, node, c, eph)
        end
      end
    end

    # A parenthesised group followed by a capability, e.g. `(A | B) val`.
    class CappedGroup < TypeNode
      property inner : TypeNode
      property cap : String?
      property eph : String?

      def initialize(line, col, @inner, @cap, @eph)
        super(line, col)
      end
    end

    def self.parse(text : String) : TypeNode?
      p = PonyParser.new(text.chars)
      node = p.parse_type
      node && p.i == text.size ? node : nil
    end

    # --- Pony -> Sparkle -----------------------------------------------------

    def self.to_sparkle(t : TypeNode, ctx : Int32 = 0) : String
      case t
      when NamedType
        named_to_sparkle(t)
      when CapType
        sparkle_cap(t.cap)
      when UnionType
        union_to_sparkle(t, ctx)
      when IsectType
        isect_to_sparkle(t, ctx)
      when TupleType
        "{" + t.types.map { |member| to_sparkle(member) }.join(", ") + "}"
      when ArrowType
        "#{to_sparkle(t.left, 2)}->#{to_sparkle(t.right, 2)}"
      when ProcType
        proc_to_sparkle(t)
      when CappedGroup
        capped_to_sparkle(t)
      else
        raise "unknown type node"
      end
    end

    private def self.isect_to_sparkle(t : IsectType, ctx : Int32) : String
      body = t.types.map { |member| to_sparkle(member, 2) }.join(" & ")
      ctx >= 2 ? "(#{body})" : body
    end

    private def self.capped_to_sparkle(t : CappedGroup) : String
      cap = t.cap
      prefix = cap ? "#{sparkle_cap(cap)}#{t.eph} " : ""
      "#{prefix}#{to_sparkle(t.inner, 2)}#{t.cap.nil? ? t.eph : nil}"
    end

    private def self.named_to_sparkle(t : NamedType) : String
      name = TO_SPARKLE[t.name]? || t.name
      if t.name == "Any" && t.args.empty? && (cap = t.cap)
        return "#{sparkle_cap(cap)}#{t.eph}"
      end
      String.build do |buffer|
        if cap = t.cap
          buffer << sparkle_cap(cap) << t.eph << ' '
        end
        buffer << name
        buffer << '(' << t.args.map { |arg| to_sparkle(arg) }.join(", ") << ')' unless t.args.empty?
        buffer << t.eph if t.cap.nil? && t.eph
      end
    end

    private def self.union_to_sparkle(t : UnionType, ctx : Int32) : String
      rest = t.types.reject { |member| member.is_a?(NamedType) && member.name == "None" && member.args.empty? }
      if rest.size < t.types.size
        inner = rest.size == 1 ? to_sparkle(rest[0], 2) : "(" + rest.map { |member| to_sparkle(member, 1) }.join(" | ") + ")"
        inner = "(#{inner})" if rest.size == 1 && (rest[0].is_a?(UnionType) || rest[0].is_a?(IsectType))
        return inner + "?"
      end
      body = t.types.map { |member| to_sparkle(member, 1) }.join(" | ")
      ctx >= 1 ? "(#{body})" : body
    end

    private def self.proc_to_sparkle(t : ProcType) : String
      args = t.params.map { |param| to_sparkle(param) }
      ret = t.ret
      args << (ret ? to_sparkle(ret) : "Nil")
      cap = t.cap
      prefix = cap ? "#{sparkle_cap(cap)}#{t.eph} " : ""
      "#{prefix}Proc(#{args.join(", ")})#{t.cap.nil? ? t.eph : nil}"
    end

    private def self.arrow_word?(chars : Array(Char), i : Int32) : Bool
      return false unless chars[i].ascii_lowercase?
      %w(this iso trn ref val box tag).any? do |word|
        word.each_char.with_index.all? { |char, k| chars[i + k]? == char } && chars[i + word.size]? == '-' && chars[i + word.size + 1]? == '>'
      end
    end

    private def self.type_start?(chars : Array(Char), i : Int32, char : Char, prev : Char) : Bool
      return false if prev.ascii_alphanumeric? || prev == '_' || prev == '.'
      char.ascii_uppercase? || char == '(' || char == '{' || arrow_word?(chars, i)
    end

    # Re-prints every Pony type expression found in `text` in Sparkle syntax.
    def self.rewrite(text : String) : String
      chars = text.chars
      out = String::Builder.new
      i = 0
      while i < chars.size
        c = chars[i]
        prev = i > 0 ? chars[i - 1] : ' '
        if type_start?(chars, i, c, prev)
          p = PonyParser.new(chars, i)
          node = p.parse_type
          if node
            original = chars[i...p.i].join
            printed = to_sparkle(node)
            if printed != original
              out << printed
              i = p.i
              next
            end
          end
        end
        out << c
        i += 1
      end
      out.to_s
    end
  end
end
