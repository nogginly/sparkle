# Sparkle

An experimental compiled language: Crystal's syntax and Ruby-style idioms on top of Pony's reference capabilities and actors.

```crystal
class Counter
  @n : UInt64 = 0
  def ref incr = @n += 1
  def count : UInt64 = @n
end

actor Main
  def self.new(env : Env)
    c = Counter.new
    c.incr
    env.@out.print("count = #{c.count}")
  end
end
```

## Status

Step 1 of the roadmap: a source-to-source translator. It parses Sparkle (`.spk`), writes Pony, runs an unmodified `ponyc`, and rewrites the compiler's errors back into Sparkle locations and type syntax. It has no type information of its own, which explains most of its rough edges.

- [docs/step1-spec.md](docs/step1-spec.md): every translation rule, the tooling, and the known gaps.
- [examples/](examples): five programs, each with its generated Pony and expected output.

## Getting started

Requires Crystal 1.11 or later, and Linux on x86-64 for the prebuilt Pony compiler.

```bash
git submodule update --init
```

```bash
make ponyc
```

```bash
make build
```

```bash
bin/sparkle run examples/counter/main.spk
```

`make ponyc` downloads the Pony release matching `vendor/ponyc/VERSION` into `.tools/`. `make ponyc-source` builds it from the submodule instead, which takes about an hour because it compiles LLVM.

## Commands

| Command | Outcome |
|---|---|
| `sparkle translate FILE.spk` | Prints the generated Pony |
| `sparkle build PATH [-o DIR]` | Compiles a `.spk` file or a directory of them into a binary |
| `sparkle run PATH [-- args]` | Builds, then runs the binary |
| `sparkle caps PATH...` | Counts capability annotations per file |

## Tests

```bash
make test
```

The suite includes golden translations of every example and end-to-end runs through `ponyc`; the latter are skipped when no `ponyc` is found. `UPDATE_GOLDEN=1 crystal spec` rewrites the golden files.

## Layout

| Path | Contents |
|---|---|
| `src/sparkle/` | Lexer, parser, emitter, source map, diagnostics rewriter, driver |
| `spec/` | Unit, golden and end-to-end specs |
| `examples/` | Sparkle programs used as golden tests |
| `vendor/ponyc` | Pony, as a submodule pinned to a release tag |
