actor Worker
  var _stream: OutStream

  new create(env: Env) =>
    _stream = env.out

  be process(names: Array[String] iso) =>
    var sealed: Array[String] val = consume names
    _stream.print("worker got " + sealed.size().string() + " names")
    for name in sealed.values() do
      _stream.print("hello, " + name.string())
    end

actor Main
  new create(env: Env) =>
    var worker = Worker.create(env)
    var names = recover iso
      Array[String].create()
    end
    names.push("ada")
    names.push("grace")
    worker.process(consume names)
