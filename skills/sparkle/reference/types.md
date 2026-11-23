# Types

## Built-in types

```crystal
small : UInt8 = 200
wide = small.u32 + 100
env.out.print("#{wide} #{small.f64}")
```

```text
300 200
```

| Type | Notes |
|---|---|
| `Int8` `Int16` `Int32` `Int64` `Int128` | signed |
| `UInt8` … `UInt128` | unsigned |
| `Float32` `Float64` | |
| `Bool` | `true`, `false` |
| `String` | immutable text |
| `Nil` | the type of `nil` |
| `Array(T)` | growable array |

`ILong`, `ULong`, `ISize` and `USize` also exist. `USize` is what `size` returns and what an index is.

Pony's short names (`U8`, `I32`, `F64`) are accepted too. Every other Pony standard library type is usable by its own name, with Crystal's `(…)` for type arguments.

## Converting numbers

Numbers never convert on their own. A conversion is a method named after the target: `u8 u16 u32 u64 u128 usize i8 i16 i32 i64 i128 isize f32 f64`.

```crystal
n = 300_u32
env.out.print("#{n.u8} #{n.f64 / 8}")
```

```text
44 37.5
```

A conversion to a narrower type truncates; it does not fail.

## Unions and `?`

```crystal
alias Id = UInt32 | String

class Show
  def describe(x : Id) : String
    case x
    when n : UInt32 then "number #{n}"
    when s : String then "text #{s}"
    end
  end
end

actor Main
  def self.new(env : Env)
    show = Show.new
    env.out.print(show.describe(5))
    env.out.print(show.describe("hi"))
  end
end
```

```text
number 5
text hi
```

- `A | B` takes either. Take it apart with `case` and `when name : Type`, see [control-flow](control-flow.md).
- `T?` is `T | Nil`. `x.nil?` tests it. Write the capability first: `val String?` is `(val String) | Nil`.
- A `case` that covers every member of a union has no `else`; adding one is an error.

```crystal
primitive Names
  def first(xs : Array(String)) : String?
    begin
      xs[0]!
    rescue
      nil
    end
  end
end

actor Main
  def self.new(env : Env)
    missing = Names.first([] of String)
    present = Names.first(["ada"])
    env.out.print("#{missing.nil?} #{present.nil?}")
  end
end
```

```text
true false
```

`x.as!(T)` narrows to `T`, and can fail, so the method that calls it is partial (see [errors](errors.md)).

## Tuples

```crystal
t = {1_u8, "a"}
env.out.print("#{t._1} #{t._2}")
```

```text
1 a
```

A tuple is read with `_1`, `_2`, and so on, and its type is written `{UInt8, String}`. A tuple pattern in `case` is in [control-flow](control-flow.md).

## Other type forms

| Form | Means |
|---|---|
| `A & B` | both: an object that is an `A` and a `B` |
| `Proc(A, B)` | a function from `A` to `B`; the last type is the result, `Nil` for none |
| `this->A`, `box->A` | `A` as seen through the receiver, or through a `box` |

A lambda is passed where an `interface` with an `apply` method is expected; see [blocks](blocks.md).

## Aliases

`alias Names = Array(String)` gives a type another name. `Id` above is one.

## Generics

```crystal
class Box(A : val)
  @value : A

  def self.new(value : A)
    @value = value
  end

  def get : A = @value
end

actor Main
  def self.new(env : Env)
    box = Box(String).new("boxed")
    env.out.print(box.get)
  end
end
```

```text
boxed
```

- `class Box(A)` has an unconstrained parameter. `Box(A : val)` demands a `val` argument; `Box(A : val Stringable)` also a type bound. See [capabilities](capabilities.md).
- Type arguments are always written out at a constructor: `Box(String).new(…)`.
- Generic methods are not supported; only types are generic.

## Type inference

Locals take the type of their first value. A number with nothing else to give it a type is an `Int32`, or a `Float64` if it has a point, as in Crystal: `n = 5`, `[1, 2]`, `7.string`, `"#{1 + 2}"`. Where the context has a type, the number takes it: `small : UInt8 = 1`, `f(1)`. A method's parameters and return type are written out; a return type may be left off when the method returns nothing.

```crystal
n = 5
half = n / 2
ratio = 2.5
evens = [2, 4, 6]
env.out.print("#{half} #{ratio} #{evens.size} #{1 + 2}")
```

```text
2 2.5 3 3
```
