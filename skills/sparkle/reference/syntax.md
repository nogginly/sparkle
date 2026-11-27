# Syntax

## Comments and statements

```crystal
# a comment
x = 1 # to the end of the line
total = x +
  2
env.out <~ print("#{total}")
```

```text
3
```

A newline ends a statement. It does not end one after a binary operator, a comma, `.` or an opening bracket, inside `(…)` and `[…]`, or when the next line starts with `.`:

```crystal
size = "hello"
  .size()
env.out <~ print("#{size}")
```

```text
5
```

## Variables

```crystal
n = 7
n = n + 1
count : USize = 0
env.out <~ print("#{n} #{count}")
```

```text
8 0
```

- The first assignment in a scope declares the variable; later ones assign.
- A variable first assigned inside an `if` or a loop exists only in that block. Declare it before.
- `x : Type = value` states the type. Do it for anything that is not an `Int32` or `Float64`; see [types](types.md).
- `x += 1` also works for `-=`, `*=`, `/=` and `%=`.
- An assignment has the new value, so `a = b = 7` sets both.

## Numbers

```crystal
a = 1_000
b = 0xFF
c = 0b101
d = 2.5
e = 7_u8
f : U64 = 9
env.out <~ print("#{a} #{b} #{c} #{d} #{e} #{f}")
```

```text
1000 255 5 2.5 7 9
```

| Form | Type |
|---|---|
| `42`, `0x2A`, `0b101010`, `1_000` | `Int32` unless the context gives a type |
| `1.5` | `Float64` unless the context gives a type |
| `7_u8`, `7u8`, `1_i64`, `2.5_f32` | the suffix's type |

`x = 0` makes an `Int32`. A bare literal alone in `"#{…}"` or as a receiver (`7.string`) has no type to ask: give it a variable first.

Division of integers is integer division. Integer types never mix: `Int32 + UInt64` is an error. Convert with `.u64`, `.i32`, `.usize` and so on.

## Strings and chars

```crystal
name = "ada"
greeting = "Hello, " + name + "!"
env.out <~ print("#{greeting} (#{greeting.size} bytes)")
env.out <~ print("tab\there \"quoted\"")
```

```text
Hello, ada! (11 bytes)
tab	here "quoted"
```

- `"…#{expr}…"` calls `string` on the value. Braces and strings may nest inside.
- Escapes are Pony's: `\n \t \" \\ \xNN`.
- `"a" + "b"` joins. `size`, `upper` and `substring(from, to)` are Pony's `String` methods.
- `'a'` is a character literal. It takes the type of its context, so write `c : U8 = 'a'` or `c : U32 = 'a'`.

## Literals

| Literal | Meaning |
|---|---|
| `nil`, `true`, `false` | `Nil`, `Bool` |
| `["a", "b"]` | `Array(String)` |
| `[1, 2] of UInt8` | array with a stated element type |
| `[] of String` | empty array |
| `{a, b}` | tuple |
| `1..5`, `1...5` | range, see [control-flow](control-flow.md) |

```crystal
bytes = [1, 2, 3] of UInt8
names = [] of String
names << "ada"
env.out <~ print("#{bytes.size} #{names.size}")
```

```text
3 1
```

An array of numbers needs `of Type`; there is no default element type. `a << b` is `a.push(b)`. A tuple's parts are `t._1`, `t._2`.

## Operators

Nested operators group by Crystal's precedence, tightest first:

| Operators |
|---|
| `!x` |
| `*` `/` `%` |
| `+` `-` |
| `<<` `>>` |
| `<` `<=` `>` `>=` |
| `==` `!=` `is` `isnt` |
| `&&` |
| `\|\|` |
| `c ? a : b` |
| `=` `+=` `-=` … |

```crystal
n = 7
ok = n > 3 && n % 2 == 1
label = ok ? "odd and big" : "no"
env.out <~ print("#{1 + n * 3} #{(1 + n) * 3} #{label}")
```

```text
22 24 odd and big
```

`&&`, `||` and `!` are `and`, `or` and `not` underneath. `is` compares identity. Overflow wraps for `+ - *`.

## Calls

```crystal
xs = [3, 1, 2] of U32
xs.push(4)
env.out <~ print("#{xs.size}")
```

- Parentheses are required when there are arguments: `f(x)`, not `f x`.
- `f(x: 1)` passes a named argument.
- `a[i]!` reads an element and `a[i]! = v` writes one. Both can fail, see [errors](errors.md).
- `x.name = v` calls the setter `def name=(v)`.
- `foo` with no receiver calls `self.foo`.
