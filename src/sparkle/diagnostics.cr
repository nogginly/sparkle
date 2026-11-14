require "./source_map"
require "./pony_type"

module Sparkle
  # A generated Pony file together with what is needed to translate its
  # diagnostics back to Sparkle.
  class GeneratedFile
    getter pony_path : String
    getter spk_path : String
    getter map : SourceMap
    getter source_lines : Array(String)

    def initialize(pony_path : String, @spk_path : String, @map : SourceMap, source : String, base_dir : String = Dir.current)
      @pony_path = File.expand_path(pony_path, base_dir)
      @source_lines = source.lines(chomp: true)
    end
  end

  # Rewrites ponyc output in terms of the Sparkle sources.
  module Diagnostics
    PRIMED   = /'([A-Za-z_][A-Za-z0-9_]*)''/
    LOCATION = /\A(\s*)(.+?):(\d+):(\d+): (.*)\z/
    CARET    = /\A\s*\^\s*\z/

    # Locations in generated files go through the source map, their source
    # excerpt is replaced by the Sparkle line, and Pony types in messages are
    # printed in Sparkle syntax. Other locations keep their file, position and excerpt; only the message is re-printed.
    def self.rewrite(output : String, files : Array(GeneratedFile), base_dir : String = Dir.current, names : Hash(String, String) = {} of String => String) : String
      lines = output.lines(chomp: true)
      by_path = files.to_h { |generated| {generated.pony_path, generated} }
      out = [] of String
      i = 0
      while i < lines.size
        line = lines[i]
        m = LOCATION.match(line)
        unless m
          out << text(line, names)
          i += 1
          next
        end
        indent, path, row, col, msg = m[1], m[2], m[3].to_i, m[4].to_i, m[5]
        excerpt = i + 2 < lines.size && CARET.matches?(lines[i + 2])
        file = by_path[File.expand_path(path, base_dir)]?
        pos = file.try(&.map.lookup(row, col))
        if file && pos
          sl, sc = pos
          out << "#{indent}#{file.spk_path}:#{sl}:#{sc}: #{text(msg, names)}"
          if excerpt
            src = file.source_lines[sl - 1]? || ""
            out << indent + src
            out << indent + caret_padding(src, sc) + "^"
          end
        else
          out << "#{indent}#{path}:#{row}:#{col}: #{text(msg, names)}"
          if excerpt
            out << lines[i + 1]
            out << lines[i + 2]
          end
        end
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
