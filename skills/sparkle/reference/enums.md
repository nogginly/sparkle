# Enums

```crystal
enum Light
  Red
  Amber = 5
  Green
end

actor Main
  def self.new(env : Env)
    light = Light::Amber
    env.out.print("#{light} = #{light.value}")
    env.out.print("#{Light::Green} = #{Light::Green.value}")
  end
end
```

```text
Amber = 5
Green = 6
```

## Members

- A member is a capitalised name on its own line, optionally `= n` with an integer literal, which may be negative.
- Values start at 0; an unvalued member is one more than the one before.
- `value` is an `Int32`.
- `"#{light}"` prints the member's name.
- Refer to a member as `Light::Red`.
- The body holds members only: no methods, no `@[Flags]`, no base type.

An enum is a type, so it can be a parameter, a field or an array element:

```crystal
enum Light
  Red
  Green
end

class Signal
  @state : Light = Light::Red

  def ref flip
    @state = @state == Light::Red ? Light::Green : Light::Red
  end

  def state : Light = @state
end

actor Main
  def self.new(env : Env)
    signal = Signal.new
    signal.flip
    env.out.print("#{signal.state}")
    env.out.print("#{signal.state == Light::Green}")
  end
end
```

```text
Green
true
```

`==` and `!=` compare members.

## Predicates

Every member has a predicate on all values of its enum, named in snake case with `?`: `Red` gives `red?`, `DarkGreen` gives `dark_green?`.

```crystal
enum Light
  Red
  Green
end

actor Main
  def self.new(env : Env)
    light = Light::Green
    env.out.print("#{light.red?} #{light.green?}")
  end
end
```

```text
false true
```

## `case`

```crystal
enum Light
  Red
  Amber
  Green
end

primitive Next
  def after(l : Light) : Light
    case l in
    when .red? then Light::Green
    when Light::Green then Light::Amber
    when .amber? then Light::Red
    end
  end
end

actor Main
  def self.new(env : Env)
    env.out.print("#{Next.after(Light::Red)}")
  end
end
```

```text
Green
```

- `when Light::Red` and `when .red?` both match one member. `.red?` finds the enum in the package that has a member `Red`. It is an error when no enum, or two enums, have one: write `Light::Red`.
- `case x in` means the cases must cover every member. Leave one out and the compiler says `match marked \exhaustive\ is not exhaustive`. Write no `else`.
- Use `x.red?` for a one-off question, `case` to handle every member.

## In error messages

Messages print a member the way you wrote it, `Light::Red`.
