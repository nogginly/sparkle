require "./lib_ponyc"

module Sparkle::Ponyc
  # Compiles the Pony package in `dir` into the binary `out_dir/bin_name`,
  # using the standard library of the Pony installation at `home`.
  # Returns whether it succeeded and ponyc's error text.
  def self.compile(dir : String, out_dir : String, bin_name : String, home : String) : {Bool, String}
    with_options(out_dir, bin_name, home) do |opt|
      program = LibPonyc.program_load(File.expand_path(dir), opt)
      ok = !program.null? && LibPonyc.generate_passes(program, opt)
      LibPonyc.ast_free(program) unless program.null?
      ok
    end
  end

  # Type-checks the package in `dir` without generating code; returns each error's file, line, column and message.
  def self.check(dir : String, home : String) : Array({String, Int32, Int32, String})
    found = [] of {String, Int32, Int32, String}
    with_options("", "check", home) do |opt|
      LibPonyc.spk_opt_set_limit(opt, LibPonyc.spk_pass_expr)
      program = LibPonyc.program_load(File.expand_path(dir), opt)
      LibPonyc.ast_free(program) unless program.null?
      error = LibPonyc.errors_get_first(LibPonyc.spk_opt_errors(opt))
      until error.null?
        msg = error.value
        file = msg.file.null? ? "" : String.new(msg.file)
        found << {file, msg.line.to_i32, msg.pos.to_i32, String.new(msg.msg)}
        error = msg.next
      end
      true
    end
    found
  end

  # Runs the block with initialised compiler options, then tears them down.
  # Returns the block's result (false when initialisation fails) and ponyc's error text.
  private def self.with_options(out_dir : String, bin_name : String, home : String, & : LibPonyc::PassOpt -> Bool) : {Bool, String}
    search = {File.join(home, "packages"), File.join(home, "lib", LIB_ARCH)}.join(Process::PATH_DELIMITER)
    opt = LibPonyc.spk_opt_new(out_dir, bin_name, search)
    ok = LibPonyc.ponyc_init(opt)
    ok = yield opt if ok
    text = LibPonyc.spk_errors_text(opt)
    errors = text.null? ? "" : String.new(text)
    LibC.free(text.as(Void*)) unless text.null?
    LibPonyc.ponyc_shutdown(opt)
    LibPonyc.spk_opt_free(opt)
    {ok, errors}
  end
end
