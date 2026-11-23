require "./spec_helper"

include Sparkle

# Wraps statements in the constructor of `actor Main`.
private def in_main(statements : String) : String
  "actor Main\n  def self.new(env : Env)\n" + statements.lines.map { |line| "    #{line}\n" }.join + "  end\nend\n"
end

describe Emitter do
  describe "declarations" do
    it "maps class forms, includes and aliases" do
      rule "class val Point\nend\n", <<-PONY
        class val Point
          new create() =>
            None

        PONY
      rule "class Box(A : val Stringable)\nend\n", <<-PONY
        class Box[A: Stringable val]
          new create() =>
            None

        PONY
      rule "class Box(A : send)\nend\n", <<-PONY
        class Box[A: Any #send]
          new create() =>
            None

        PONY
      rule "class Foo\n  include A\n  include B\nend\n", <<-PONY
        class Foo is (A & B)
          new create() =>
            None

        PONY
      rule "alias Name = String?\n", <<-PONY
        type Name is (String | None)

        PONY
    end

    it "writes fields before methods and makes them private" do
      rule "class C\n  def count : UInt64 = @count\n  @count : UInt64 = 0\nend\n", <<-PONY
        class C
          var _count: U64 = 0

          new create() =>
            None

          fun count(): U64 =>
            _count

        PONY
    end

    it "adds an explicit create to classes without constructors" do
      rule "class C\nend\n", <<-PONY
        class C
          new create() =>
            None

        PONY
      rule "class C\n  def self.new\n  end\nend\n", <<-PONY
        class C
          new create() =>
            None

        PONY
      rule "actor A\nend\n", "actor A\n"
    end

    it "maps method forms" do
      rule <<-SPK, <<-PONY
        class C
          def ref push(x : Int8, b : UInt8 = 1)
          end
          def self.new(env : Env)
          end
          def iso self.new
          end
          def self.from_pair(a : A)
          end
          def first! : A
          end
          def empty? : Bool
          end
          def name=(v : A)
          end
          def +(o : T) : T
          end
          def []!(i : USize) : A
          end
          def []=(i : USize, v : A)
          end
        end
        SPK
        class C
          fun ref push(x: I8, b: U8 = 1) =>
            None

          new create(env: Env) =>
            None

          new iso create() =>
            None

          new from_pair(a: A) =>
            None

          fun first(): A ? =>
            None

          fun is_empty(): Bool =>
            None

          fun ref set_name(v: A) =>
            None

          fun add(o: T): T =>
            None

          fun apply(i: USize): A ? =>
            None

          fun ref update(i: USize, v: A) =>
            None

        PONY
    end

    it "emits abstract methods without bodies and behaviours" do
      rule "trait T\n  abstract def area : F64\nend\nactor A\n  be go(x : iso Array(String))\n  end\nend\n", <<-PONY
        trait T
          fun area(): F64

        actor A
          be go(x: Array[String] iso) =>
            None

        PONY
    end

    it "emits None for empty bodies" do
      rule "class C\n  def f\n  end\nend\n", <<-PONY
        class C
          new create() =>
            None

          fun f() =>
            None

        PONY
    end

    it "adds use \"collections\" when ranges are used" do
      rule in_main("(1..3).each do |i|\nend"), <<-PONY
        use "collections"

        actor Main
          new create(env: Env) =>
            for i in Range[USize].through(1, 3) do
              None
            end

        PONY
    end

    it "keeps an existing use of collections once" do
      rule "use \"collections\"\n" + in_main("3.times do\nend"), <<-PONY
        use "collections"

        actor Main
          new create(env: Env) =>
            for _ in Range[USize].till(0, 3) do
              None
            end

        PONY
    end

    it "keeps several uses in order" do
      rule "use \"foo\"\nuse \"bar\"\n" + in_main("3.times do\nend"), <<-PONY
        use "foo"
        use "bar"
        use "collections"

        actor Main
          new create(env: Env) =>
            for _ in Range[USize].till(0, 3) do
              None
            end

        PONY
    end
  end

  describe "names, fields and calls" do
    it "decides var versus assignment from scope" do
      rule in_main("x = 1\nx = 2"), <<-PONY
        actor Main
          new create(env: Env) =>
            var x: I32 = 1
            x = 2

        PONY
    end

    it "keeps variables first assigned in a branch scoped to it" do
      rule in_main("if true\n  y = 1\nend\ny = 2"), <<-PONY
        actor Main
          new create(env: Env) =>
            if true then
              var y: I32 = 1
            end
            var y: I32 = 2

        PONY
    end

    it "treats bare names as calls unless local" do
      rule in_main("foo\nz = 1\nz"), <<-PONY
        actor Main
          new create(env: Env) =>
            foo()
            var z: I32 = 1
            z

        PONY
    end

    it "emits typed locals, self, instance variables and field reads" do
      rule "class C\n  @n : U8 = 0\n  def f(o : C, env : Env)\n    x : UInt8 = 1\n    self\n    @n\n    o.@n\n    env.@out\n  end\nend\n", <<-PONY
        class C
          var _n: U8 = 0

          new create() =>
            None

          fun f(o: C, env: Env) =>
            var x: U8 = 1
            this
            _n
            o._n
            env.out

        PONY
    end

    it "emits calls, constructors, named arguments and setters" do
      rule in_main("x.size\nFoo.new(1)\nArray(String).new\nf(x: 1)\nf(1, y: 2)\nx.name = 3"), <<-PONY
        actor Main
          new create(env: Env) =>
            x().size
            Foo.create(1)
            Array[String].create()
            f(where x = 1)
            f(1 where y = 2)
            x().set_name(3)

        PONY
    end

    it "emits indexing, partial calls and predicates" do
      rule in_main("a = [1]\na[0]\na[0]!\na[0] = 1\na[0]! = 1\na.first!\na.parse!(s)\na.empty?\na.nil?\na.as!(String)"), <<-PONY
        actor Main
          new create(env: Env) =>
            var a = [1]
            a(0)
            a(0)?
            a(0) = 1
            a(0)? = 1
            a.first()?
            a.parse(s())?
            a.is_empty()
            (a is None)
            (a as String)

        PONY
    end

    it "types variables first bound to bare numeric literals" do
      rule in_main("a = 0\nb = -1\nc = 1.5\nd = 1_u64\ne = 2.5_f32\nf = a"), <<-PONY
        actor Main
          new create(env: Env) =>
            var a: I32 = 0
            var b: I32 = -1
            var c: F64 = 1.5
            var d = U64(1)
            var e = F32(2.5)
            var f = a

        PONY
    end

    it "primes locals that share a name with a method of the type" do
      rule "class C\n  @payload : U32\n  def self.new(payload : U32)\n    @payload = payload\n  end\n  def payload : U32 = @payload\n  def g(xs : Array(U32))\n    xs.each do |payload|\n      payload\n    end\n    payload\n    payload = 1\n    payload\n  end\nend\n", <<-PONY
        class C
          var _payload: U32

          new create(payload': U32) =>
            _payload = payload'

          fun payload(): U32 =>
            _payload

          fun g(xs: Array[U32]) =>
            for payload' in xs.values() do
              payload'
            end
            payload()
            var payload': I32 = 1
            payload'

        PONY
    end

    it "escapes Pony reserved words used as names" do
      rule in_main("val = 1\nval"), <<-PONY
        actor Main
          new create(env: Env) =>
            var val_: I32 = 1
            val_

        PONY
    end

    it "emits default parameter values and negative literals" do
      rule "class C\n  def f(a : Int32 = 1 + 2, b : String = \"x\", c : Int8 = -1_i8) : Int32\n    a\n  end\nend\n", <<-PONY
        class C
          new create() =>
            None

          fun f(a: I32 = 1 + 2, b: String = "x", c: I8 = I8(-1)): I32 =>
            a

        PONY
    end
  end

  describe "named arguments" do
    job = "class val Job\n  @payload : UInt32\n  def self.new(payload : UInt32)\n    @payload = payload\n  end\n  def payload : UInt32 = @payload\nend\n"
    main = "actor Main\n  def self.new(env : Env)\n    j = Job.new(payload: 1)\n  end\nend\n"

    it "primes a named argument whose parameter is primed" do
      rule job + main, <<-PONY
        class val Job
          var _payload: U32

          new create(payload': U32) =>
            _payload = payload'

          fun payload(): U32 =>
            _payload

        actor Main
          new create(env: Env) =>
            var j = Job.create(where payload' = 1)

        PONY
    end

    it "leaves an unmatched named argument alone" do
      rule in_main("f(x: 1)"), <<-PONY
        actor Main
          new create(env: Env) =>
            f(where x = 1)

        PONY
    end

    it "matches methods across programs" do
      job_program = Parser.parse(job)
      main_program = Parser.parse(main)
      table = Emitter.primed_params([job_program, main_program])
      Emitter.emit(main_program, table)[0].should contain "where payload' = 1"
    end
  end

  describe "operators and literals" do
    it "parenthesises nested binary expressions" do
      rule in_main("a = 1 + 2 * 3 - 4"), <<-PONY
        actor Main
          new create(env: Env) =>
            var a = (1 + (2 * 3)) - 4

        PONY
      rule in_main("a = 1\nb = a > 1 && a < 5 || !(a == 3)"), <<-PONY
        actor Main
          new create(env: Env) =>
            var a: I32 = 1
            var b = ((a > 1) and (a < 5)) or not (a == 3)

        PONY
    end

    it "rewrites << and compound assignment" do
      rule in_main("a = 1\nb = []of String\nb << \"x\"\na += 2\na *= 3"), <<-PONY
        actor Main
          new create(env: Env) =>
            var a: I32 = 1
            var b = Array[String].create()
            b.push("x")
            a = a + 2
            a = a * 3

        PONY
    end

    it "emits ternaries and ranges" do
      rule in_main("c = true\nx = c ? 1 : 2\nr = 1...n"), <<-PONY
        use "collections"

        actor Main
          new create(env: Env) =>
            var c = true
            var x = if c then 1 else 2 end
            var r = Range[USize].till(1, n())

        PONY
    end

    it "emits literals" do
      rule in_main("a = nil\nb = 1_u64\nc = 2.5_f32\nd = {1, 2}\ne = [1, 2, 3]\nf = [1, 2] of UInt8\ng = [] of String"), <<-PONY
        actor Main
          new create(env: Env) =>
            var a = None
            var b = U64(1)
            var c = F32(2.5)
            var d = (1, 2)
            var e = [1; 2; 3]
            var f = [as U8: 1; 2]
            var g = Array[String].create()

        PONY
    end

    it "emits numbers in every form" do
      rule in_main("a = -2.5\nb = 0x1F\nc = 1_f32\nd = 1_000.5\ne = 1e3\nf = 7 - -1\ng = {1}"), <<-PONY
        actor Main
          new create(env: Env) =>
            var a: F64 = -2.5
            var b: I32 = 0x1F
            var c = F32(1)
            var d: F64 = 1_000.5
            var e: F64 = 1e3
            var f = 7 - -1
            var g = (1)

        PONY
    end

    it "emits chars" do
      rule in_main(<<-'SPK'), <<-'PONY'
        a = 'a'
        b = '\n'
        c = '\x41'
        d = '\''
        e = '\\'
        f = '\0'
        g = '\xE9'
        h = 'é'
        SPK
        actor Main
          new create(env: Env) =>
            var a = 'a'
            var b = '\n'
            var c = '\x41'
            var d = '\''
            var e = '\\'
            var f = '\0'
            var g = '\xE9'
            var h = 'é'

        PONY
    end

    it "emits string interpolation as concatenation" do
      rule in_main(<<-'SPK'), <<-'PONY'
        n = 1
        s = "n = #{n}!"
        t = "#{n}"
        u = "plain\n"
        v = "#{n + 1}"
        SPK
        actor Main
          new create(env: Env) =>
            var n: I32 = 1
            var s = "n = " + n.string() + "!"
            var t = "" + n.string()
            var u = "plain\n"
            var v = "" + (n + 1).string()

        PONY
    end
  end

  describe "control flow" do
    it "emits if, elsif, else and unless" do
      rule in_main("if a\n  b\nelsif c\n  d\nelse\n  e\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            if a() then
              b()
            elseif c() then
              d()
            else
              e()
            end

        PONY
      rule in_main("unless a\n  b\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            if not (a()) then
              b()
            end

        PONY
    end

    it "emits postfix modifiers" do
      rule in_main("a if b\na unless b"), <<-PONY
        actor Main
          new create(env: Env) =>
            if b() then a() end
            if not (b()) then a() end

        PONY
    end

    it "emits loops" do
      rule in_main("while a\n  break\nend\nuntil a\n  next\nend\nloop do\n  return 1\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            while a() do
              break
            end
            while not (a()) do
              continue
            end
            while true do
              return 1
            end

        PONY
    end

    it "emits case as match" do
      rule in_main("case x\nwhen 1, 2\n  a\nwhen s : String\n  s\nwhen {p, _}\n  b\nelse\n  c\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            match x()
            | 1 | 2 =>
              a()
            | let s: String =>
              s
            | (p, _) =>
              b()
            else
              c()
            end

        PONY
      rule in_main("case x in\nwhen 1\n  a\nend"), <<-'PONY'
        actor Main
          new create(env: Env) =>
            match \exhaustive\ x()
            | 1 =>
              a()
            end

        PONY
    end

    it "emits begin as try" do
      rule in_main("begin\n  a\nrescue\n  b\nensure\n  c\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            try
              a()
            else
              b()
            then
              c()
            end

        PONY
      rule in_main("raise"), <<-PONY
        actor Main
          new create(env: Env) =>
            error

        PONY
    end

    it "emits recover and consume" do
      rule in_main("x = recover iso do\n  Foo.new\nend\ny = consume x"), <<-PONY
        actor Main
          new create(env: Env) =>
            var x = recover iso
              Foo.create()
            end
            var y = consume x

        PONY
    end
  end

  describe "blocks" do
    it "turns each, each_with_index and times into for loops" do
      rule in_main("xs = [1]\nxs.each do |x|\n  x\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            var xs = [1]
            for x in xs.values() do
              x
            end

        PONY
      rule in_main("xs = [1]\nxs.each_with_index do |x, i|\n  x\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            var xs = [1]
            for (i, x) in xs.pairs() do
              x
            end

        PONY
      rule in_main("5.times do |i|\n  i\nend"), <<-PONY
        use "collections"

        actor Main
          new create(env: Env) =>
            for i in Range[USize].till(0, 5) do
              i
            end

        PONY
      rule in_main("(1...4).each do |i|\n  i\nend"), <<-PONY
        use "collections"

        actor Main
          new create(env: Env) =>
            for i in Range[USize].till(1, 4) do
              i
            end

        PONY
      rule in_main("(1..4).each do |i|\n  i\nend"), <<-PONY
        use "collections"

        actor Main
          new create(env: Env) =>
            for i in Range[USize].through(1, 4) do
              i
            end

        PONY
    end

    it "turns other blocks into lambda arguments" do
      rule in_main("a.map do |x|\n  x.size\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            a().map({(x) => x.size})

        PONY
      rule in_main("a.fold(0) { |acc, x| acc + x }"), <<-PONY
        actor Main
          new create(env: Env) =>
            a().fold(0, {(acc, x) => acc + x})

        PONY
      rule in_main("a.each_pair do |k, v|\n  k\n  v\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            a().each_pair({(k, v) =>
              k
              v
            })

        PONY
    end

    it "turns blocks that do not fit a loop into lambda arguments" do
      rule in_main("xs.each do |a, b|\n  a\nend\nxs.each_with_index do |a|\n  a\nend\nfoo do\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            xs().each({(a, b) => a})
            xs().each_with_index({(a) => a})
            foo({() =>
              None
            })

        PONY
    end

    it "turns &.name into a lambda" do
      rule in_main("a.map(&.size)"), <<-PONY
        actor Main
          new create(env: Env) =>
            a().map({(x) => x.size()})

        PONY
      rule in_main("xs.map do |x|\n  xs.each(&.run!)\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            xs().map({(x) => xs().each({(x1) => x1.run()?})})

        PONY
    end

    it "scopes block parameters to the block" do
      rule in_main("xs = [1]\nxs.each do |x|\nend\nx = 1"), <<-PONY
        actor Main
          new create(env: Env) =>
            var xs = [1]
            for x in xs.values() do
              None
            end
            var x: I32 = 1

        PONY
    end
  end

  describe "assignment as a value" do
    it "keeps statements unchanged" do
      rule in_main("y = 5\ny = 6"), <<-PONY
        actor Main
          new create(env: Env) =>
            var y: I32 = 5
            y = 6

        PONY
      rule in_main("c = true\nx = 1 if c"), <<-PONY
        actor Main
          new create(env: Env) =>
            var c = true
            if c then var x: I32 = 1 end

        PONY
    end

    it "evaluates to the new value" do
      rule in_main("x = (y = 5)"), <<-PONY
        actor Main
          new create(env: Env) =>
            var x = (var y: I32 = 5; y)

        PONY
      rule in_main("x = y = 5"), <<-PONY
        actor Main
          new create(env: Env) =>
            var x = (var y: I32 = 5; y)

        PONY
      rule in_main("n = 3\nwhile (n -= 1) > 0\n  n\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            var n: I32 = 3
            while (n = n - 1; n) > 0 do
              n
            end

        PONY
    end

    it "returns the new value from a method with a return type" do
      rule "class C\n  @n : UInt64 = 0\n  def ref incr : UInt64 = @n += 1\nend\n", <<-PONY
        class C
          var _n: U64 = 0

          new create() =>
            None

          fun ref incr(): U64 =>
            (_n = _n + 1; _n)

        PONY
      rule "class C\n  @n : UInt64 = 0\n  def ref bump = @n += 1\nend\n", <<-PONY
        class C
          var _n: U64 = 0

          new create() =>
            None

          fun ref bump() =>
            _n = _n + 1

        PONY
    end

    it "treats a block's last statement as a statement, since a lambda returns None" do
      rule in_main("a = [1]\nf(1) do |v|\n  a[0] = v\nend"), <<-PONY
        actor Main
          new create(env: Env) =>
            var a = [1]
            f(1, {(v) => a(0) = v})

        PONY
      rule in_main("a = [1]\nf(1) { |v| a[0] = v }"), <<-PONY
        actor Main
          new create(env: Env) =>
            var a = [1]
            f(1, {(v) => a(0) = v})

        PONY
    end

    it "assigns through indexes, setters and fields" do
      rule in_main("a = [1]\na[0] += 1\nx.n += 1\no.@n = 2\no.@n += 2"), <<-PONY
        actor Main
          new create(env: Env) =>
            var a = [1]
            a(0) = a(0) + 1
            x().set_n(x().n() + 1)
            o().n = 2
            o().n = o().n + 2

        PONY
    end

    it "rejects the value of an index assignment" do
      expect_raises(ParseError) { translate("actor Main\n  def self.new(env : Env)\n    a = [1]\n    b = (a[0] = 2)\n  end\nend\n") }
    end
  end

  describe "enums" do
    it "emits a primitive per member and a union type" do
      rule "enum Colour\n  Red\n  Green = 5\n  Blue\nend\n", <<-PONY
        primitive ColourRed
          fun value(): I32 => 0
          fun string(): String iso^ => "Red".clone()
          fun eq(that: Colour): Bool => that is this
          fun ne(that: Colour): Bool => not (that is this)
          fun is_red(): Bool => true
          fun is_green(): Bool => false
          fun is_blue(): Bool => false

        primitive ColourGreen
          fun value(): I32 => 5
          fun string(): String iso^ => "Green".clone()
          fun eq(that: Colour): Bool => that is this
          fun ne(that: Colour): Bool => not (that is this)
          fun is_red(): Bool => false
          fun is_green(): Bool => true
          fun is_blue(): Bool => false

        primitive ColourBlue
          fun value(): I32 => 6
          fun string(): String iso^ => "Blue".clone()
          fun eq(that: Colour): Bool => that is this
          fun ne(that: Colour): Bool => not (that is this)
          fun is_red(): Bool => false
          fun is_green(): Bool => false
          fun is_blue(): Bool => true

        type Colour is (ColourRed | ColourGreen | ColourBlue)

        PONY
    end

    it "emits member references and patterns" do
      rule in_main("c = Colour::Green"), <<-PONY
        actor Main
          new create(env: Env) =>
            var c = ColourGreen

        PONY
      rule in_main("c = Colour::Green\ncase c in\nwhen Colour::Red then 1\nend"), <<-'PONY'
        actor Main
          new create(env: Env) =>
            var c = ColourGreen
            match \exhaustive\ c
            | let _: ColourRed =>
              1
            end

        PONY
    end

    it "emits a predicate per member" do
      rule "enum Colour\n  Red\n  DarkGreen\nend\n", <<-PONY
        primitive ColourRed
          fun value(): I32 => 0
          fun string(): String iso^ => "Red".clone()
          fun eq(that: Colour): Bool => that is this
          fun ne(that: Colour): Bool => not (that is this)
          fun is_red(): Bool => true
          fun is_dark_green(): Bool => false

        primitive ColourDarkGreen
          fun value(): I32 => 1
          fun string(): String iso^ => "DarkGreen".clone()
          fun eq(that: Colour): Bool => that is this
          fun ne(that: Colour): Bool => not (that is this)
          fun is_red(): Bool => false
          fun is_dark_green(): Bool => true

        type Colour is (ColourRed | ColourDarkGreen)

        PONY
      Emitter.predicate("DarkGreen").should eq "dark_green?"
    end

    it "emits when .red? as the member's pattern" do
      src = "enum Light\n  Red\nend\nactor Main\n  def self.new(env : Env)\n    case Light::Red in\n    when .red? then 1\n    end\n  end\nend\n"
      rule src, <<-'PONY'
        primitive LightRed
          fun value(): I32 => 0
          fun string(): String iso^ => "Red".clone()
          fun eq(that: Light): Bool => that is this
          fun ne(that: Light): Bool => not (that is this)
          fun is_red(): Bool => true

        type Light is (LightRed)

        actor Main
          new create(env: Env) =>
            match \exhaustive\ LightRed
            | let _: LightRed =>
              1
            end

        PONY
    end

    it "rejects a predicate pattern that is unknown, ambiguous or lacks ?" do
      enums = "enum Light\n  Red\nend\nenum Signal\n  Red\nend\n"
      main = ->(pattern : String) { "actor Main\n  def self.new(env : Env)\n    case 1\n    when #{pattern} then 1\n    end\n  end\nend\n" }
      expect_raises(ParseError, "no enum member has the predicate `.blue?`") { translate("enum Light\n  Red\nend\n" + main.call(".blue?")) }
      expect_raises(ParseError, "`.red?` names a member of several enums (Light::Red, Signal::Red); write the member instead") { translate(enums + main.call(".red?")) }
      expect_raises(ParseError, "only enum predicates such as `.red?` can be patterns") { translate("enum Light\n  Red\nend\n" + main.call(".red")) }
    end

    it "parenthesises a single member" do
      rule "enum Solo\n  Only\nend\n", <<-PONY
        primitive SoloOnly
          fun value(): I32 => 0
          fun string(): String iso^ => "Only".clone()
          fun eq(that: Solo): Bool => that is this
          fun ne(that: Solo): Bool => not (that is this)
          fun is_only(): Bool => true

        type Solo is (SoloOnly)

        PONY
    end

    it "maps Pony member names back" do
      names = Emitter.enum_names([Parser.parse("enum Colour\n  Red\nend\n")])
      names.should eq({"ColourRed" => "Colour::Red"})
    end
  end

  describe "bare dot-names" do
    it "emits a field read unless the position is a known call" do
      rule in_main("x.size"), <<-PONY
        actor Main
          new create(env: Env) =>
            x().size

        PONY
      rule in_main("x.size"), <<-PONY, Set{ {3, 7} }
        actor Main
          new create(env: Env) =>
            x().size()

        PONY
    end

    it "keeps calls that cannot be fields" do
      rule in_main("x.size!\nx.empty?\nx.f(1)\nx.f()\nFoo.new\nFoo.bar"), <<-PONY
        actor Main
          new create(env: Env) =>
            x().size()?
            x().is_empty()
            x().f(1)
            x().f()
            Foo.create()
            Foo.bar()

        PONY
    end

    it "emits an explicit field read" do
      rule in_main("x.@out"), <<-PONY
        actor Main
          new create(env: Env) =>
            x().out

        PONY
    end
  end

  describe "types and aliases" do
    it "nests unions of three types" do
      rule "alias T = A | B | C\n", <<-PONY
        type T is (A | B | C)

        PONY
    end

    it "joins several includes with &" do
      rule "class Foo\n  include A\n  include B\n  include C\nend\n", <<-PONY
        class Foo is (A & B & C)
          new create() =>
            None

        PONY
    end
  end
end
