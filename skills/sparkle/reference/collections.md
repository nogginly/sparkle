# Collections

`Array` has Crystal's collection methods. They come from the library's prelude, so there is no `require`.

| Method | Means |
|---|---|
| `map { }` | a new array of the block's values |
| `select { }`, `reject { }` | the elements the block accepts, or rejects |
| `find { }` | the first element the block accepts, or `nil` |
| `any? { }`, `all? { }`, `none? { }` | whether some, every, or no element is accepted |
| `count { }` | how many elements the block accepts, a `USize` |
| `sum` | the elements added up |
| `reduce(initial) { \|acc, x\| … }` | folds the elements into one value, starting at `initial` |
| `includes?(value)` | whether an element `==` the value |
| `index(value)` | the position of the first equal element, a `USize`, or `nil` |
| `first?` | the first element, or `nil` when empty |
| `min?`, `max?` | the smallest or largest element, or `nil` when empty |
| `join(separator)` | each element's `string`, separated |
| `delete_at!(i)` | removes and returns the element at `i`; partial, fails past the end |

```crystal
xs = [3, 1, 4, 1, 5]
doubled = xs.map { |x| x * 2 }
big = xs.select { |x| x > 2 }
env.out <~ print(doubled.join(","))
env.out <~ print(big.join(","))
env.out <~ print("#{xs.sum} #{xs.count { |x| x == 1 }} #{xs.any? { |x| x > 4 }}")
```

```text
6,2,8,2,10
3,4,5
14 2 true
```

`reduce` passes the accumulator first, then the element:

```crystal
xs = [1, 2, 3]
env.out <~ print("#{xs.reduce(10) { |acc, x| acc + x }}")
```

```text
16
```

## Empty arrays

`min?`, `max?`, `first?`, `find` and `index` return `nil` when there is nothing to return. Test with `nil?`:

```crystal
empty = [] of Int32
env.out <~ print("#{empty.min?.nil?} #{[2, 1].min?.nil?}")
```

```text
true false
```

Crystal's raising `min` and `max` are not provided: a method that can fail ends in `!` in Sparkle.

## Pony's names

Pony's `Array` already has `find` and `delete`, with other meanings. Here `find { }` is Crystal's. For Pony's `find(value)`, which gives an index, call `index(value)`; for Pony's `delete(i)`, which removes at an index, call `delete_at!(i)`:

```crystal
xs = [10, 20, 30]
begin
  removed = xs.delete_at!(1)
  env.out <~ print("#{removed} #{xs.join(",")}")
  xs.delete_at!(5)
rescue
  env.out <~ print("past the end")
end
```

```text
20 10,30
past the end
```

## How they work

Every method is inlined: each call is replaced by a copy of the method's body, as for a method of yours that `yield`s (see [blocks](blocks.md)). Nothing is added to Pony's `Array`, and a method that is never called costs nothing.

The prelude declares them in Sparkle. `module Enumerable(A)` holds the methods, written with `each` and `yield`, and a type opts in with `include`:

```text
module Enumerable(A)
  def select(&block : A -> Bool) : Array(A)
    result = [] of A
    each do |x|
      result << x if yield x
    end
    result
  end
end

class Array(A)
  include Enumerable(A)
end
```

`A` is the receiver's element type. A method whose block makes a new type, as `map` does, names it with `forall B`.
