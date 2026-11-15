actor Main
  new create(env: Env) =>
    env.out.print(env.args.size().string())
    var names = ["ada"; "grace"]
    env.out.print(names.size().string() + " names, " + "hello".size().string() + " letters")
    env.out.print("explicit field read")
