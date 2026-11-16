# Prints a Crystal enum of ponyc's token ids, read from the `token.h` whose
# path is the only argument. Run at compile time by `lib_ponyc.cr`, so the
# values always match the headers the shim is compiled against.
body = File.read(ARGV[0]).match!(/typedef enum token_id\s*\{(.*?)\}\s*token_id;/m)[1]
puts "enum Sparkle::Ponyc::Tk"
body.scan(/^\s*TK_(\w+)/m).each_with_index { |name, value| puts "  #{name[1]} = #{value}" }
puts "end"
