use "collections"

trait Shape
  fun area(): U32

  fun name(): String

  fun describe(): String =>
    name().string() + " with area " + area().string()

  fun is_big(): Bool =>
    area() > 10

class Circle is Shape
  var _r: U32

  new create(r: U32) =>
    _r = r

  fun area(): U32 =>
    (3 * _r) * _r

  fun name(): String =>
    "circle"

class Square is Shape
  var _side: U32

  new create(side: U32) =>
    _side = side

  fun area(): U32 =>
    _side * _side

  fun name(): String =>
    "square"

class Vec2
  var _x: U32
  var _y: U32

  new create(x: U32, y: U32) =>
    _x = x
    _y = y

  fun x(): U32 =>
    _x

  fun y(): U32 =>
    _y

  fun add(o: Vec2): Vec2 =>
    Vec2.create(_x + o._x, _y + o._y)

class Stack[A: Any val]
  var _items: Array[A] = Array[A].create()

  fun ref push(item: A) =>
    _items.push(item)

  fun ref pop(): A ? =>
    _items.pop()?

  fun size(): USize =>
    _items.size()

  fun is_empty(): Bool =>
    _items.size() == 0

primitive Report
  fun pop_or(stack: Stack[U32], fallback: U32): U32 =>
    try
      stack.pop()?
    else
      fallback
    end

  fun at_or(names: Array[String], i: USize): String =>
    try
      names(i)?
    else
      "none"
    end

  fun tag_for(n: U32): (String | None) =>
    if n == 0 then None else "n" + n.string() end

actor Main
  new create(env: Env) =>
    var shapes = [as Shape: Circle.create(1); Square.create(4); Circle.create(3)]
    for s in shapes.values() do
      env.out.print(s.describe().string() + " big=" + s.is_big().string())
    end
    var sum = Vec2.create(1, 2) + Vec2.create(3, 4)
    env.out.print("sum = (" + sum.x().string() + ", " + sum.y().string() + ")")
    var stack = Stack[U32].create()
    stack.push(10)
    stack.push(20)
    for _ in Range[USize].till(0, 3) do
      env.out.print("popped " + Report.pop_or(stack, 0).string())
    end
    env.out.print("empty = " + stack.is_empty().string() + " size = " + stack.size().string())
    var names = ["ada"; "grace"]
    env.out.print(Report.at_or(names, 1))
    env.out.print(Report.at_or(names, 7))
    var missing = Report.tag_for(0)
    var present = Report.tag_for(5)
    env.out.print("missing nil = " + (missing is None).string() + ", present nil = " + (present is None).string())
