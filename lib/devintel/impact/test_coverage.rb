# frozen_string_literal: true

module DevIntel
  module Impact
    # Which test files name a symbol.
    #
    # "Named by a test" is not the same as "tested": a spec may exercise a
    # method through something else entirely, and naming it proves only that
    # the file mentions it. It is still the best static signal available for
    # where to look, and the wording in the output says exactly that.
    module TestCoverage
      # @return [Array<Array(String, Array<String>)>] test file, and the
      #   symbols from `names` it reaches, so a reader can see why it is here.
      def self.for(names, graph)
        pairs = names.flat_map { |name| naming(name, graph).map { |test| [test.path, name] } }

        pairs.group_by(&:first)
             .transform_values { |found| found.map(&:last).uniq.sort }
             .sort
      end

      # Symbols no test file names. Where to look, not proof of absence.
      def self.untested(symbols, graph)
        symbols.reject { |symbol| naming(symbol.qualified_name, graph).any? }
      end

      # A spec says `RSpec.describe PaymentService`, not
      # `RSpec.describe PaymentService.charge`. Looking only for the method
      # would report a thoroughly tested method as untested, so the class that
      # owns it counts too.
      def self.naming(qualified_name, graph)
        [qualified_name, owner_of(qualified_name)].compact
                                                  .flat_map { |name| Graph::TestFiles.from(graph.callers(name)) }
                                                  .uniq(&:path)
      end

      # "Billing::Invoice#total" and "Billing::Invoice.create" are both owned
      # by "Billing::Invoice". A class or constant has no owner for this
      # purpose: a spec naming `Billing` is not a test for `Billing::Invoice`.
      def self.owner_of(qualified_name)
        separator = qualified_name.rindex(/[#.]/)

        separator.nil? ? nil : qualified_name[0...separator]
      end
    end
  end
end
