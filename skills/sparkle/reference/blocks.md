# Blocks

A block follows a call as `do |x| … end` or `{ |x| … }`. Three method names make it a loop; any other name makes it a lambda.

## `each`

```crystal
names = ["ada", "grace"]
names.each do |name|
  env.out.print("hello, #{name}")
end
```

```text
hello, ada
hello, grace
```

`each` runs the block once per element. It works on anything with a `values()` method: `Array`, `String`, `Range`, and the collections in Pony's `collections` package.

## `each_with_index`

```crystal
names = ["ada", "grace"]
names.each_with_index do |name, i|
  env.out.print("#{i}: #{name}")
end
```

```text
0: ada
1: grace
```

The element comes first, then its index, a `USize`.

## `times` and ranges

```crystal
total : USize = 0
4.times do |i|
  total += i
end
(1..3).each do |n|
  total += n
end
env.out.print("#{total}")
```

```text
12
```

- `n.times` counts from 0 to `n - 1`. `n` must be a `USize`, so write `count : USize = 4`, or call `n.usize`.
- `(a..b).each` includes `b`; `(a...b).each` stops before it. The elements are `USize`.

## Loop bodies

The block is a real loop body, so `break` and `next` work, and the block may assign to variables declared outside it.

```crystal
found = ""
["ada", "grace", "edsger"].each do |name|
  next if name.size < 4
  found = name
  break
end
env.out.print(found)
```

```text
grace
```

A variable first assigned inside the block exists only there, as in any block. Declare it before the loop.

## Lambdas

Any other block is a lambda, passed as the call's last argument. The callee takes an object with an `apply` method, usually an `interface`:

```crystal
interface Op
  abstract def apply(x : UInt32) : UInt32
end

primitive Run
  def twice(x : UInt32, f : val Op) : UInt32 = f(f(x))
end

actor Main
  def self.new(env : Env)
    five : UInt32 = 5
    doubled = Run.twice(five) { |x| x * 2 }
    env.out.print("#{doubled}")
  end
end
```

```text
20
```

- The parameter types come from the interface, so the block names them only.
- `do |x| … end` and `{ |x| … }` are the same.
- `&.name` is short for `{ |x| x.name }`: `Run.measure("text", &.size)`.
- A lambda can read the locals and parameters of the method around it: `{ |x| x + step }`.

There is no `yield`, so a method that would yield in Crystal takes a lambda this way.
