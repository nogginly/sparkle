# From Pony

Sparkle has Pony's semantics and its standard library. Only the spelling changes. `sparkle translate PATH` prints the Pony syntax tree a file becomes.

```crystal
class Counter
  @n : U64 = 0

  def ref incr : U64 = @n += 1
  def count : U64 = @n
end
```

```pony
class Counter
  var _n: U64 = 0

  fun ref incr(): U64 => (_n = _n + 1; _n)
  fun count(): U64 => _n
```

## Declarations

| Pony | Sparkle |
|---|---|
| `class Foo … end` | `class Foo … end` (also `actor`, `struct`, `primitive`, `trait`, `interface`) |
| `class val Foo` | `class val Foo` |
| `class Box[A: Any val]` | `class Box(A : val)` |
| `class Box[A: Stringable val]` | `class Box(A : val Stringable)` |
| `is Comparable[Foo]` | `include Comparable(Foo)` in the body |
| `type Name is (A \| B)` | `alias Name = A \| B` |
| `var _n: U64 = 0` | `@n : U64 = 0` |
| `new create(env: Env) =>` | `def self.new(env : Env)` |
| `new iso create() =>` | `def iso self.new` |
| `new from_pair(a: A) =>` | `def self.from_pair(a : A)` |
| `fun name(a: A): R =>` | `def name(a : A) : R` |
| `fun ref push(x: A) =>` | `def ref push(x : A)` |
| `fun name(): R => expr` | `def name : R = expr` |
| `be run(x: U32) =>` | `on run(x : U32)` |
| `w.run(1)`, a behaviour | `w <~ run(1)` |
| `fun first(): A ?` | `def first! : A` |
| `fun is_empty(): Bool` | `def empty? : Bool` |
| `fun ref set_name(v: A)` | `def name=(v : A)` |
| `fun add(o: T): T` | `def +(o : T) : T` |
| `fun name(): R` in a trait | `abstract def name : R` |

Every Sparkle declaration and body closes with `end`, and there is no `=>`.

## Names

| Pony | Sparkle |
|---|---|
| `_n` (field) | `@n` |
| `this` | `self` |
| `None` | `Nil` (or `nil` as a value) |
| `I32`, `U64`, `F64` | `Int32`, `UInt64`, `Float64`; the short names also work |
| `Array[String]` | `Array(String)` |
| `String val` | `val String` |
| `String iso^` | `iso^ String` |
| `(String \| None)` | `String?` |
| `(A \| B)`, `(A & B)` | `A \| B`, `A & B` |
| `Foo.create(a)` | `Foo.new(a)` |
| `x.foo()` | `x.foo` (or `x.foo()`) |
| `x.first()?` | `x.first!` |
| `x.is_empty()` | `x.empty?` |
| `f(where x = 1)` | `f(x: 1)` |
| `a(i)?` | `a[i]!` |
| `a.push(b)` | `a << b` |
| `(x as T)` | `x.as!(T)` |
| `x is None` | `x.nil?` |
| `ColourGreen` (an `enum` member) | `Colour::Green` |

A name that Pony reserves is renamed behind the scenes: a variable called `val` is `val_` in the generated code.

## Statements

| Pony | Sparkle |
|---|---|
| `var x = 1` | `x = 1`, then `x = 2` to assign |
| `var x: U8 = 1` | `x : UInt8 = 1` |
| `x = x + 1` | `x += 1` |
| `if c then … elseif d then … else … end` | `if c … elsif d … else … end` |
| `if not c then … end` | `unless c … end` |
| `while c do … end` | `while c … end` |
| `while true do … end` | `loop do … end` |
| `continue` | `next` |
| `for x in xs.values() do … end` | `xs.each do \|x\| … end` |
| `for (i, x) in xs.pairs() do … end` | `xs.each_with_index do \|x, i\| … end` |
| `for i in Range[USize](0, n) do … end` | `n.times do \|i\| … end` |
| `match x \| 1 => … \| let s: String => … end` | `case x when 1 … when s : String … end` |
| `match \exhaustive\ x` | `case x in` |
| `try … else … then … end` | `begin … rescue … ensure … end` |
| `error` | `raise` |
| `recover iso … end` | `recover iso do … end` |
| `consume x` | `consume x` |

## Assignment

Pony's `x = y` evaluates to the old value of `x`. Sparkle's evaluates to the new one, as in Crystal; `a = b = 7` sets both to 7.

## Strings

`"n = #{n}"` is `"n = " + n.string()`.

## Calling a field or a method

Pony distinguishes `x.field` from `x.method()`. Sparkle lets you write `x.name` for both, as in Crystal. When the type of `x` has a method `name`, it is called; when it has a field, the field is read. Write `x.@name` to force the field.

## Capabilities and types

Capabilities, `recover`, `consume`, `iso^` and `A!` mean what they mean in Pony. See [capabilities](capabilities.md).

## Lambdas and tuples

Lambda types are written `Proc(A, B)` for `{(A): B}`, and tuple types `{A, B}` for `(A, B)`. A lambda expression is a block: `{ |x| x * 2 }`.

What Pony has and Sparkle does not is in [limits](limits.md).
