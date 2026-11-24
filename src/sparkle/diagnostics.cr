require "./pony_type"
require "./inliner"

module Sparkle
  # Rewrites ponyc output in terms of the Sparkle sources.
  module Diagnostics
    PRIMED   = /'([A-Za-z_][A-Za-z0-9_]*)''/
    LOCATION = /\A(\s*)(.+?):(\d+):(\d+): (.*)\z/
    CARET    = /\A\s*\^\s*\z/
    INLINED  = /\by\d+_(?=[a-z_])/

    # Re-prints each message of ponyc's `output` in Sparkle terms: Pony types
    # in Sparkle syntax, primed names unprimed, the enum `names` mapped back,
    # and the prefixes of inlined names (`y1_x`) dropped. A location in code
    # copied by the `Inliner` is moved to the yielding method's own line, from
    # `origins`, quoting it from `sources`, with a note giving the call. Other
    # locations, excerpts and caret lines pass through untouched.
    def self.rewrite(output : String, names : Hash(String, String) = {} of String => String, origins : Hash({String, Int32, Int32}, Inliner::Origin) = {} of {String, Int32, Int32} => Inliner::Origin, sources : Hash(String, String) = {} of String => String) : String
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
        excerpt = i + 2 < lines.size && CARET.matches?(lines[i + 2])
        indent = m[1]
        if origin = origins[{m[2], m[3].to_i, m[4].to_i}]?
          out << "#{indent}#{origin.file}:#{origin.line}:#{origin.col}: #{text(m[5], names)}"
          if excerpt
            src = sources[origin.file]?.try(&.lines(chomp: true)[origin.line - 1]?) || ""
            out << indent + src << indent + caret_padding(src, origin.col) + "^"
          end
          out << "#{indent}    in the copy inlined at #{origin.call_file}:#{origin.call_line}:#{origin.call_col}"
        else
          out << "#{indent}#{m[2]}:#{m[3]}:#{m[4]}: #{text(m[5], names)}"
          out << lines[i + 1] << lines[i + 2] if excerpt
        end
        i += excerpt ? 3 : 1
      end
      text = out.join('\n')
      output.ends_with?('\n') ? text + "\n" : text
    end

    private def self.text(s : String, names : Hash(String, String)) : String
      PonyType.rewrite(s).gsub(PRIMED, "'\\1'").gsub(INLINED, "").gsub(/\b[A-Z][A-Za-z0-9_]*\b/) { |word| names[word]? || word }
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
