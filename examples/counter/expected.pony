class Counter
  var _n: U64 = 0

  fun ref incr() =>
    _n = _n + 1

  fun count(): U64 =>
    _n

actor Main
  new create(env: Env) =>
    var c = Counter.create()
    c.incr()
    c.incr()
    env.out.print("count = " + c.count().string())
