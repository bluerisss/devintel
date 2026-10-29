# frozen_string_literal: true

module DevIntel
  module Graph
    # Which referencing files count as tests.
    #
    # A spec earns the link by *referencing* the symbol — that part is a fact
    # read from the source. Deciding that `spec/services/foo_spec.rb` is a test
    # is a convention, and conventions belong in one place so that `trace` and
    # `impact` cannot disagree about what a test is.
    module TestFiles
      PATH = %r{(\A|/)(spec|test)/|_spec\.rb\z|_test\.rb\z}

      # A file that exercises a symbol, plus how we know.
      TestFile = Data.define(:path, :line, :type)

      def self.test?(path)
        PATH.match?(path)
      end

      # @param edges [Array<SymbolGraph::Edge>] references pointing at a symbol
      # @return [Array<TestFile>] one per file, at its first reference
      def self.from(edges)
        edges.select { |edge| test?(edge.path) }
             .group_by(&:path)
             .map { |path, found| TestFile.new(path: path, line: found.first.line, type: found.first.type) }
      end
    end
  end
end
