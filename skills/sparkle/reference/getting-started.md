# Getting started

## Install

There are no releases yet. Build from source, then install into one directory:

```sh
git clone --recurse-submodules https://github.com/nogginly/sparkle
cd sparkle
make ponyc build install
export PATH="$HOME/.local/sparkle/bin:$PATH"
```

`make uninstall` removes it. `PREFIX=DIR` picks another directory for both.

## A program

A program is one `.spk` file, or a directory of them that form one package. It starts in `Main`'s constructor, which receives the environment:

```crystal
actor Main
  def self.new(env : Env)
    env.out.print("args: #{env.args.size}")
  end
end
```

```text
args: 1
```

`sparkle run hello.spk` builds and runs it; `sparkle run app/` does the same for a directory. Arguments after `--` reach `env.args`, whose first element is the program's name.

## Printing

`env.out.print(s)` writes a line to standard output, `env.err.print(s)` to standard error. Both take a `String`; interpolation calls `string` on each value:

```crystal
n = 42
env.out.print("n = #{n}, half = #{n / 2}")
```

```text
n = 42, half = 21
```

## Packages

Pony's standard library is available. Import a package with `use` at the top of a file:

```crystal
use "collections"

actor Main
  def self.new(env : Env)
    seen = Set(String).new
    seen.set("a")
    seen.set("a")
    env.out.print("#{seen.size}")
  end
end
```

```text
1
```

`collections` is added for you when a range or `times` needs it.
