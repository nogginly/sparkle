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
        String.build do |s|
          s << (TO_PONY[t.name]? || t.name)
          unless t.args.empty?
            s << '[' << t.args.map { |a| to_pony(a) }.join(", ") << ']'
          end
          if cap = t.cap
            s << ' ' << pony_cap(cap)
          end
          s << t.eph if t.eph
        end
      when CapType
        "Any #{pony_cap(t.cap)}"
      when UnionType
        "(" + t.types.map { |a| to_pony(a) }.join(" | ") + ")"
      when IsectType
        "(" + t.types.map { |a| to_pony(a) }.join(" & ") + ")"
      when TupleType
        "(" + t.types.map { |a| to_pony(a) }.join(", ") + ")"
      when ArrowType
        left = t.left.is_a?(CapType) ? pony_cap(t.left.as(CapType).cap) : to_pony(t.left)
        "#{left}->#{to_pony(t.right)}"
      when ProcType
        String.build do |s|
          s << "{(" << t.params.map { |a| to_pony(a) }.join(", ") << ')'
          ret = t.ret
          unless ret.nil? || (ret.is_a?(NamedType) && ret.name == "Nil" && ret.args.empty?)
            s << ": " << to_pony(ret)
          end
          s << '?' if t.partial
          s << '}'
          s << ' ' << pony_cap(t.cap.not_nil!) if t.cap
          s << t.eph if t.eph
        end
      else
        raise "unknown type node"
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
        str.each_char.with_index.all? { |c, k| @s[@i + k]? == c }
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
        if c == '('
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
          return with_cap(node)
        elsif c == '{'
          return parse_lambda
        end
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
        args = [] of TypeNode
        if @s[@i]? == '['
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
              break
            else
              return nil
            end
          end
        end
        with_cap(NamedType.new(0, 0, w, args))
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
        name = TO_SPARKLE[t.name]? || t.name
        if t.name == "Any" && t.args.empty? && t.cap
          return "#{sparkle_cap(t.cap.not_nil!)}#{t.eph}"
        end
        String.build do |s|
          if cap = t.cap
            s << sparkle_cap(cap) << t.eph << ' '
          end
          s << name
          s << '(' << t.args.map { |a| to_sparkle(a) }.join(", ") << ')' unless t.args.empty?
          s << t.eph if t.cap.nil? && t.eph
        end
      when CapType
        sparkle_cap(t.cap)
      when UnionType
        rest = t.types.reject { |m| m.is_a?(NamedType) && m.name == "None" && m.args.empty? }
        if rest.size < t.types.size
          inner = rest.size == 1 ? to_sparkle(rest[0], 2) : "(" + rest.map { |a| to_sparkle(a, 1) }.join(" | ") + ")"
          inner = "(#{inner})" if rest.size == 1 && (rest[0].is_a?(UnionType) || rest[0].is_a?(IsectType))
          return inner + "?"
        end
        body = t.types.map { |a| to_sparkle(a, 1) }.join(" | ")
        ctx >= 1 ? "(#{body})" : body
      when IsectType
        body = t.types.map { |a| to_sparkle(a, 2) }.join(" & ")
        ctx >= 2 ? "(#{body})" : body
      when TupleType
        "{" + t.types.map { |a| to_sparkle(a) }.join(", ") + "}"
      when ArrowType
        "#{to_sparkle(t.left, 2)}->#{to_sparkle(t.right, 2)}"
      when ProcType
        args = t.params.map { |a| to_sparkle(a) }
        args << (t.ret ? to_sparkle(t.ret.not_nil!) : "Nil")
        prefix = t.cap ? "#{sparkle_cap(t.cap.not_nil!)}#{t.eph} " : ""
        "#{prefix}Proc(#{args.join(", ")})#{t.cap.nil? ? t.eph : nil}"
      when CappedGroup
        prefix = t.cap ? "#{sparkle_cap(t.cap.not_nil!)}#{t.eph} " : ""
        "#{prefix}#{to_sparkle(t.inner, 2)}#{t.cap.nil? ? t.eph : nil}"
      else
        raise "unknown type node"
      end
    end

    private def self.arrow_word?(chars : Array(Char), i : Int32) : Bool
      return false unless chars[i].ascii_lowercase?
      %w(this iso trn ref val box tag).any? do |w|
        w.each_char.with_index.all? { |ch, k| chars[i + k]? == ch } && chars[i + w.size]? == '-' && chars[i + w.size + 1]? == '>'
      end
    end

    # Re-prints every Pony type expression found in `text` in Sparkle syntax.
    def self.rewrite(text : String) : String
      chars = text.chars
      out = String::Builder.new
      i = 0
      while i < chars.size
        c = chars[i]
        prev = i > 0 ? chars[i - 1] : ' '
        candidate = (c.ascii_uppercase? || c == '(' || c == '{' || arrow_word?(chars, i)) &&
                    !(prev.ascii_alphanumeric? || prev == '_' || prev == '.')
        if candidate
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
