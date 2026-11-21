primitive TempCold
  fun value(): I32 => -5
  fun string(): String iso^ => "Cold".clone()
  fun eq(that: Temp): Bool => that is this
  fun ne(that: Temp): Bool => not (that is this)
  fun is_cold(): Bool => true
  fun is_mild(): Bool => false

primitive TempMild
  fun value(): I32 => -4
  fun string(): String iso^ => "Mild".clone()
  fun eq(that: Temp): Bool => that is this
  fun ne(that: Temp): Bool => not (that is this)
  fun is_cold(): Bool => false
  fun is_mild(): Bool => true

type Temp is (TempCold | TempMild)

actor Main
  new create(env: Env) =>
    env.out.print("tab\there \"quoted\" back\\slash")
    var n: I32 = 7
    if n < 5 then
      env.out.print("small")
    elseif n < 10 then
      env.out.print("medium")
    else
      env.out.print("large")
    end
    var size = if n < 5 then
      "small"
    elseif n < 10 then
      "medium"
    else
      "large"
    end
    env.out.print("size is " + size.string())
    if not (n > 8) then
      env.out.print("not above 8")
    else
      env.out.print("above 8")
    end
    var a = true
    var b = false
    env.out.print("and " + (a and b).string() + ", or " + (a or b).string())
    env.out.print("nested " + (a and (b or a)).string() + ", " + (a or (b and a)).string())
    var xs = [as I32: 1; 2]
    try
      env.out.print("body")
      xs(5)?
      env.out.print("not reached")
    else
      env.out.print("rescued")
    then
      env.out.print("ensured")
    end
    try
      env.out.print("plain body")
    then
      env.out.print("plain ensure")
    end
    env.out.print(TempCold.string() + " = " + TempCold.value().string() + ", " + TempMild.string() + " = " + TempMild.value().string())
