# frozen_string_literal: true

require "prism"

module DevIntel
  module Parser
    # Parses one Ruby file into symbols and relationships.
    #
    # Prism is used rather than the running Ruby's own parser: it is error
    # tolerant, it reports locations precisely, and it is decoupled from the
    # Ruby that DevIntel happens to run on, so DevIntel can read syntax from a
    # Ruby version other than its own.
    class RubyParser
      Result = Data.define(:symbols, :references, :errors) do
        def failed?
          !errors.empty?
        end
      end

      EMPTY = Result.new(symbols: [], references: [], errors: []).freeze

      def self.parse_file(path)
        from(Prism.parse_file(path.to_s))
      end

      def self.parse(source)
        from(Prism.parse(source))
      end

      # A file that does not parse yields no symbols at all. Prism can return a
      # partial tree, but definitions recovered from broken syntax are a guess
      # about what the author meant, and the index must not contain guesses.
      def self.from(parse_result)
        if parse_result.failure?
          return Result.new(symbols: [], references: [], errors: errors_from(parse_result))
        end

        extracted = SymbolExtractor.call(parse_result.value)
        Result.new(symbols: extracted.symbols, references: extracted.references, errors: [])
      end
      private_class_method :from

      def self.errors_from(parse_result)
        parse_result.errors.map do |error|
          ParseError.new(message: error.message, line: error.location.start_line)
        end
      end
      private_class_method :errors_from
    end
  end
end
