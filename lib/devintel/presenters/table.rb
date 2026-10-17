# frozen_string_literal: true

module DevIntel
  module Presenters
    # Lays out fixed-width text columns.
    #
    # Every presenter needs the same thing — pad each column to its widest
    # cell, separate by two spaces, indent, and trim the trailing run — and
    # each had grown its own `format("%-#{width}s")` string. One place to get
    # the arithmetic right is one place to read it.
    module Table
      INDENT = "  "
      GAP = "  "

      LEFT = :left
      RIGHT = :right

      # @param rows [Array<Array<#to_s>>] one array of cells per line
      # @param align [Array<Symbol>, nil] per column; defaults to left
      # @return [Array<String>]
      def self.rows(rows, align: nil)
        return [] if rows.empty?

        cells = rows.map { |row| row.map(&:to_s) }
        widths = widths_of(cells)

        cells.map { |row| line(row, widths, align) }
      end

      def self.widths_of(cells)
        columns = cells.map(&:size).max

        Array.new(columns) { |index| cells.map { |row| row.fetch(index, "").length }.max }
      end
      private_class_method :widths_of

      def self.line(row, widths, align)
        padded = row.each_with_index.map { |cell, index| pad(cell, widths[index], align&.fetch(index, LEFT)) }

        "#{INDENT}#{padded.join(GAP)}".rstrip
      end
      private_class_method :line

      def self.pad(cell, width, alignment)
        alignment == RIGHT ? cell.rjust(width) : cell.ljust(width)
      end
      private_class_method :pad
    end
  end
end
