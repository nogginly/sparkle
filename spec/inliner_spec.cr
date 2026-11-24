require "./spec_helper"

include Sparkle

private INLINER_HOME = Driver.find_pony_home(exe_path: File.join(ROOT, "bin", "sparkle"), cwd: ROOT)

# The lowered tree of `sparkle`, with its yielding methods inlined.
private def inlined(sparkle : String) : {Int32, String}
  dir = File.tempname("inliner")
  Dir.mkdir_p(dir)
  File.write(File.join(dir, "main.spk"), sparkle)
  err = IO::Memory.new
  code, text = Driver.tree_text(dir, err)
  {code, text || err.to_s}
ensure
  FileUtils.rm_rf(dir) if dir
end

# ponyc's parse of `pony`, as a package of its own.
private def parsed(pony : String, home : String) : String
  dir = File.tempname("inliner")
  Dir.mkdir_p(dir)
  File.write(File.join(dir, "main.pony"), pony)
  Ponyc.parse_text(dir, home)
ensure
  FileUtils.rm_rf(dir) if dir
end

private BAG = <<-SPK
  class Bag
    @items : Array(UInt32)

    def self.new
      @items = [] of UInt32
    end

    def each_item
      @items.each do |x|
        yield x
      end
    end
  end

  SPK

describe Inliner do
  if home = INLINER_HOME
    it "replaces a call with a block by a copy of the yielding method" do
      code, tree = inlined(BAG + <<-SPK)
        actor Main
          def self.new(env : Env)
            bag = Bag.new
            total : UInt32 = 0
            bag.each_item do |v|
              total += v
            end
          end
        end
        SPK
      code.should eq(0), tree
      tree.should eq parsed(<<-PONY, home)
        class Bag
          var _items: Array[U32]

          new create() =>
            _items = Array[U32].create()

          fun _yf_items(): this->Array[U32] =>
            _items

        actor Main
          new create(env: Env) =>
            var bag = Bag.create()
            var total: U32 = 0
            var y1_self = bag
            for y1_x in y1_self._yf_items().values() do
              var v = y1_x
              total = total + v
            end

        PONY
    end

    it "inlines a call on self, and leaves each on an Array a loop" do
      code, tree = inlined(BAG.sub("  def each_item", "  def size : USize\n    n : USize = 0\n    each_item do |x|\n      n += 1\n    end\n    n\n  end\n\n  def each_item") + <<-SPK)
        actor Main
          def self.new(env : Env)
            [1, 2].each do |n|
              n
            end
          end
        end
        SPK
      code.should eq(0), tree
      tree.should contain "(id y1_self)"
      tree.should contain "(id values)"
      tree.should_not contain "each_item"
    end

    it "refuses a yielding method that reaches itself" do
      code, out = inlined(<<-SPK)
        class Tree
          def walk
            walk do |x|
              yield x
            end
          end
        end

        actor Main
          def self.new(env : Env)
            Tree.new.walk do |x|
              x
            end
          end
        end
        SPK
      code.should eq 1
      out.should contain "`walk` reaches itself"
    end

    it "says next in a block passed to a yielding method is not supported yet" do
      code, out = inlined(BAG + <<-SPK)
        actor Main
          def self.new(env : Env)
            Bag.new.each_item do |v|
              next
            end
          end
        end
        SPK
      code.should eq 1
      out.should contain "`next` in a block passed to a yielding method is not supported yet"
    end

    it "refuses a block with more parameters than yield passes" do
      code, out = inlined(BAG + <<-SPK)
        actor Main
          def self.new(env : Env)
            Bag.new.each_item do |v, w|
              v
            end
          end
        end
        SPK
      code.should eq 1
      out.should contain "the block takes 2 parameters, but `yield` passes 1"
    end

    it "reports an error in the copy at the yielding method's line" do
      err = IO::Memory.new
      dir = File.tempname("inliner")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "main.spk"), BAG.sub("yield x", "yield x.nope") + "actor Main\n  def self.new(env : Env)\n    Bag.new.each_item do |v|\n      v\n    end\n  end\nend\n")
        Driver.check(dir, err).should eq 1
      ensure
        FileUtils.rm_rf(dir)
      end
      text = err.to_s
      text.should contain "main.spk:10:"
      text.should contain "in the copy inlined at"
    end
  else
    pending "inlines yield (ponyc not found)"
  end
end
