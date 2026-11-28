# Packages

A package is a directory of `.spk` files. `sparkle run app` builds the package in `app/` and every package it requires.

## `require`

| Write | Means |
|---|---|
| `require "./geometry"` | the package in `geometry/`, beside this file |
| `require "../shared"` | the package in `shared/`, in the parent directory |
| `require "json"` | the library's package `json` if it has one, else Pony's package `json` |

`use` is an error: write `require`.

```text
# app/main.spk
require "./geometry"

actor Main
  def self.new(env : Env)
    env.out <~ print("#{Point.new(1, 2).x}")
  end
end
```

```text
# app/geometry/point.spk
class val Point
  @x : Int32
  @y : Int32

  def self.new(x : Int32, y : Int32)
    @x = x
    @y = y
  end

  def x : Int32 = @x
end
```

```text
app/
  main.spk
  geometry/
    point.spk
```

## Names

Every public name of a required package comes into scope. There are no qualified names, so keep type names distinct across packages.

A name starting with `_` is private to its package; a field is private to its type.

Names starting with `spk_` are reserved for names Sparkle generates, and are an error in your code.

## The library

The library is the directory named by `$SPARKLE_LIB`, else `share/sparkle/stdlib` beside an installed `bin/sparkle`, else a `stdlib/` directory found upward from the executable or the working directory.

If the library has a `prelude/` package, every package sees its names without a `require`.

## Errors

A path with no `.spk` files:

```text
app/main.spk:1:1: no Sparkle package at "./geometry": a directory of .spk files
```

Packages that require each other, reported at the `require` that closes the loop: here `geometry` requires `../shared`, and `shared/label.spk` requires `../geometry`:

```text
app/shared/label.spk:1:1: packages require each other: app -> geometry -> shared -> geometry
```

An error inside a required package is reported at that package's own file.
