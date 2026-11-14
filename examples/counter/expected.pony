class Counter
  var _n: U64 = 0

  new create() =>
    None

  fun ref incr(): U64 =>
    (_n = _n + 1; _n)

  fun count(): U64 =>
    _n

actor Main
  new create(env: Env) =>
    var c = Counter.create()
    c.incr()
    var last = c.incr()
    var a = (var b: I32 = 7; b)
    env.out.print("count = " + c.count().string() + ", last = " + last.string() + ", a = " + a.string() + ", b = " + b.string())
