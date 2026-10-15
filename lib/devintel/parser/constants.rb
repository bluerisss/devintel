# frozen_string_literal: true

require "prism"

module DevIntel
  module Parser
    # Reads a constant's written name out of an AST node.
    module Constants
      # @return [String, nil] the name as written ("A::B", "::Top"), or nil when
      #   any part of the path is computed at runtime (`foo::Bar`) and therefore
      #   cannot be named without guessing.
      def self.name_of(node)
        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode
          path_name(node)
        end
      end

      def self.path_name(node)
        # A nil parent means a root-scoped constant: `::Top`.
        return "::#{node.name}" if node.parent.nil?

        prefix = name_of(node.parent)
        prefix && "#{prefix}::#{node.name}"
      end
      private_class_method :path_name
    end
  end
end
