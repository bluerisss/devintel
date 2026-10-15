# frozen_string_literal: true

require "prism"

module DevIntel
  module Parser
    # Decides what a `def` is called and who owns it.
    #
    # Ruby writes the same definition four ways — `def f`, `def self.f`,
    # `class << self; def f; end; end` and `def Foo.f` — and the resulting
    # qualified name differs each time. Keeping that decision in one place
    # stops the visitor from re-deriving it.
    module MethodNaming
      # @param node [Prism::DefNode]
      # @param scope [Scope] the enclosing class/module path
      # @param singleton [Boolean] are we inside `class << self`?
      # @return [Array(String, String)] symbol type and qualified name
      def self.call(node, scope, singleton:)
        type, owner = type_and_owner(node, scope, singleton: singleton)
        [type, qualified_name(type, owner, node.name)]
      end

      def self.type_and_owner(node, scope, singleton:)
        case node.receiver
        when nil
          [singleton ? ExtractedSymbol::SINGLETON_METHOD : ExtractedSymbol::METHOD, scope.namespace]
        when Prism::SelfNode
          [ExtractedSymbol::SINGLETON_METHOD, scope.namespace]
        else
          # `def Foo.bar` or `def obj.bar`: the owner is whatever the source
          # wrote, kept verbatim rather than attributed to the enclosing scope.
          [ExtractedSymbol::SINGLETON_METHOD, Constants.name_of(node.receiver) || node.receiver.slice]
        end
      end
      private_class_method :type_and_owner

      # A top-level `def` has no owner; it stays unqualified rather than being
      # attributed to Object, which is true but never what a reader means.
      def self.qualified_name(type, owner, name)
        return name.to_s if owner.nil? || owner.empty?

        separator = type == ExtractedSymbol::SINGLETON_METHOD ? "." : "#"
        "#{owner}#{separator}#{name}"
      end
      private_class_method :qualified_name
    end
  end
end
