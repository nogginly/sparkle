# Spike: two Sparkle packages built in memory, one using the other, compiled
# to one binary by the linked-in libponyc. Run: crystal run spike/packages/two.cr
require "../../src/sparkle/driver"

module Spike
  include Sparkle

  GEOMETRY = <<-SPK
    class Point
      @x : Int32

      def self.new(x : Int32)
        @x = x
      end

      def x : Int32 = @x
    end
    SPK

  MAIN = <<-SPK
    use "spk_geometry"

    actor Main
      def self.new(env : Env)
        p = Point.new(7)
        env.out <~ print("x = \#{p.x()}")
      end
    end
    SPK

  def self.lower(tree : Sparkle::Ponyc::Tree, source : String, file : String) : Nil
    Lowerer.new(tree).lower(Parser.parse(source), file, source)
  end

  def self.run : Nil
    home = Driver.find_pony_home || raise "no ponyc"
    out_dir = File.join(Dir.tempdir, "spk-two")
    Dir.mkdir_p(out_dir)
    opt = Sparkle::Ponyc.options(out_dir, "two", home)
    raise "init" unless ::LibPonyc.spk_ponyc_init(opt)
    strtab = ::LibPonyc.spk_opt_strtab(opt)
    main_path = ::LibPonyc.stringtab(strtab, "two")
    dep_path = ::LibPonyc.stringtab(strtab, "spk_geometry")
    ::LibPonyc.module_add_magic_src(main_path, "", opt)
    ::LibPonyc.module_add_magic_src(dep_path, "", opt)
    ::LibPonyc.spk_opt_set_limit(opt, ::LibPonyc.spk_pass_parse)
    program = ::LibPonyc.program_load(main_path, opt)
    raise "load" if program.null?
    dep = ::LibPonyc.spk_module_load_parsed(program, dep_path, opt)
    raise "dep" if dep.null?
    lower(Sparkle::Ponyc::Tree.new(opt, ::LibPonyc.ast_child(::LibPonyc.ast_child(program))), MAIN, "main.spk")
    lower(Sparkle::Ponyc::Tree.new(opt, ::LibPonyc.ast_child(dep)), GEOMETRY, "geometry.spk")
    ::LibPonyc.spk_opt_set_limit(opt, ::LibPonyc.spk_pass_all)
    ok = ::LibPonyc.spk_program_passes(program, opt) && ::LibPonyc.generate_passes(program, opt)
    text = ::LibPonyc.spk_errors_text(opt)
    puts String.new(text) unless text.null?
    puts "compiled: #{ok}"
    system(File.join(out_dir, "two")) if ok
  end
end

Spike.run
