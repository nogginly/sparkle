require "./lib_ponyc"

module Sparkle::Ponyc
  # Compiles the Pony package in `dir` into the binary `out_dir/bin_name`,
  # using the standard library of the Pony installation at `home`.
  # Returns whether it succeeded and ponyc's error text.
  def self.compile(dir : String, out_dir : String, bin_name : String, home : String) : {Bool, String}
    search = {File.join(home, "packages"), File.join(home, "lib", LIB_ARCH)}.join(Process::PATH_DELIMITER)
    opt = LibPonyc.spk_opt_new(out_dir, bin_name, search)
    ok = LibPonyc.ponyc_init(opt)
    if ok
      program = LibPonyc.program_load(File.expand_path(dir), opt)
      ok = !program.null? && LibPonyc.generate_passes(program, opt)
      LibPonyc.ast_free(program) unless program.null?
    end
    text = LibPonyc.spk_errors_text(opt)
    errors = text.null? ? "" : String.new(text)
    LibC.free(text.as(Void*)) unless text.null?
    LibPonyc.ponyc_shutdown(opt)
    LibPonyc.spk_opt_free(opt)
    {ok, errors}
  end
end
