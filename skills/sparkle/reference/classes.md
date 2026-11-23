# Classes

## `class`

```crystal
class Point
  @x : Int32
  @y : Int32

  def self.new(x : Int32, y : Int32)
    @x = x
    @y = y
  end

  def x : Int32 = @x
  def y : Int32 = @y
end

actor Main
  def self.new(env : Env)
    p = Point.new(3, 4)
    env.out.print("(#{p.x}, #{p.y})")
  end
end
```

```text
(3, 4)
```

| Declaration | Is |
|---|---|
| `class Foo` | objects with fields and methods; default capability `ref` |
| `struct Foo` | a class for passing to C code |
| `primitive Foo` | one value, no fields; call its methods on the name: `Foo.twice(21)` |
| `actor Foo` | see [actors](actors.md) |
| `trait Foo` | a named interface that types opt into with `include` |
| `interface Foo` | a trait that any type with the right methods satisfies |
| `enum Foo` | see [enums](enums.md) |

A declaration may carry a capability: `class val Point`. See [capabilities](capabilities.md).

## Fields

```crystal
class Counter
  @n : UInt64 = 0
  @name : String = "counter"

  def ref incr : UInt64 = @n += 1
  def count : UInt64 = @n
end
```

- A field is `@name : Type`, with an optional default. The type is required.
- Fields are private to the type. Reach one from outside through a method; `def count` may share a name with `@count`.
- A constructor must set every field that has no default.
- `o.@x` reads field `x` of another object of the same type, and never calls a method.

## Constructors

```crystal
class Pair
  @a : UInt32
  @b : UInt32

  def self.new(a : UInt32, b : UInt32)
    @a = a
    @b = b
  end

  def self.twin(n : UInt32)
    @a = n
    @b = n
  end
end
```

- `def self.new` is `Foo.new(…)`. Any other `def self.name` is a named constructor: `Pair.twin(3)`.
- A constructor's body assigns fields; it returns the new object.
- A class with no constructor and every field defaulted gets `Foo.new` with no arguments.
- `def iso self.new` or `def val self.new` makes the object `iso` or `val`.

## Methods

```crystal
class Stack
  @items : Array(String) = Array(String).new

  def ref push(item : String)
    @items << item
  end

  def size : USize = @items.size
  def empty? : Bool = @items.size == 0
end

actor Main
  def self.new(env : Env)
    s = Stack.new
    s.push("a")
    env.out.print("#{s.size} #{s.empty?}")
  end
end
```

```text
1 false
```

- `def name(args) : Type` with a body ending in `end`, or `def name : Type = expr` on one line.
- A method with no return type returns nothing.
- The last expression is the value; `return x` leaves early.
- A method may only read its fields. To change one, write `def ref`.
- `def name=(v)` is a setter, used as `x.name = v`. It is `ref` by default.
- `def first!` can fail; `def empty?` answers a question. See [errors](errors.md).
- Default argument values: `def greet(name : String = "you")`.
- A parameter may share a name with a method of its type; Sparkle renames it underneath.

## Operators

```crystal
class Score
  @points : UInt32

  def self.new(points : UInt32)
    @points = points
  end

  def points : UInt32 = @points
  def +(o : Score) : Score = Score.new(@points + o.points)
  def <(o : Score) : Bool = @points < o.points
end

actor Main
  def self.new(env : Env)
    total = Score.new(2) + Score.new(3)
    env.out.print("#{total.points} #{Score.new(1) < total}")
  end
end
```

```text
5 true
```

Definable: `+ - * / %`, `== != < <= > >=`, `<<`, `>>`, `[]`, `[]!`, `[]=`. `def <<` and `def []=` are `ref` by default. `a[i]!` calls `[]!`.

## `trait` and `interface`

```crystal
trait Shape
  abstract def area : UInt32

  def big? : Bool = area > 10
end

class Square
  include Shape
  @side : UInt32

  def self.new(side : UInt32)
    @side = side
  end

  def area : UInt32 = @side * @side
end

interface Named
  abstract def name : String
end
```

- `abstract def` has no body and no `end`.
- A trait's other methods are defaults. `include Shape` gives them to `Square`; several `include`s are allowed.
- A type satisfies an `interface` by having the methods, with no `include`.
- Write the trait or interface as the type of a parameter or array element: `[Square.new(2)] of Shape`.
