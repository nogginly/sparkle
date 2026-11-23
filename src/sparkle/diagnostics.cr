require "./pony_type"

module Sparkle
  # Rewrites ponyc output in terms of the Sparkle sources.
  module Diagnostics
    PRIMED   = /'([A-Za-z_][A-Za-z0-9_]*)''/
    LOCATION = /\A(\s*)(.+?):(\d+):(\d+): (.*)\z/
    CARET    = /\A\s*\^\s*\z/

    # Re-prints each message of ponyc's `output` in Sparkle terms: Pony types
    # in Sparkle syntax, primed names unprimed, and the enum `names` mapped
    # back. Locations, source excerpts and caret lines pass through untouched.
    def self.rewrite(output : String, names : Hash(String, String) = {} of String => String) : String
      lines = output.lines(chomp: true)
      out = [] of String
      i = 0
      while i < lines.size
        m = LOCATION.match(lines[i])
        unless m
          out << text(lines[i], names)
          i += 1
          next
        end
        out << "#{m[1]}#{m[2]}:#{m[3]}:#{m[4]}: #{text(m[5], names)}"
        excerpt = i + 2 < lines.size && CARET.matches?(lines[i + 2])
        out << lines[i + 1] << lines[i + 2] if excerpt
        i += excerpt ? 3 : 1
      end
      text = out.join('\n')
      output.ends_with?('\n') ? text + "\n" : text
    end

    private def self.text(s : String, names : Hash(String, String)) : String
      PonyType.rewrite(s).gsub(PRIMED, "'\\1'").gsub(/\b[A-Z][A-Za-z0-9_]*\b/) { |word| names[word]? || word }
    end

    # Whitespace that places a caret under column `col` of `src`.
    def self.caret_padding(src : String, col : Int32) : String
      String.build do |buffer|
        src.each_char.first(col - 1).each { |char| buffer << (char == '\t' ? '\t' : ' ') }
        buffer << " " * (col - 1 - src.size) if col - 1 > src.size
      end
    end
  end
end
