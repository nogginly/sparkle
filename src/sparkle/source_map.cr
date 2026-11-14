module Sparkle
  # Maps positions in generated Pony back to Sparkle positions. Marks are
  # recorded in emission order, so they are sorted by Pony position.
  class SourceMap
    record Mark, pony_line : Int32, pony_col : Int32, line : Int32, col : Int32

    getter marks = [] of Mark

    def add(pony_line : Int32, pony_col : Int32, line : Int32, col : Int32) : Nil
      if (last = @marks.last?) && last.pony_line == pony_line && last.pony_col == pony_col
        @marks[-1] = Mark.new(pony_line, pony_col, line, col)
      else
        @marks << Mark.new(pony_line, pony_col, line, col)
      end
    end

    # The Sparkle position of the last mark at or before the Pony position.
    def lookup(pony_line : Int32, pony_col : Int32) : {Int32, Int32}?
      idx = @marks.bsearch_index { |m| m.pony_line > pony_line || (m.pony_line == pony_line && m.pony_col > pony_col) }
      idx = @marks.size if idx.nil?
      return nil if idx == 0
      m = @marks[idx - 1]
      {m.line, m.col}
    end
  end
end
