# Limits

What Sparkle does not do, and what to write instead.

## Not supported

| Not supported | Instead |
|---|---|
| `return` with a value in a method that yields; `next` or `break` in a block whose call's value is used | Assign to a local in the block, and read it after the call; see [blocks](blocks.md) |
| Macros: `getter`, `property`, `record` | Write the methods |
| Hash and symbol literals | `Map` and `Set` from `require "collections"` |
| `puts "x"`: a call with arguments and no parentheses | `env.out <~ print("x")` |
| FFI | none |
| Qualified names: `Geometry::Point`, `use g = "geometry"` | Keep type names distinct across packages |
| `let` and `embed` fields | `@name : Type` |
| Generic methods | Make the type generic, or write one method per type |
| Reopening a type | Declare it once |
| Methods, flags or a base type inside an `enum` | Put the methods on a `primitive` |
| Destructuring: `(a, b) = pair` | Read `pair._1` and `pair._2` |
| Contract clauses on a method that yields, an abstract method or a `tag` method; `maintains` in a trait, interface or primitive | Check in the callers, or in a method that does not yield |

## Typeless translation

Sparkle translates before it knows types. These follow, each with its way out.

| Gap | Instead |
|---|---|
| `x = 0` is an `Int32`, so it will not compare with a `USize` | `x : USize = 0` |
| `'a'` has no type of its own | `c : UInt8 = 'a'` |
| `a << b` is always `a.push(b)` | For integer shifts use `a.shl(b)` |
| Ranges and `times` count in `USize` | Convert: `i.u32` |
| `x.name` is a field read unless the type has a method `name`; a chain `a.b.c` costs one type-check round per bare link | Parentheses force a call: `x.name()` |
| A bare `x.name` is decided once per place in the code, so generic code used with two types cannot read a field for one and call a method for the other | Write `x.name()` or `x.@name` |
| A named argument is matched to a renamed parameter by method name only: if two types define `f` and only one renames its parameter `x`, `f(x: 1)` is wrong for the other | Use distinct parameter names |
| `x.@name` reads the enclosing type's own field when it has an `@name`, so a type with `@out` cannot read `env.@out` | Write `env.out` |

## Assignment

| Gap | Instead |
|---|---|
| An index, setter or field write cannot be used as a value: `y = (a[0] = 1)` | Assign on one line, read on the next |
| `x = (y = consume z)` fails for an `iso` `z`: reading the assignment aliases it | `y = consume z`, then `consume y` |
| A variable first assigned inside an `if` or a loop exists only there | Assign it before the block |

## Order of evaluation

Sparkle evaluates left to right, as Crystal does: the receiver, then the arguments in order. One exception:

| Gap | Instead |
|---|---|
| A field receiver is read after the arguments: in `@items.push(swap_items)`, if `swap_items` reassigns `@items`, the new array gets the push | Read the field into a local first: `items = @items` |

## Syntax

| Gap | Instead |
|---|---|
| In a `case`, a name in a tuple pattern `{a, b}` compares against existing values | Bind with types: `{a : String, b : UInt32}` |
| A continuation line inside `(…)` may not start with an operator | End the line before with the operator |
| `def pop` and `def pop!` both become `pop`; `def empty?` and `def is_empty` both become `is_empty` | Do not define both |
