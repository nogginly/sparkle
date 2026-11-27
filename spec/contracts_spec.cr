require "./spec_helper"

include Sparkle

private SUPPORT_USES = <<-PONY
  use @fprintf[I32](stream: Pointer[U8] tag, fmt: Pointer[U8] tag, ...)
  use @pony_os_stderr[Pointer[U8]]()
  use @exit[None](status: I32)

  PONY

private SUPPORT = <<-'PONY'

  primitive _SpkContract
    fun fail(message: String) =>
      @fprintf(@pony_os_stderr(), "%s\n".cstring(), message.cstring())
      @exit(I32(1))

    fun keep(value: Any val) =>
      None

  PONY

private def contracted(source : String, all : Bool = true) : Program
  program = Parser.parse(source)
  Contracts.support(program) if Contracts.apply(program, "main.spk", all: all)
  program
end

# Pins how clauses lower: `sparkle`, its contracts applied, lowers to the
# Pony `members` of one type, with the support declarations around them.
private def contract_rule(sparkle : String, pony : String, all : Bool = true) : Nil
  program = contracted(sparkle, all)
  full = program.items.any?(ContractSupport) ? SUPPORT_USES + pony + SUPPORT : pony
  lowers_as(program, sparkle, full, primed: Rules.primed_params([program]))
end

private def contract_error(source : String) : String
  contracted(source)
  raise "expected an error"
rescue e : ParseError
  "#{e.line}:#{e.col}: #{e.message}"
end

describe Contracts do
  describe "parsing" do
    it "reads clauses with their text and position" do
      source = <<-SPK
        class Account
          maintains @balance >= 0 # never negative

          @balance : Int64 = 0

          def ref withdraw(amount : Int64) : Int64
            expects amount > 0, amount <= @balance
            guarantees @balance == old(@balance) - amount,
              result == amount

            @balance -= amount
            amount
          end
        end
        SPK
      decl = Parser.parse(source).items[0].as(TypeDecl)
      decl.maintains.map { |clause| {clause.kind, clause.text, clause.line, clause.col} }.should eq [{"maintains", "@balance >= 0", 2, 13}]
      m = decl.methods[0]
      m.expects.map { |clause| {clause.text, clause.line, clause.col} }.should eq [{"amount > 0", 7, 13}, {"amount <= @balance", 7, 25}]
      m.guarantees.map { |clause| {clause.text, clause.line, clause.col} }.should eq [{"@balance == old(@balance) - amount", 8, 16}, {"result == amount", 9, 7}]
      m.guarantees[0].cond.as(Binary).left.should be_a IVarRef
      m.guarantees[0].cond.as(Binary).right.as(Binary).left.should be_a Old
      m.guarantees[1].cond.as(Binary).left.should be_a ResultRef
      m.body.try(&.size).should eq 2
    end

    it "reads old and result as names outside guarantees" do
      m = Parser.parse("class C\n  def f(old : U8) : U8\n    result = old\n    result\n  end\nend\n").items[0].as(TypeDecl).methods[0]
      m.body.try(&.first.as(Assign).value).should be_a Ident
    end

    it "rejects clauses out of place" do
      bad = {
        "class C\n  def f\n    x = 1\n    expects x > 0\n  end\nend\n"          => "4:5: `expects` must open a `def` or `be`, before its body",
        "class C\n  def f\n    guarantees true\n    expects true\n  end\nend\n" => "4:5: `expects` must come before `guarantees`",
        "class C\n  @a : U8 = 0\n  maintains @a == 0\nend\n"                    => "3:3: `maintains` must come before the fields and methods of class C",
        "class C\n  def f(x : U8)\n    expects old(x) > 0\n  end\nend\n"        => "3:13: `old` is only allowed in `guarantees`",
        "class C\n  maintains result\nend\n"                                    => "2:13: `result` is only allowed in `guarantees`",
        "class C\n  def f\n    maintains true\n  end\nend\n"                    => "3:5: `maintains` must open a type, before its fields and methods",
        "class C\n  def f(x : U8)\n    expects x > 0 x\n  end\nend\n"           => "3:19: unexpected 'x'",
      }
      bad.each do |source, message|
        expect_raises(ParseError) { Parser.parse(source) }.try { |e| "#{e.line}:#{e.col}: #{e.message}" }.should eq message
      end
    end
  end

  describe "lowering" do
    it "wraps a method: checks around the renamed body" do
      contract_rule <<-SPK, <<-PONY
        class C
          @n : Int32 = 0

          def ref bump(by : Int32) : Int32
            expects by > 0
            guarantees result == old(@n) + by
            @n += by
            @n
          end
        end
        SPK
        class C
          var _n: I32 = 0

          new create() =>
            None

          fun ref bump(by: I32): I32 =>
            var spk_view: C box = this
            var spk_arg_by: box->I32 = by
            if not (spk_arg_by > 0) then _SpkContract.fail("main.spk:5:13: contract failed in C.bump: expects by > 0") end
            var spk_old_1 = spk_view._n
            _SpkContract.keep(spk_old_1)
            var spk_result = _spk_bump(by)
            var spk_result_view: box->I32 = spk_result
            if not (spk_result_view == (spk_old_1 + spk_arg_by)) then _SpkContract.fail("main.spk:6:16: contract failed in C.bump: guarantees result == old(@n) + by") end
            consume spk_result

          fun ref _spk_bump(by: I32): I32 =>
            _n = _n + by
            _n
        PONY
    end

    it "reads self, fields and calls on self through the box view" do
      contract_rule <<-SPK, <<-PONY
        class C(A : val)
          @items : Array(A) = [] of A

          def size : USize = @items.size

          def ref push(x : iso String)
            expects size < 3, self.size == @items.size
            @items.size
          end
        end
        SPK
        class C[A: Any val]
          var _items: Array[A] = Array[A].create()

          new create() =>
            None

          fun size(): USize =>
            _items.size

          fun ref push(x: String iso) =>
            var spk_view: C[A] box = this
            if not (spk_view.size() < 3) then _SpkContract.fail("main.spk:7:13: contract failed in C.push: expects size < 3") end
            if not (spk_view.size == spk_view._items.size) then _SpkContract.fail("main.spk:7:23: contract failed in C.push: expects self.size == @items.size") end
            _spk_push(consume x)

          fun ref _spk_push(x: String iso) =>
            _items.size
        PONY
    end

    it "checks a constructor before and after its body, and maintains after" do
      contract_rule <<-SPK, <<-PONY
        class C
          maintains @n >= 0

          @n : Int32

          def self.new(n : Int32)
            expects n > 0
            guarantees @n == n
            @n = n
          end

          def get : Int32 = @n
        end
        SPK
        class C
          var _n: I32

          new create(n: I32) =>
            var spk_arg_n: box->I32 = n
            if not (spk_arg_n > 0) then _SpkContract.fail("main.spk:7:13: contract failed in C.new: expects n > 0") end
            _n = n
            var spk_view: C box = this
            if not (spk_view._n == spk_arg_n) then _SpkContract.fail("main.spk:8:16: contract failed in C.new: guarantees @n == n") end
            _spk_maintains("C.new")

          fun get(): I32 =>
            _n

          fun box _spk_maintains(spk_after: String) =>
            if not (_n >= 0) then _SpkContract.fail("main.spk:2:13: contract failed after " + spk_after.string() + ": maintains @n >= 0") end
        PONY
    end

    it "checks maintains after public ref methods and message handlers only" do
      contract_rule <<-SPK, <<-PONY
        actor A
          maintains @n < 3

          @n : Int32 = 0

          on bump(by : Int32)
            expects by > 0
            @n += by
          end

          def ref _helper
            @n = 9
          end

          def peek : Int32 = @n
        end
        SPK
        actor A
          var _n: I32 = 0

          be bump(by: I32) =>
            var spk_view: A box = this
            var spk_arg_by: box->I32 = by
            if not (spk_arg_by > 0) then _SpkContract.fail("main.spk:7:13: contract failed in A.bump: expects by > 0") end
            _spk_bump(by)
            _spk_maintains("A.bump")

          fun ref _spk_bump(by: I32) =>
            _n = _n + by

          fun ref _helper() =>
            _n = 9

          fun peek(): I32 =>
            _n

          fun box _spk_maintains(spk_after: String) =>
            if not (_n < 3) then _SpkContract.fail("main.spk:2:13: contract failed after " + spk_after.string() + ": maintains @n < 3") end
        PONY
    end

    it "keeps only expects when not all clauses are kept" do
      contract_rule <<-SPK, <<-PONY, all: false
        class C
          maintains @n >= 0

          @n : Int32 = 0

          def ref set(n : Int32)
            guarantees @n == n
            @n = n
          end
        end
        SPK
        class C
          var _n: I32 = 0

          new create() =>
            None

          fun ref set(n: I32) =>
            _n = n
        PONY
    end

    it "wraps a partial method and calls its body as partial" do
      contract_rule <<-SPK, <<-PONY
        class C
          @items : Array(U8) = [] of U8

          def ref pop! : U8
            expects @items.size > 0
            @items.pop!
          end
        end
        SPK
        class C
          var _items: Array[U8] = Array[U8].create()

          new create() =>
            None

          fun ref pop(): U8 ? =>
            var spk_view: C box = this
            if not (spk_view._items.size > 0) then _SpkContract.fail("main.spk:5:13: contract failed in C.pop!: expects @items.size > 0") end
            var spk_result = _spk_pop()?
            consume spk_result

          fun ref _spk_pop(): U8 ? =>
            _items.pop()?
        PONY
    end
  end

  describe "errors" do
    it "rejects clauses it cannot check yet, or that cannot hold" do
      contract_error("class C\n  def each\n    expects true\n    yield 1\n  end\nend\n").should eq "3:13: clauses on a yielding method are not supported yet"
      contract_error("class C\n  def tag f\n    expects true\n  end\nend\n").should eq "3:13: clauses on a `tag` method are not supported yet"
      contract_error("actor A\n  on go(x : U8)\n    guarantees x == 1\n  end\nend\n").should eq "3:16: a message handler cannot have `guarantees`: no caller sees its end"
      contract_error("class C\n  def ref f(x : U8)\n    guarantees result == 1\n  end\nend\n").should eq "3:16: `result` in a method that returns nothing"
      contract_error("primitive P\n  maintains true\nend\n").should eq "2:13: `maintains` is not supported in a primitive yet"
      contract_error("class C\n  @n : U8 = 0\n  def self.new(n : U8)\n    expects @n == 0\n  end\nend\n").should eq "4:13: a constructor's `expects` can only read its arguments"
      contract_error("class C\n  @n : U8 = 0\n  def self.new(n : U8)\n    guarantees @n == old(@n)\n  end\nend\n").should eq "4:16: `old` cannot be used in a constructor's `guarantees`"
      contract_error("class C\n  @n : U8 = 0\n  def self.new(n : U8)\n    guarantees @n == n\n    return\n  end\nend\n").should eq "5:5: `return` in a constructor with contracts is not supported yet"
    end
  end
end
