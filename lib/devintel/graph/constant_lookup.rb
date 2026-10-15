# frozen_string_literal: true

module DevIntel
  module Graph
    # Resolves a constant as written to a definition in the index.
    #
    # Ruby looks a constant up lexically: inside `module A; class B`, the name
    # `C` is searched for as `A::B::C`, then `A::C`, then `C`. This reproduces
    # that walk, and nothing more. In particular it does **not** search a
    # class's ancestors, so a constant inherited from a superclass resolves to
    # nothing rather than to a guess.
    class ConstantLookup
      ROOT_PREFIX = "::"

      # @param known_names [Set<String>, Hash] qualified names present in the index
      def initialize(known_names)
        @known_names = known_names
      end

      # @return [String, nil] the canonical qualified name, or nil if unknown here.
      def call(name, scope)
        return nil if name.nil?
        return rooted(name) if name.start_with?(ROOT_PREFIX)

        candidates(name, scope).find { |candidate| known?(candidate) }
      end

      private

      def rooted(name)
        stripped = name.delete_prefix(ROOT_PREFIX)
        known?(stripped) ? stripped : nil
      end

      # Innermost scope first, exactly as Ruby searches.
      def candidates(name, scope)
        parts = scope.to_s.empty? ? [] : scope.split("::")

        parts.length.downto(0).map { |depth| (parts.first(depth) + [name]).join("::") }
      end

      def known?(name)
        @known_names.include?(name)
      end
    end
  end
end
