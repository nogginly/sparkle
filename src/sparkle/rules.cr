require "./ast"
require "./token"

module Sparkle
  # The translation rules that depend only on names and declarations, used by
  # the lowerer, the driver and the diagnostics.
  module Rules
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
    NON_VALUE_ASSIGN = "the value of an index, setter or field assignment cannot be used; assign, then read"
    REF_BY_DEFAULT   = Set{"[]=", "<<"}
    LOOP_METHODS     = Set{"each", "each_with_index", "times"}

    # Each enum predicate name (`red?`) and the members that have it, as
    # their Pony and Sparkle names (`{"LightRed", "Light::Red"}`).
    alias Predicates = Hash(String, Array({String, String}))

    # Returns, per Pony method name, the parameters that are primed: those
    # named like a method of their type, which Pony forbids.
    def self.primed_params(programs : Array(Program)) : Hash(String, Set(String))
      table = Hash(String, Set(String)).new
      programs.each do |program|
        program.items.each do |decl|
          next unless decl.is_a?(TypeDecl)
          names = decl.methods.map { |method| pony_method_name(method.name, method.self_recv) }.to_set
          decl.methods.each do |method|
            method.params.each do |param|
              n = pony_ident(param.name)
              (table[pony_method_name(method.name, method.self_recv)] ||= Set(String).new).add(n) if names.includes?(n)
            end
          end
        end
      end
      table
    end

    # Maps each Pony enum member name to its Sparkle spelling (`ColourRed` to `Colour::Red`).
    def self.enum_names(programs : Array(Program)) : Hash(String, String)
      names = Hash(String, String).new
      programs.each do |program|
        program.items.each do |decl|
          next unless decl.is_a?(EnumDecl)
          decl.members.each { |member| names["#{decl.name}#{member.name}"] = "#{decl.name}::#{member.name}" }
        end
      end
      names
    end

    # The predicate of an enum member: `DarkGreen` gives `dark_green?`.
    def self.predicate(member : String) : String
      "#{member.gsub(/(?<=.)[A-Z]/) { |capital| "_#{capital}" }.downcase}?"
    end

    # The predicates of the enums in `programs`, each with the members that have it.
    def self.enum_predicates(programs : Array(Program)) : Predicates
      table = Predicates.new
      programs.each do |program|
        program.items.each do |decl|
          next unless decl.is_a?(EnumDecl)
          decl.members.each do |member|
            (table[predicate(member.name)] ||= [] of {String, String}) << {"#{decl.name}#{member.name}", "#{decl.name}::#{member.name}"}
          end
        end
      end
      table
    end

    # The Pony name of the one enum member whose predicate the pattern names;
    # raises a `ParseError` at the pattern when there is not exactly one.
    def self.resolve_predicate(p : PredicatePattern, table : Predicates) : String
      unless p.name.ends_with?('?')
        raise ParseError.new("only enum predicates such as `.red?` can be patterns", p.line, p.col)
      end
      hits = table[p.name]? || raise ParseError.new("no enum member has the predicate `.#{p.name}`", p.line, p.col)
      return hits.first[0] if hits.size == 1
      raise ParseError.new("`.#{p.name}` names a member of several enums (#{hits.join(", ", &.[1])}); write the member instead", p.line, p.col)
    end

    # A name Pony reserves gets a trailing underscore.
    def self.pony_ident(name : String) : String
      PONY_RESERVED.includes?(name) ? "#{name}_" : name
    end

    # The Pony name of a method: operators spelled out, `?` as `is_`, `!`
    # dropped, `=` as `set_`, and `new` as `create` for a constructor.
    def self.pony_method_name(name : String, constructor : Bool) : String
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

    # Classes without a constructor get an explicit `create`, so instances are
    # `ref` (Pony infers `iso` for the implicit one, which cannot be aliased).
    def self.implicit_constructor?(d : TypeDecl) : Bool
      (d.kind == "class" || d.kind == "struct") && d.methods.none?(&.self_recv) && d.fields.all?(&.init)
    end

    # Setters, `[]=` and `<<` change their receiver, so they are `ref` unless
    # the method says otherwise.
    def self.mutating_name?(name : String) : Bool
      REF_BY_DEFAULT.includes?(name) || (name.ends_with?('=') && !%w[== != <= >=].includes?(name))
    end

    # Whether `d`'s methods are inline-only: a `module`, or a class that
    # reopens a Pony type.
    def self.inline_only?(d : TypeDecl) : Bool
      d.kind == "module" || d.reopens
    end

    # Whether `e` needs no parentheses as an operand or receiver.
    def self.atomic?(e : Expr) : Bool
      case e
      when Ident, IVarRef, SelfRef, IntLit, FloatLit, CharLit, BoolLit, NilLit, TypeRef, EnumRef,
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
  end
end
