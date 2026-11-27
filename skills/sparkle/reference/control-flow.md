# Control flow

## `if` and `unless`

```crystal
n = 7
if n < 5
  env.out <~ print("small")
elsif n < 10
  env.out <~ print("medium")
else
  env.out <~ print("large")
end
```

```text
medium
```

- `unless c … else … end` is `if` with the test reversed.
- `stmt if c` and `stmt unless c` guard one statement.
- `c ? a : b` is the short form of `if c then a else b end`.
- `if` is an expression: its value is the value of the branch taken.

```crystal
n = 7
size = if n < 5
  "small"
else
  "large"
end
env.out <~ print(size)
env.out <~ print("not above 8") unless n > 8
```

```text
large
not above 8
```

## Loops

```crystal
ticks : USize = 0
while ticks < 5
  ticks += 1
  next if ticks == 2
  env.out <~ print("tick #{ticks}")
  break if ticks >= 4
end
```

```text
tick 1
tick 3
tick 4
```

| Form | Runs |
|---|---|
| `while c … end` | while `c` is true |
| `until c … end` | until `c` is true |
| `loop do … end` | until `break` |

`break` leaves the loop, `next` skips to the next turn, `return x` leaves the method.

## Counting

```crystal
3.times do |i|
  env.out <~ print("i = #{i}")
end
(1..3).each do |i|
  env.out <~ print("n = #{i}")
end
```

```text
i = 0
i = 1
i = 2
n = 1
n = 2
n = 3
```

`a..b` includes `b` and `a...b` stops before it. Both count in `USize`, as does `times`, so the variable is a `USize`. Looping over a collection is in [blocks](blocks.md).

## `case`

```crystal
primitive Grade
  def label(n : UInt32) : String
    case n
    when 0 then "zero"
    when 1, 2, 3 then "few"
    else "many"
    end
  end
end

actor Main
  def self.new(env : Env)
    env.out <~ print(Grade.label(2))
    env.out <~ print(Grade.label(9))
  end
end
```

```text
few
many
```

`case` is an expression. Each `when` takes values, separated by commas, compared with `==`. `then` puts the body on the same line.

### Matching types

```crystal
alias Id = UInt32 | String

primitive Show
  def id(x : Id) : String
    case x
    when n : UInt32 then "number #{n}"
    when s : String then "text #{s}"
    end
  end
end
```

`when name : Type` matches by type and binds the value under that type inside the branch. A `case` over a union that names every member has no `else`; Pony reports an `else` there as unreachable.

### Matching tuples

```crystal
primitive FizzBuzz
  def label(i : USize) : String
    case {i % 3, i % 5}
    when {0, 0} then "FizzBuzz"
    when {0, _} then "Fizz"
    when {_, 0} then "Buzz"
    else "#{i}"
    end
  end
end

actor Main
  def self.new(env : Env)
    env.out <~ print(FizzBuzz.label(9))
    env.out <~ print(FizzBuzz.label(10))
    env.out <~ print(FizzBuzz.label(15))
  end
end
```

```text
Fizz
Buzz
FizzBuzz
```

`_` matches anything. A name in a tuple pattern compares with that variable; to bind, write the type: `when {a : String, b : UInt32}`.

For enums, `case x in` checks every member is handled: see [enums](enums.md).
