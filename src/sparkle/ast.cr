require "./token"

module Sparkle
  CAPABILITIES = %w[iso trn ref val box tag]
  GENERIC_CAPS = %w[read send share alias any]
  ALL_CAPS     = CAPABILITIES + GENERIC_CAPS

  # Base of every AST node; `line` and `col` are 1-based positions in the
  # Sparkle source.
  abstract class Node
    property line : Int32
    property col : Int32

    def initialize(@line, @col)
    end
  end

  macro node(name, parent, *fields)
    class {{ name }} < {{ parent }}
      {% for f in fields %}
        property {{ f.var }} : {{ f.type }}{% if !f.value.is_a?(Nop) %} = {{ f.value }}{% end %}
      {% end %}

      def initialize(line : Int32, col : Int32{% for f in fields %}, @{{ f.var }} : {{ f.type }}{% if !f.value.is_a?(Nop) %} = {{ f.value }}{% end %}{% end %})
        super(line, col)
      end

      def_clone
    end
  end

  abstract class TypeNode < Node
  end

  # `cap` is the capability written before the name (Sparkle) or after it
  # (Pony); `eph` is "^" or "!".
  node NamedType, TypeNode, name : String, args : Array(TypeNode) = [] of TypeNode, cap : String? = nil, eph : String? = nil
  node CapType, TypeNode, cap : String
  node UnionType, TypeNode, types : Array(TypeNode)
  node IsectType, TypeNode, types : Array(TypeNode)
  node TupleType, TypeNode, types : Array(TypeNode)
  node ArrowType, TypeNode, left : TypeNode, right : TypeNode
  node ProcType, TypeNode, params : Array(TypeNode), ret : TypeNode?, cap : String? = nil, eph : String? = nil, partial : Bool = false

  abstract class Expr < Node
  end

  node Param, Node, name : String, type : TypeNode?, default : Expr?

  node IntLit, Expr, text : String, suffix : String?
  node FloatLit, Expr, text : String, suffix : String?
  node StrLit, Expr, parts : Array(String | Expr)
  node CharLit, Expr, text : String
  node BoolLit, Expr, value : Bool
  node NilLit, Expr
  node SelfRef, Expr
  node Ident, Expr, name : String
  node IVarRef, Expr, name : String
  node TypeRef, Expr, type : TypeNode
  node Paren, Expr, expr : Expr
  node NamedArg, Node, name : String, value : Expr
  node Lambda, Expr, params : Array(Param), body : Array(Expr), brace : Bool = false
  node AmpMethod, Expr, name : String
  node Call, Expr, recv : Expr?, name : String, args : Array(Expr), named : Array(NamedArg), block : Lambda?, parens : Bool, name_line : Int32, name_col : Int32, post : Bool = false
  node FieldRead, Expr, recv : Expr, name : String
  node Index, Expr, recv : Expr, args : Array(Expr), bang : Bool
  node Assign, Expr, target : Expr, value : Expr, type : TypeNode?
  node OpAssign, Expr, target : Expr, op : String, value : Expr
  node Binary, Expr, op : String, left : Expr, right : Expr
  node Unary, Expr, op : String, operand : Expr
  node Ternary, Expr, cond : Expr, then_ : Expr, else_ : Expr
  node If, Expr, cond : Expr, then_ : Array(Expr), else_ : Array(Expr)?, negate : Bool = false, is_elsif : Bool = false, modifier : Bool = false
  node While, Expr, cond : Expr, body : Array(Expr), inverted : Bool = false
  node TypePattern, Expr, name : String, type : TypeNode
  node PredicatePattern, Expr, name : String
  node TuplePattern, Expr, items : Array(Expr)
  node When, Node, patterns : Array(Expr), body : Array(Expr)
  node Case, Expr, subject : Expr, whens : Array(When), else_ : Array(Expr)?, exhaustive : Bool = false
  node Begin, Expr, body : Array(Expr), rescue_body : Array(Expr)?, ensure_body : Array(Expr)?
  node Raise, Expr
  # `yield a, b` in a yielding method; see `Inliner`.
  node Yield, Expr, args : Array(Expr)
  # Made by the `Inliner`, never parsed: statements whose last is the value,
  # and statements run once, in which `next` ends the run.
  node Sequence, Expr, body : Array(Expr)
  node RunOnce, Expr, body : Array(Expr)
  node Return, Expr, value : Expr?
  node Break, Expr
  node Next, Expr
  node Consume, Expr, expr : Expr
  node Recover, Expr, cap : String?, body : Array(Expr)
  node ArrayLit, Expr, elems : Array(Expr), of_type : TypeNode?
  node TupleLit, Expr, items : Array(Expr)
  node RangeLit, Expr, from : Expr, to : Expr, exclusive : Bool
  node AsCast, Expr, expr : Expr, type : TypeNode
  node EnumRef, Expr, enum_name : String, member : String
  # `old(expr)` and `result`, only inside a `guarantees` clause.
  node Old, Expr, expr : Expr
  node ResultRef, Expr

  # Where a capability was written, for `sparkle caps`.
  record CapUse, position : String, cap : String, line : Int32, col : Int32

  node Field, Node, name : String, type : TypeNode?, init : Expr?

  # One condition of an `expects`, `guarantees` or `maintains` clause, with
  # its source text; `kind` is the clause's word.
  node Clause, Node, kind : String, cond : Expr, text : String

  # `kind` is "def", "be" (a message handler, written `on`) or "abstract"; `self_recv` marks `def self.name`.
  node Method, Node, kind : String, cap : String?, self_recv : Bool, name : String, params : Array(Param), ret : TypeNode?, body : Array(Expr)?, name_line : Int32, name_col : Int32, expects : Array(Clause) = [] of Clause, guarantees : Array(Clause) = [] of Clause

  node TypeParam, Node, name : String, constraint : TypeNode?
  node TypeDecl, Node, kind : String, cap : String?, name : String, tparams : Array(TypeParam), includes : Array(TypeNode), fields : Array(Field), methods : Array(Method), maintains : Array(Clause) = [] of Clause
  node AliasDecl, Node, name : String, type : TypeNode
  node RequireDecl, Node, path : String

  # `value` is the member's resolved integer value.
  node EnumMember, Node, name : String, value : Int64
  node EnumDecl, Node, name : String, members : Array(EnumMember)

  # The primitive `_SpkContract` and the C functions it calls, which the
  # checks made by `Contracts` need once per package.
  node ContractSupport, Node

  class Program
    getter items : Array(Node)
    getter cap_uses : Array(CapUse)

    def initialize(@items, @cap_uses)
    end
  end
end
