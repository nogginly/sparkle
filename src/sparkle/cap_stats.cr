require "./ast"

module Sparkle
  # Counts capability annotations by position and by capability.
  module CapStats
    POSITIONS = ["type declaration", "def", "type", "recover"]

    class Stats
      getter by_position = Hash(String, Int32).new(0)
      getter by_cap = Hash(String, Int32).new(0)

      def total : Int32
        @by_position.values.sum
      end

      def add(use : CapUse) : Nil
        @by_position[use.position] += 1
        @by_cap[use.cap] += 1
      end

      def merge(other : Stats) : Nil
        other.by_position.each { |k, v| @by_position[k] += v }
        other.by_cap.each { |k, v| @by_cap[k] += v }
      end
    end

    def self.collect(program : Program) : Stats
      stats = Stats.new
      program.cap_uses.each { |cap_use| stats.add(cap_use) }
      stats
    end

    # One block per file, followed by a total when there are several files.
    def self.report(entries : Array({String, Program})) : String
      total = Stats.new
      blocks = entries.map do |(name, program)|
        stats = collect(program)
        total.merge(stats)
        block(name, stats)
      end
      blocks << block("total", total) if entries.size > 1
      blocks.join("\n")
    end

    private def self.block(name : String, stats : Stats) : String
      String.build do |buffer|
        buffer << name << '\n'
        POSITIONS.each do |pos|
          buffer << "  " << pos.ljust(17) << stats.by_position[pos] << '\n'
        end
        buffer << "  " << "total".ljust(17) << stats.total << '\n'
        caps = ALL_CAPS.select { |cap| stats.by_cap[cap] > 0 }.map { |cap| "#{cap} #{stats.by_cap[cap]}" }
        buffer << "  " << "by capability".ljust(17) << (caps.empty? ? "-" : caps.join(", ")) << '\n'
      end
    end
  end
end
