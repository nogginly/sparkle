require "./spec_helper"

include Sparkle

private def body(src : String) : String
  main_body(src).join("\n")
end

private def decl(src : String) : String
  translate(src)
end

private def bare_body(statement : String, calls_at_name : Bool = false) : String
  src = "actor Main\n  def self.new(env : Env)\n    #{statement}\n  end\nend\n"
  program = Parser.parse(src)
  calls = Set({Int32, Int32}).new
  if calls_at_name
    call = program.items[0].as(TypeDecl).methods[0].body.as(Array(Expr))[0].as(Call)
    calls << {call.name_line, call.name_col}
  end
  Emitter.emit(program, calls: calls)[0].lines.skip(2).first.strip
end

describe Emitter do
  describe "declarations" do
    it "maps class forms, includes and aliases" do
      decl("class val Point\nend\n").should contain "class val Point"
      decl("class Box(A : val Stringable)\nend\n").should contain "class Box[A: Stringable val]"
      decl("class Box(A : send)\nend\n").should contain "class Box[A: Any #send]"
      decl("class Foo\n  include A\n  include B\nend\n").should contain "class Foo is (A & B)"
      decl("alias Name = String?\n").should contain "type Name is (String | None)"
    end

    it "writes fields before methods and makes them private" do
      pony = decl("class C\n  def count : UInt64 = @count\n  @count : UInt64 = 0\nend\n")
      pony.should eq "class C\n  var _count: U64 = 0\n\n  new create() =>\n    None\n\n  fun count(): U64 =>\n    _count\n"
    end

    it "adds an explicit create to classes without constructors" do
      decl("class C\nend\n").should eq "class C\n  new create() =>\n    None\n"
      decl("class C\n  def self.new\n  end\nend\n").should_not contain "new create() =>\n    None\n\n"
      decl("actor A\nend\n").should eq "actor A\n"
    end

    it "maps method forms" do
      pony = decl(<<-SPK)
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
      pony.should contain "fun ref push(x: I8, b: U8 = 1) =>\n    None"
      pony.should contain "new create(env: Env) =>"
      pony.should contain "new iso create() =>"
      pony.should contain "new from_pair(a: A) =>"
      pony.should contain "fun first(): A ? =>"
      pony.should contain "fun is_empty(): Bool =>"
      pony.should contain "fun ref set_name(v: A) =>"
      pony.should contain "fun add(o: T): T =>"
      pony.should contain "fun apply(i: USize): A ? =>"
      pony.should contain "fun ref update(i: USize, v: A) =>"
    end

    it "emits abstract methods without bodies and behaviours" do
      pony = decl("trait T\n  abstract def area : F64\nend\nactor A\n  be go(x : iso Array(String))\n  end\nend\n")
      pony.should contain "fun area(): F64\n"
      pony.should contain "be go(x: Array[String] iso) =>"
    end

    it "emits None for empty bodies" do
      decl("class C\n  def f\n  end\nend\n").should contain "fun f() =>\n    None"
    end

    it "adds use \"collections\" when ranges are used" do
      translate("actor Main\n  def self.new(env : Env)\n    (1..3).each do |i|\n    end\n  end\nend\n").should start_with %(use "collections")
    end

    it "keeps an existing use of collections once" do
      pony = translate("use \"collections\"\nactor Main\n  def self.new(env : Env)\n    3.times do\n    end\n  end\nend\n")
      pony.scan(%(use "collections")).size.should eq 1
    end
  end

  describe "names, fields and calls" do
    it "decides var versus assignment from scope" do
      body("x = 1\nx = 2").should eq "new create(env: Env) =>\n    var x: I32 = 1\n    x = 2"
    end

    it "keeps variables first assigned in a branch scoped to it" do
      body("if true\n  y = 1\nend\ny = 2").should contain "var y: I32 = 2"
    end

    it "treats bare names as calls unless local" do
      body("foo\nz = 1\nz").should eq "new create(env: Env) =>\n    foo()\n    var z: I32 = 1\n    z"
    end

    it "emits typed locals, self, instance variables and field reads" do
      pony = decl("class C\n  @n : U8 = 0\n  def f(o : C, env : Env)\n    x : UInt8 = 1\n    self\n    @n\n    o.@n\n    env.@out\n  end\nend\n")
      pony.should contain "var x: U8 = 1"
      pony.should contain "this\n"
      pony.should contain "o._n"
      pony.should contain "env.out"
    end

    it "emits calls, constructors, named arguments and setters" do
      body("x.size\nFoo.new(1)\nArray(String).new\nf(x: 1)\nf(1, y: 2)\nx.name = 3").should eq <<-PONY.chomp
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
      body("a = [1]\na[0]\na[0]!\na[0] = 1\na[0]! = 1\na.first!\na.parse!(s)\na.empty?\na.nil?\na.as!(String)").should contain <<-PONY.chomp
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
      body("a = 0\nb = -1\nc = 1.5\nd = 1_u64\ne = 2.5_f32\nf = a").should eq <<-PONY.chomp
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
      pony = decl("class C\n  @payload : U32\n  def self.new(payload : U32)\n    @payload = payload\n  end\n  def payload : U32 = @payload\n  def g(xs : Array(U32))\n    xs.each do |payload|\n      payload\n    end\n    payload\n    payload = 1\n    payload\n  end\nend\n")
      pony.should contain "new create(payload': U32) =>\n    _payload = payload'"
      pony.should contain "for payload' in xs.values() do\n      payload'\n    end"
      pony.should contain "    payload()\n    var payload': I32 = 1\n    payload'"
    end

    it "escapes Pony reserved words used as names" do
      body("val = 1\nval").should contain "var val_: I32 = 1"
    end
  end

  describe "named arguments" do
    job = "class val Job\n  @payload : UInt32\n  def self.new(payload : UInt32)\n    @payload = payload\n  end\n  def payload : UInt32 = @payload\nend\n"
    main = "actor Main\n  def self.new(env : Env)\n    j = Job.new(payload: 1)\n  end\nend\n"

    it "primes a named argument whose parameter is primed" do
      decl(job + main).should contain "Job.create(where payload' = 1)"
    end

    it "leaves an unmatched named argument alone" do
      body("f(x: 1)").should eq "new create(env: Env) =>\n    f(where x = 1)"
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
      body("a = 1 + 2 * 3 - 4").should contain "var a = (1 + (2 * 3)) - 4"
      body("a = 1\nb = a > 1 && a < 5 || !(a == 3)").should contain "var b = ((a > 1) and (a < 5)) or not (a == 3)"
    end

    it "rewrites << and compound assignment" do
      body("a = 1\nb = []of String\nb << \"x\"\na += 2\na *= 3").should contain "b.push(\"x\")\n    a = a + 2\n    a = a * 3"
    end

    it "emits ternaries and ranges" do
      body("c = true\nx = c ? 1 : 2").should contain "var x = if c then 1 else 2 end"
    end

    it "emits literals" do
      body("a = nil\nb = 1_u64\nc = 2.5_f32\nd = {1, 2}\ne = [1, 2, 3]\nf = [1, 2] of UInt8\ng = [] of String").should eq <<-PONY.chomp
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

    it "emits string interpolation as concatenation" do
      body(%(n = 1\ns = "n = \#{n}!"\nt = "\#{n}"\nu = "plain\\n")).should contain %(var s = "n = " + n.string() + "!")
      body(%(n = 1\nt = "\#{n}")).should contain %(var t = "" + n.string())
      body(%(n = 1\nt = "\#{n + 1}")).should contain %(var t = "" + (n + 1).string())
    end
  end

  describe "control flow" do
    it "emits if, elsif, else and unless" do
      body("if a\n  b\nelsif c\n  d\nelse\n  e\nend").should eq <<-PONY.chomp
        new create(env: Env) =>
            if a() then
              b()
            elseif c() then
              d()
            else
              e()
            end
        PONY
      body("unless a\n  b\nend").should contain "if not (a()) then"
    end

    it "emits postfix modifiers" do
      body("a if b\na unless b").should eq "new create(env: Env) =>\n    if b() then a() end\n    if not (b()) then a() end"
    end

    it "emits loops" do
      body("while a\n  break\nend\nuntil a\n  next\nend\nloop do\n  return 1\nend").should eq <<-PONY.chomp
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
      body("case x\nwhen 1, 2\n  a\nwhen s : String\n  s\nwhen {p, _}\n  b\nelse\n  c\nend").should eq <<-PONY.chomp
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
      body("case x in\nwhen 1\n  a\nend").should contain "match \\exhaustive\\ x()"
    end

    it "emits begin as try" do
      body("begin\n  a\nrescue\n  b\nensure\n  c\nend").should eq <<-PONY.chomp
        new create(env: Env) =>
            try
              a()
            else
              b()
            then
              c()
            end
        PONY
      body("raise").should contain "error"
    end

    it "emits recover and consume" do
      body("x = recover iso do\n  Foo.new\nend\ny = consume x").should eq <<-PONY.chomp
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
      body("xs = [1]\nxs.each do |x|\n  x\nend").should contain "for x in xs.values() do\n      x\n    end"
      body("xs = [1]\nxs.each_with_index do |x, i|\n  x\nend").should contain "for (i, x) in xs.pairs() do"
      body("5.times do |i|\n  i\nend").should contain "for i in Range[USize].till(0, 5) do"
      body("(1...4).each do |i|\n  i\nend").should contain "for i in Range[USize].till(1, 4) do"
      body("(1..4).each do |i|\n  i\nend").should contain "for i in Range[USize].through(1, 4) do"
    end

    it "turns other blocks into lambda arguments" do
      body("a.map do |x|\n  x.size\nend").should contain "a().map({(x) => x.size})"
      body("a.fold(0) { |acc, x| acc + x }").should contain "a().fold(0, {(acc, x) => acc + x})"
      body("a.each_pair do |k, v|\n  k\n  v\nend").should contain "a().each_pair({(k, v) =>\n      k\n      v\n    })"
    end

    it "turns &.name into a lambda" do
      body("a.map(&.size)").should contain "a().map({(x) => x.size()})"
    end

    it "scopes block parameters to the block" do
      body("xs = [1]\nxs.each do |x|\nend\nx = 1").should contain "var x: I32 = 1"
    end
  end

  describe "assignment as a value" do
    it "keeps statements unchanged" do
      body("y = 5\ny = 6").should contain "var y: I32 = 5\n    y = 6"
      body("c = true\nx = 1 if c").should contain "if c then var x: I32 = 1 end"
    end

    it "evaluates to the new value" do
      body("x = (y = 5)").should contain "var x = (var y: I32 = 5; y)"
      body("x = y = 5").should contain "var x = (var y: I32 = 5; y)"
      body("n = 3\nwhile (n -= 1) > 0\n  n\nend").should contain "while (n = n - 1; n) > 0 do"
    end

    it "returns the new value from a method with a return type" do
      decl("class C\n  @n : UInt64 = 0\n  def ref incr : UInt64 = @n += 1\nend\n").should contain "fun ref incr(): U64 =>\n    (_n = _n + 1; _n)"
      decl("class C\n  @n : UInt64 = 0\n  def ref bump = @n += 1\nend\n").should contain "fun ref bump() =>\n    _n = _n + 1"
    end

    it "treats a block's last statement as a statement, since a lambda returns None" do
      body("a = [1]\nf(1) do |v|\n  a[0] = v\nend").should contain "a(0) = v"
      body("a = [1]\nf(1) { |v| a[0] = v }").should contain "a(0) = v}"
    end

    it "rejects the value of an index assignment" do
      expect_raises(ParseError) { translate("actor Main\n  def self.new(env : Env)\n    a = [1]\n    b = (a[0] = 2)\n  end\nend\n") }
    end
  end

  describe "enums" do
    it "emits a primitive per member and a union type" do
      decl("enum Colour\n  Red\n  Green = 5\n  Blue\nend\n").should eq <<-PONY
        primitive ColourRed
          fun value(): I32 => 0
          fun string(): String iso^ => "Red".clone()
          fun eq(that: Colour): Bool => that is this
          fun ne(that: Colour): Bool => not (that is this)

        primitive ColourGreen
          fun value(): I32 => 5
          fun string(): String iso^ => "Green".clone()
          fun eq(that: Colour): Bool => that is this
          fun ne(that: Colour): Bool => not (that is this)

        primitive ColourBlue
          fun value(): I32 => 6
          fun string(): String iso^ => "Blue".clone()
          fun eq(that: Colour): Bool => that is this
          fun ne(that: Colour): Bool => not (that is this)

        type Colour is (ColourRed | ColourGreen | ColourBlue)

        PONY
    end

    it "emits member references and patterns" do
      body("c = Colour::Green").should contain "var c = ColourGreen"
      body("c = Colour::Green\ncase c in\nwhen Colour::Red then 1\nend").should contain "| let _: ColourRed =>"
    end

    it "parenthesises a single member" do
      decl("enum Solo\n  Only\nend\n").should contain "type Solo is (SoloOnly)"
    end

    it "maps Pony member names back" do
      names = Emitter.enum_names([Parser.parse("enum Colour\n  Red\nend\n")])
      names.should eq({"ColourRed" => "Colour::Red"})
    end
  end

  describe "bare dot-names" do
    it "emits a field read unless the position is a known call" do
      bare_body("x.size").should eq "x().size"
      bare_body("x.size", calls_at_name: true).should eq "x().size()"
    end

    it "keeps calls that cannot be fields" do
      bare_body("x.size!").should eq "x().size()?"
      bare_body("x.empty?").should eq "x().is_empty()"
      bare_body("x.f(1)").should eq "x().f(1)"
      bare_body("x.f()").should eq "x().f()"
      bare_body("Foo.new").should eq "Foo.create()"
      bare_body("Foo.bar").should eq "Foo.bar()"
    end

    it "emits an explicit field read" do
      bare_body("x.@out").should eq "x().out"
    end
  end
end
