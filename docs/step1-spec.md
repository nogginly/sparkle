# Step 1 specification: the Sparkle → Pony translator

Step 1 is a source-to-source translator. It parses Sparkle (`.spk`), writes Pony, and runs an unmodified `ponyc` on the result. It has **no type information**: every rule below is decided from syntax alone. Where that forces a compromise, the rule is marked *(typeless)*.

```mermaid
flowchart LR
    A[".spk source"] --> B["Lexer"] --> C["Parser<br/>(AST with line + column)"] --> D["Emitter"]
    D --> E[".pony source"]
    D --> F["Source map"]
    E --> G["ponyc (unmodified)"]
    G --> H["Diagnostics rewriter"]
    F --> H
    H --> I["Errors in Sparkle terms"]
```

## 1. Lexical rules

- Comments run from `#` to end of line and are dropped.
- A newline ends a statement, except: after a binary operator, a comma, `.`, or an opening `(`/`[`/`{`; inside `(`…`)` and `[`…`]`; and when the next non-blank line starts with `.` (a method chain).
- Identifiers: `[a-z_][A-Za-z0-9_]*`, optionally ending in `?` or `!` when that character follows immediately and is not itself followed by `=` (so `a != b` still lexes as `!=`). Constants: `[A-Z][A-Za-z0-9_]*` (never take a `?`/`!` suffix into the name).
- Instance variables: `@name`.
- Numbers: decimal, `0x`, `0b`, `_` separators, floats. A Crystal suffix (`1_u64`, `2.5_f32`, `7u8`) becomes a Pony conversion (`U64(1)`, `F32(2.5)`).
- Strings: `"…"` with Pony-compatible escapes and `#{expr}` interpolation (nested braces and strings allowed inside). Chars: `'a'`.
- Capability words (`iso trn ref val box tag`, and the generic capability sets `read send share alias any`) are **contextual**: keywords only in type position, right after `def`, right after a type-declaration keyword, and right after `recover`. Everywhere else they are ordinary identifiers. Pony still reserves them, so a variable named `val` is emitted as `val_`.

## 2. Declarations

| Sparkle | Pony |
|---|---|
| `use "collections"` | `use "collections"` |
| `class Foo … end` (also `actor`, `struct`, `primitive`, `trait`, `interface`) | same keyword |
| `class val Point` | `class val Point` |
| `class Box(A)` / `class Box(A : val)` / `class Box(A : val Stringable)` | `class Box[A]` / `class Box[A: Any val]` / `class Box[A: Stringable val]` |
| `include Comparable(Foo)` inside a body (repeatable) | `is Comparable[Foo]` (several: `is (A & B)`) |
| `alias Name = Type` | `type Name is Type` |
| `@n : UInt64 = 0` in a body | `var _n: U64 = 0` |
| `def name(a : A, b : B = 1) : R … end` | `fun name(a: A, b: B = 1): R => …` |
| `def name = expr` (one-liner) | `fun name() => expr` |
| `def ref push(x : A)` | `fun ref push(x: A)` |
| `def self.new(env : Env)` | `new create(env: Env)` |
| `def iso self.new` | `new iso create()` |
| `def self.from_pair(a : A)` | `new from_pair(a: A)` |
| `be name(a : A) … end` (actors) | `be name(a: A) => …` |
| `abstract def name : R` (no body, no `end`) | `fun name(): R` |
| `def first! : A` | `fun first(): A ?` |
| `def empty? : Bool` | `fun is_empty(): Bool` |
| `def name=(v : A)` | `fun ref set_name(v: A)` |
| `def +(o : T) : T` | `fun add(o: T): T` |

### Enums

```crystal
enum Colour
  Red
  Green = 5
  Blue
end
```

becomes one `primitive` per member, named after the enum, and a union type:

```pony
primitive ColourRed
  fun value(): I32 => 0
  fun string(): String iso^ => "Red".clone()
  fun eq(that: Colour): Bool => that is this
  fun ne(that: Colour): Bool => not (that is this)

primitive ColourGreen
  …                                  // value 5

primitive ColourBlue
  …                                  // value 6

type Colour is (ColourRed | ColourGreen | ColourBlue)
```

- A member is a constant on its own line, optionally `= n` with an integer literal (which may be negative). Values start at 0 and each unvalued member is one more than the previous. `value` is always `Int32`.
- `string` gives the member's name, so `"#{c}"` prints `Green` and a member is `Stringable`. `eq` and `ne` make `==` and `!=` work.
- An enum needs at least one member, and member names must be distinct. Methods, flags (`@[Flags]`) and a base type (`enum Colour : UInt8`) are not supported: anything but a member in the body is a parse error.

Operator method names: `+ add`, `- sub`, `* mul`, `/ div`, `% rem`, `== eq`, `!= ne`, `< lt`, `<= le`, `> gt`, `>= ge`, `<< push`, `>> shr`, `[] apply`, `[]! apply … ?`, `[]= update`.

A field needs a type (`@n = 0` alone is a parse error). `def []=`, `def <<` and `def name=` default to `fun ref` when no capability is written.

Pony requires fields before methods, so the emitter writes all of a type's fields first, then methods in source order. An empty body emits `None`.

A `class` or `struct` with no `def self.new` and every field initialised gets an explicit `new create() => None`. Without it Pony infers an `iso` constructor, and `x = Foo.new` could not be passed as a `ref`.

Instance variables map to **private** Pony fields (`@n` → `_n`). This gives Crystal's rule that fields are private, and lets a field and a method share a name (`@count` and `def count`), which Pony otherwise forbids.

## 3. Types

| Sparkle | Pony |
|---|---|
| `Int8 … Int128`, `UInt8 … UInt128` | `I8 … I128`, `U8 … U128` |
| `Float32`, `Float64` | `F32`, `F64` |
| `Nil` | `None` |
| `Array(String)` | `Array[String]` |
| `val String` | `String val` |
| `iso^ String` (ephemeral), `A!` (alias) | `String iso^`, `A!` |
| `String?` / `val String?` | `(String \| None)` / `(String val \| None)` |
| `A \| B`, `A & B` | `(A \| B)`, `(A & B)` |
| `{A, B}` | `(A, B)` |
| `this->A`, `box->A` | `this->A`, `box->A` |
| `Proc(A, B)` (last is the return type) / `val Proc(A, B)` | `{(A): B}` / `{(A): B} val` |
| a capability alone, e.g. `(A : val)` or `(A : send)` | `Any val`, `Any #send` |

All other type names pass through unchanged, so every Pony stdlib type is usable.

## 4. Expressions and statements

### Names, fields and calls

| Sparkle | Pony | Note |
|---|---|---|
| `x = 1` (first assignment in scope) | `var x = 1` | later assignments emit `x = 2` |
| `x : UInt8 = 1` | `var x: U8 = 1` | |
| `x = (y = 5)`, `x = y = 5` | `var x = (var y: I32 = 5; y)` | an assignment used as a value gives the **new** value, as in Crystal; see below |
| `x = 0` / `x = 1.5` (first assignment, bare literal) | `var x: I32 = 0` / `var x: F64 = 1.5` | Crystal's literal defaults; Pony cannot infer them |
| a parameter or local named like a method of its type | emitted with a prime: `payload'` | Pony forbids the clash; Crystal's `def self.new(payload)` beside `def payload` is idiomatic |
| `@n` | `_n` | |
| `self` | `this` | |
| `Colour::Green` | `ColourGreen` | an enum member; not checked against the enum *(typeless)*, so `ponyc` reports an unknown one |
| `x.size` (no arguments, parentheses or block) | `x.size` or `x.size()` | a **field read unless the type checker says `size` is a method**; `sparkle build` decides, see *Fields and methods* below |
| `x.@name` | `x._name` if `name` is an ivar of the enclosing type, otherwise `x.name` | explicit field read, never a call |
| `foo` (not a local or parameter) | `foo()` | call on `this` |
| `Foo.new(a)` / `Array(String).new` | `Foo.create(a)` / `Array[String].create()` | |
| `f(x: 1)` | `f(where x = 1)` | named arguments |
| `Message.new(payload: s)`, where some `def self.new(payload …)` in the package has its `payload` primed | `Message.create(where payload' = s)` | a named argument is primed when a Sparkle method of the same Pony name, anywhere in the package, primes that parameter *(typeless: matched by method name, not by receiver type)* |
| `a[i]` / `a[i]!` | `a(i)` / `a(i)?` | |
| `a[i] = v` / `a[i]! = v` | `a(i) = v` / `a(i)? = v` | |
| `x.name = v` | `x.set_name(v)` | |
| `x.first!` / `x.parse!(s)` | `x.first()?` / `x.parse(s)?` | `!` is Pony's partial-call `?` |
| `x.empty?` | `x.is_empty()` | |
| `x.as!(T)` | `(x as T)` | |
| `x.nil?` | `(x is None)` | |

### Fields and methods

In Crystal `x.name` with no parentheses is a method call, but Pony types also have public fields, such as `env.out`. A bare `x.name` is therefore a field read when `x`'s type has a field `name`, and a call otherwise. The translator has no types, so `sparkle build` asks the compiler:

```mermaid
flowchart TD
    E["Emit every bare x.name<br/>as a field read"] --> C["Type-check only"]
    C --> Q{{"New 'can't reference a method<br/>without calling it' at a bare x.name?"}}
    Q -- yes --> M["Emit those as calls"]
    M --> C
    Q -- no --> B["Compile"]
```

| Sparkle | Pony that is compiled | Rounds of type checking |
|---|---|---|
| `env.out.print("hi")` | `env.out.print("hi")` | 1 |
| `xs.size` | `xs.size()` | 2 |
| `env.args.size.string` | `env.args.size().string()` | 3 |

- **Bare** means a call with a receiver, no arguments, no parentheses and no block, whose name does not end in `!` or `?`, and which is not an assignment target. A receiver that is a type (`Foo.new`, `Array(String).new`, `Foo.bar`) is always a call, because Pony types have no fields.
- A position is reported against the Sparkle name after the dot, so one round settles every bare name whose receiver's type is known; a chain settles one link per round.
- The default is a field because the reverse cannot work: calling a field means calling `apply()` on its value, which either fails with an unrelated error or compiles with a different meaning.
- `x.@name` still reads a field and is never a call. `env.@out` keeps working; `env.out` is the ordinary spelling.
- `sparkle translate` has no type checker, so it prints every bare `x.name` as a field read. The Pony that `build` compiled is in `.sparkle/<package>/`, and the examples' `expected.pony` files hold that resolved Pony.

### Assignment as a value

Pony's assignment evaluates to the old value; Sparkle's, like Crystal's, to the new one. An assignment is a **statement** when its value is discarded: a statement that is not the last of its block, the last of a block whose value is unused (a loop body, a block passed as a lambda, a `be`, a constructor, a method with no return type or `Nil`, an `if` used as a statement), or the body of a modifier `if`/`unless` used as a statement. A statement emits as before. Anywhere else the assignment is a **value**, and the target is read back:

| Sparkle | Pony |
|---|---|
| `y = 5` (statement) | `y = 5` |
| `x = (y = 5)` | `var x = (y = 5; y)` |
| `def ref incr : UInt64 = @n += 1` | `fun ref incr(): U64 => (_n = _n + 1; _n)` |
| `while (n -= 1) > 0` | `while (n = n - 1; n) > 0 do` |

Only a local or `@field` target can be used as a value. An index (`a[i] = v`), setter (`x.name = v`) or field write (`x.@name = v`) used as a value is a translation error.

### Operators

Pony has no operator precedence, so the emitter parenthesises every nested binary expression using Crystal's precedence.

| Sparkle | Pony |
|---|---|
| `&&`, `\|\|`, `!x` | `and`, `or`, `not x` |
| `+ - * / % == != < <= > >=`, `>>`, `is`, `isnt` | unchanged |
| `a << b` | `a.push(b)` *(typeless: integer shift is `a.shl(b)`)* |
| `a += b` (also `-= *= /= %=`) | `a = a + b` |
| `c ? a : b` | `if c then a else b end` |
| `a...b` / `a..b` | `Range[USize].till(a, b)` / `Range[USize].through(a, b)`, adding `use "collections"` if missing *(typeless: the element type is fixed at `USize`)* |

### Literals

| Sparkle | Pony |
|---|---|
| `nil`, `true`, `false` | `None`, `true`, `false` |
| `"n = #{n}!"` / `"#{n}"` | `"n = " + n.string() + "!"` / `"" + n.string()` |
| `[1, 2, 3]` / `[1, 2] of UInt8` / `[] of String` | `[1; 2; 3]` / `[as U8: 1; 2]` / `Array[String].create()` |
| `{a, b}` in expression position | `(a, b)` |

### Control flow

| Sparkle | Pony |
|---|---|
| `if c … elsif d … else … end` | `if c then … elseif d then … else … end` |
| `unless c … end` | `if not (c) then … end` |
| `stmt if c` / `stmt unless c` | `if c then stmt end` / `if not (c) then stmt end` |
| `while c … end` / `until c … end` | `while c do … end` / `while not (c) do … end` |
| `loop do … end` | `while true do … end` |
| `break`, `next`, `return x` | `break`, `continue`, `return x` |
| `case x when 1, 2 … when s : String … when {a, b} … else … end` | `match x \| 1 \| 2 => … \| let s: String => … \| (a, b) => … else … end` |
| `case x in …` | `match \exhaustive\ x …` |
| `when Colour::Red` / `in Colour::Red` | `\| let _: ColourRed =>` | matched by type, because Pony does not count a primitive with its own `eq` towards exhaustiveness |
| `begin … rescue … ensure … end` | `try … else … then … end` |
| `raise` (takes no value) | `error` |
| `consume x` | `consume x` |
| `recover iso do … end` / `recover do … end` | `recover iso … end` / `recover … end` |

### Blocks

Step 1 has no `yield`. A block is either loop sugar or a lambda.

| Sparkle | Pony | Note |
|---|---|---|
| `xs.each do \|x\| … end` | `for x in xs.values() do … end` | *(typeless, by method name)* |
| `xs.each_with_index do \|x, i\| … end` | `for (i, x) in xs.pairs() do … end` | |
| `n.times do \|i\| … end` | `for i in Range[USize].till(0, n) do … end` | `n` must be a `USize` |
| `(a...b).each do \|i\| … end` | `for i in Range[USize].till(a, b) do … end` | |
| any other `recv.m(args) do \|x\| … end` or `{ \|x\| … }` | `recv.m(args, {(x) => …})` | lambda as last argument |
| `&.name` as an argument | `{(x) => x.name()}` | |

`break` and `next` work inside loop sugar because it is a real Pony loop.

## 5. Tooling

1. **Source map.** The emitter records a mark `(pony line, pony column) → (sparkle line, sparkle column)` each time it starts writing a node. A `ponyc` location maps to the last mark at or before it on that line.
2. **Diagnostics.** `ponyc` output is rewritten: file, line and column go through the source map, the quoted source excerpt is replaced by the Sparkle line with a caret, and Pony type expressions inside messages are re-printed in Sparkle syntax, including in notes that point into the Pony stdlib (`Array[String val] ref` → `ref Array(val String)`, `(String val | None val)` → `val String?`). An enum member's Pony name is printed as Sparkle's: `ColourRed` → `Colour::Red`.
3. **Capability statistics.** `sparkle caps` reports, per file, how many capability annotations were written, by position (type declaration, `def`, type, `recover`) and by capability.

## 6. CLI

```
sparkle translate FILE.spk          # print the generated Pony
sparkle build PATH [-o DIR]         # PATH is a .spk file or a directory (one Pony package)
sparkle run PATH [-- args]          # build, then run the binary
sparkle caps PATH...                # capability statistics
```

`build` writes generated Pony under `.sparkle/<package>/` and compiles it with the `libponyc` linked into `sparkle`, using the standard library of the Pony installation that holds the first `ponyc` found via `$SPARKLE_PONYC`, then `.tools/ponyc/bin/ponyc` (installed by `make ponyc`), then `vendor/ponyc/build/release/ponyc` (built by `make ponyc-source`), then `PATH`. Both paths are searched upward from the executable's directory and from the current directory.

## 7. Not in step 1

`yield`, macros (`getter`, `property`, `record`), methods inside an `enum`, calls with arguments but no parentheses (`puts "x"`), hash and symbol literals, FFI, `let`/`embed` fields, generic method calls, reopening types.

## 8. Known semantic gaps

- Reading an assignment's value aliases the target, so `x = (y = consume z)` fails for an `iso` `z`. Assign, then `consume y`.
- An index, setter or field assignment cannot be used as a value (see *Assignment as a value*).
- A variable first assigned inside a branch or loop is scoped to that block, as in Pony.
- `ticks = 0` is an `Int32`, as in Crystal, so it will not compare with a `USize`. Write `ticks : USize = 0`.
- A named argument is primed by method name alone. If two types in a package each define `f` and only one primes its parameter `x`, then `f(x: 1)` is primed for both, and `ponyc` reports the call to the other.
- `x.@name` picks the private field whenever the enclosing type has an ivar of that name, so a type with `@out` cannot also read `env.@out`; it can read `env.out`.
- Each link of a chain of bare method names (`a.b.c`) costs one more round of type checking, about 0.15 s.
- A bare name is resolved once per position, so it cannot be a field for one caller and a method for another, for example in a generic method used with two types.
- In a `case`, a tuple pattern `{a, b}` compares against existing values; binding is written `{a : String, b : UInt32}`.
- A continuation line inside parentheses may not start with an operator; end the previous line with it instead.
- `def pop` and `def pop!` both become `pop`; `def empty?` and `def is_empty` both become `is_empty`. Defining both is an error from `ponyc`.
