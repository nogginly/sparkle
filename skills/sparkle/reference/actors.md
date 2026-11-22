# Actors

An actor is a class with its own state that runs on its own. You talk to it by sending it messages, and it handles them one at a time. No two threads ever touch an actor's fields.

```crystal
actor Printer
  @out : OutStream

  def self.new(out : OutStream)
    @out = out
  end

  be say(text : String)
    @out.print(text)
  end
end

actor Main
  def self.new(env : Env)
    printer = Printer.new(env.out)
    printer.say("one")
    printer.say("two")
  end
end
```

```text
one
two
```

## Behaviours

`be` declares a behaviour: a method that runs later, asynchronously. The call returns at once, with nothing.

- A behaviour has no return type and no value. To get an answer, pass the sender and have the behaviour send one back.
- Messages from one actor to another arrive in the order they were sent.
- Messages from different senders arrive in no fixed order. Make one actor do all the printing, and do not depend on the order between actors.
- A behaviour's parameters must be `iso`, `val` or `tag`, since they cross to another actor. A `String` literal is `val`, so it is fine. See [capabilities](capabilities.md).

## Replying

An actor is held as a `tag`: you can send it messages, not read it. Pass one to another actor to let it reply.

```crystal
actor Collector
  @out : OutStream
  @total : UInt64 = 0
  @pending : USize

  def self.new(out : OutStream, expected : USize)
    @out = out
    @pending = expected
  end

  be add(value : UInt64)
    @total += value
    @pending -= 1
    if @pending == 0
      @out.print("total = #{@total}")
    end
  end
end

actor Worker
  @sink : Collector

  def self.new(sink : Collector)
    @sink = sink
  end

  be run(n : UInt64)
    @sink.add(n * n)
  end
end

actor Main
  def self.new(env : Env)
    count : USize = 3
    sink = Collector.new(env.out, count)
    n : UInt64 = 1
    count.times do |i|
      Worker.new(sink).run(n + i.u64)
    end
  end
end
```

```text
total = 14
```

Each `Worker` sends to `Collector` in its own time; addition does not care about the order, so the output is the same on every run.

## Methods on actors

```crystal
actor Greeter
  @out : OutStream

  def self.new(out : OutStream)
    @out = out
  end

  be greet(name : String)
    @out.print(line(name))
  end

  def line(name : String) : String = "hello, #{name}"
end
```

Other code cannot call a `def` on an actor, because a `tag` reference gives access only to behaviours. Use `def` for helpers.

## Sending data

```crystal
actor Sink
  be take(data : val Array(String), out : OutStream)
    out.print("got #{data.size}")
  end
end

actor Main
  def self.new(env : Env)
    data = recover val do
      list = Array(String).new
      list << "a"
      list << "b"
      list
    end
    Sink.new.take(data, env.out)
    Sink.new.take(data, env.out)
  end
end
```

- `val` data is shared: send it to any number of actors.
- `iso` data is moved: write `consume x` as the argument.
- A `ref` value cannot be sent. Build it in `recover`, or make it `val` once it is finished.

## Main and `env`

`Main` is the actor that starts the program. Its constructor runs first and gets `env`. The program ends when every actor has no messages left.

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
