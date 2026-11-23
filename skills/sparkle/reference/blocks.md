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

## `yield`

A method of yours whose body has `yield` takes a block, as in Crystal. Each call is replaced by a copy of the method's body, so the block runs in the caller and can change its locals:

```crystal
class Bag
  @items : Array(UInt32)

  def self.new
    @items = [1_u32, 2_u32, 3_u32]
  end

  def each_item
    @items.each do |x|
      yield x
    end
  end
end

actor Main
  def self.new(env : Env)
    total : UInt32 = 0
    Bag.new.each_item do |v|
      total += v
    end
    env.out.print("#{total}")
  end
end
```

```text
6
```

- `yield a, b` passes two values; the block may name fewer.
- A method that yields may call another with a block, and may not reach itself.
- The method is picked by the receiver's type, so `each` on your type is yours, and `each` on an `Array` is a loop.
- `yield x` has a value, the block's last expression: `total += yield x`.
- In the block, `next` ends this run, `break` leaves the whole call, and `return` returns from your method, as in Crystal. A bare `return` in the yielding method ends the call.
- Not yet: `return` with a value in a yielding method, and `next` or `break` in a block whose call's value is used.
