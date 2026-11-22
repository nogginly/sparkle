# From Crystal

Sparkle reads like Crystal, but it has no type inference across methods and no macros. This page lists what to unlearn.

| Crystal | Sparkle |
|---|---|
| `x = 0` is `Int32`, and mixes with other integers | `x = 0` is `Int32`, and mixes with nothing. Convert with `.u64`, `.usize`; or write `x : USize = 0` |
| `def foo(x)` infers its types | Every parameter has a type: `def foo(x : String)` |
| `def initialize(x)` and `Foo.new(x)` | `def self.new(x : T)` and `Foo.new(x)` |
| `getter name`, `property name`, `record` | Write the method: `def name : String = @name` |
| `yield` and `&block` | No `yield`. `each`, `each_with_index` and `times` are loops; any other block is a lambda the method takes as its last argument |
| `puts x`, `foo 1, 2` | Parentheses are required when there are arguments. Print with `env.out.print(s)` |
| `{"a" => 1}`, `:sym` | Not supported: no hashes, no symbols. `Map` and `Set` come from `use "collections"` |
| Reopening a class | Not supported |
| `Foo(T)` generic methods | Only types are generic, not methods |
| `Array(Int32)` | `Array(Int32)`, but `[1, 2]` needs `[1, 2] of Int32` |
| `raise "message"` | `raise` takes no value |
| `begin … rescue ex : Foo` | `begin … rescue … end`; no exception types or values |
| `case … when Foo` | Also `when n : Foo` to bind the value |
| Every object may be shared | Every reference has a capability, see below |
| Fibers and channels | Actors and `be` methods |

## Numbers

```crystal
ticks : USize = 0
limit = 3
limit_size = limit.usize
env.out.print("#{ticks < limit_size}")
```

```text
true
```

`ticks = 0` followed by `ticks < size` with a `USize` `size` fails: `val USize is not a subtype of val^ Int32`. `Array#size` and indexes are `USize`, so declare counters as `USize`.

## `x.name`

```crystal
class Person
  @name : String

  def self.new(name : String)
    @name = name
  end

  def name : String = @name
end

actor Main
  def self.new(env : Env)
    p = Person.new("ada")
    env.out.print("#{p.name} #{env.args.size}")
  end
end
```

```text
ada 1
```

`p.name` is a method; `env.args` is a field of `Env`. Sparkle uses whichever the type has, so you can write both the same way. `p.@name` always reads a field.

## `!` and `?`

`def first!` is a method that can fail, and the compiler forces the caller to handle it, see [errors](errors.md). In Crystal, `!` is only a naming habit. `def empty?` is an ordinary predicate, as in Crystal.

## Capabilities

```crystal
class Counter
  @n : UInt32 = 0

  def ref incr : UInt32 = @n += 1
  def count : UInt32 = @n
end

actor Main
  def self.new(env : Env)
    c = Counter.new
    c.incr
    env.out.print("#{c.count}")
  end
end
```

```text
1
```

A method changes its object only if it is `def ref`. Passing data to another actor needs `iso`, `val` or `tag`. See [capabilities](capabilities.md).

## Blocks

Crystal's `yield` is not available. `each`, `each_with_index` and `times` are real loops, and `break` and `next` work in them:

```crystal
3.times do |i|
  next if i == 1
  env.out.print("#{i}")
end
```

```text
0
2
```

The count of `times` is a `USize`. Any other block is a lambda, see [blocks](blocks.md).

## Strings and printing

`"#{x}"` works as in Crystal and calls `string` on the value. `env.out.print` takes a `String`, not any value, and adds the newline.

## Types that differ

| Crystal | Sparkle |
|---|---|
| `Int32`, `UInt8`, `Float64` | the same; `Int8` … `Int128` and `UInt8` … `UInt128` |
| `Nil` | `Nil`; `T?` is `T \| Nil` |
| `Tuple`, `{1, "a"}` | `{1, "a"}`, read with `_1` and `_2` |
| `Proc` | not supported yet |
| `Char` | none: `'a'` is an integer literal |
