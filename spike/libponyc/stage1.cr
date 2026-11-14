require "./libponyc"

opt = LibPonyc.spk_opt_new(".", "hello")
puts "ponyc_init: #{LibPonyc.ponyc_init(opt)}"
LibPonyc.ponyc_shutdown(opt)
LibPonyc.spk_opt_free(opt)
puts "shut down"
