use "collections"

primitive FizzBuzz
  fun label(i: USize): String =>
    match (i % 3, i % 5)
    | (0, 0) =>
      "FizzBuzz"
    | (0, _) =>
      "Fizz"
    | (_, 0) =>
      "Buzz"
    else
      "" + i.string()
    end

actor Main
  new create(env: Env) =>
    for i in Range[USize].through(1, 15) do
      env.out.print(FizzBuzz.label(i))
    end
    var ticks: I32 = 0
    while ticks < 5 do
      ticks = ticks + 1
      if ticks == 2 then continue end
      env.out.print("tick " + ticks.string())
      if ticks >= 4 then break end
    end
    for n in Range[USize].till(0, 3) do
      env.out.print("n = " + n.string())
    end
