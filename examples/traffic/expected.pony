primitive LightRed
  fun value(): I32 => 0
  fun string(): String iso^ => "Red".clone()
  fun eq(that: Light): Bool => that is this
  fun ne(that: Light): Bool => not (that is this)

primitive LightAmber
  fun value(): I32 => 5
  fun string(): String iso^ => "Amber".clone()
  fun eq(that: Light): Bool => that is this
  fun ne(that: Light): Bool => not (that is this)

primitive LightGreen
  fun value(): I32 => 6
  fun string(): String iso^ => "Green".clone()
  fun eq(that: Light): Bool => that is this
  fun ne(that: Light): Bool => not (that is this)

type Light is (LightRed | LightAmber | LightGreen)

actor Main
  new create(env: Env) =>
    var lights = [as Light: LightRed; LightAmber; LightGreen]
    for light in lights.values() do
      env.out.print(light.string() + " = " + light.value().string() + ", next " + after(light).string())
      if light == LightGreen then
        env.out.print("go")
      end
    end

  fun after(l: Light): Light =>
    match \exhaustive\ l
    | let _: LightRed =>
      LightGreen
    | let _: LightAmber =>
      LightRed
    | let _: LightGreen =>
      LightAmber
    end
