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
    LOCATION = /\A(\s*)(.+?):(\d+):(\d+): (.*)\z/
    CARET    = /\A\s*\^\s*\z/

    # Locations in generated files go through the source map, their source
    # excerpt is replaced by the Sparkle line, and Pony types in messages are
    # printed in Sparkle syntax. Other locations pass through unchanged.
    def self.rewrite(output : String, files : Array(GeneratedFile), base_dir : String = Dir.current) : String
      lines = output.lines(chomp: true)
      by_path = files.to_h { |f| {f.pony_path, f} }
      out = [] of String
      i = 0
      while i < lines.size
        line = lines[i]
        m = LOCATION.match(line)
        unless m
          out << PonyType.rewrite(line)
          i += 1
          next
        end
        indent, path, row, col, msg = m[1], m[2], m[3].to_i, m[4].to_i, m[5]
        excerpt = i + 2 < lines.size && CARET.matches?(lines[i + 2])
        file = by_path[File.expand_path(path, base_dir)]?
        pos = file.try(&.map.lookup(row, col))
        if file && pos
          sl, sc = pos
          out << "#{indent}#{file.spk_path}:#{sl}:#{sc}: #{PonyType.rewrite(msg)}"
          if excerpt
            src = file.source_lines[sl - 1]? || ""
            out << indent + src
            out << indent + caret_padding(src, sc) + "^"
          end
        else
          out << line
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

    # Whitespace that places a caret under column `col` of `src`.
    def self.caret_padding(src : String, col : Int32) : String
      String.build do |s|
        src.each_char.first(col - 1).each { |c| s << (c == '\t' ? '\t' : ' ') }
        s << " " * (col - 1 - src.size) if col - 1 > src.size
      end
    end
  end
end
