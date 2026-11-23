---
name: sparkle
description: Write, read, build and debug Sparkle (.spk) programs. Sparkle is Crystal's syntax on Pony's reference capabilities and actors, compiled by the `sparkle` command. Use when a task involves .spk files, the sparkle CLI, or Sparkle code.
---

# Sparkle

Sparkle reads like Crystal and behaves like Pony: Pony's types, reference capabilities, actors and standard library, with Crystal's `def … end`, blocks and string interpolation. A program is a directory of `.spk` files (one package) with an `actor Main`.

```crystal
actor Main
  def self.new(env : Env)
    name = "world"
    env.out.print("Hello, #{name}!")
  end
end
```

```text
Hello, world!
```

## Commands

| Command | Does |
|---|---|
| `sparkle check PATH` | Type-check a file or directory, without generating code |
| `sparkle run PATH [-- args]` | Build a file or directory, then run it |
| `sparkle build PATH [-o DIR]` | Build into `.sparkle/bin/` (or `DIR`) |
| `sparkle translate PATH` | Print the Pony syntax tree it compiles, to see how code was read |

Errors are reported at `.spk` lines with types in Sparkle syntax. Fix the first error first. `check` is the fast way to see them; `run` also generates code.

## Rules that differ from Crystal

1. **Capabilities.** Every reference has one: `iso`, `trn`, `ref`, `val`, `box`, `tag`. Write it before the type: `val String`. A method can only read `self` unless declared `def ref`. See [capabilities](reference/capabilities.md).
2. **Constructors** are `def self.new`; call them as `Foo.new`. A class whose fields all have defaults gets one for free.
3. **Fields** are `@name : Type`, private, and need a type.
4. **`x.name`** is a field read or a method call, whichever `x`'s type has. `x.@name` always reads a field.
5. **`!` and `?`.** `def first!` can fail and must be called as `first!`. `def empty?` is a predicate.
6. **Numbers.** `x = 0` is an `Int32` and `x = 1.5` a `Float64`. Types never mix silently: convert with `n.usize`, or declare `i : USize = 0`.
7. **Blocks.** No `yield`. `each`, `each_with_index` and `times` are loops; any other block is a lambda. See [blocks](reference/blocks.md).
8. **Actors.** `be` methods run asynchronously and return nothing. Output order between actors is not fixed. See [actors](reference/actors.md).
9. **Not supported:** `yield`, macros (`getter`, `property`, `record`), hashes, symbols, calls without parentheses that take arguments (`puts x`). See [limits](reference/limits.md).

## Reference

Read the page for the feature at hand.

| Page | Covers |
|---|---|
| [getting-started](reference/getting-started.md) | Installing, packages, `Main`, `env`, printing |
| [syntax](reference/syntax.md) | Comments, literals, variables, operators, strings |
| [types](reference/types.md) | Built-in types, unions, `?`, tuples, aliases, generics, `Proc` |
| [capabilities](reference/capabilities.md) | `iso` … `tag`, `recover`, `consume`, defaults |
| [classes](reference/classes.md) | `class`, `struct`, `primitive`, `trait`, `interface`, fields, methods, operators |
| [actors](reference/actors.md) | Actors, behaviours, sending data |
| [control-flow](reference/control-flow.md) | `if`, `unless`, `while`, `until`, `loop`, `case` |
| [blocks](reference/blocks.md) | Loops over collections, lambdas, `&.name` |
| [enums](reference/enums.md) | `enum`, members, predicates, exhaustive `case … in` |
| [errors](reference/errors.md) | Partial methods (`!`), `raise`, `begin … rescue … ensure` |
| [from-crystal](reference/from-crystal.md) | What a Crystal programmer must unlearn |
| [from-pony](reference/from-pony.md) | Pony constructs and their Sparkle spelling |
| [limits](reference/limits.md) | What is not supported, and known gaps |
