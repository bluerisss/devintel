# frozen_string_literal: true

require "prism"

module DevIntel
  module Parser
    # Decides whether a call is worth recording, and how its receiver was written.
    #
    # Ruby makes almost everything a method call — `a + b`, `x[0]`, `obj.name =`
    # — and recording all of them would bury the few edges that carry meaning
    # under arithmetic. The filters here are about signal, not about hiding
    # uncertainty: what they drop is syntax, never a relationship the source
    # actually states.
    module CallSites
      # Operators and setters are excluded by construction: a traceable method
      # reads like an identifier, optionally ending in `?` or `!`.
      TRACEABLE_NAME = /\A[a-zA-Z_][a-zA-Z0-9_]*[?!]?\z/

      # `"text".upcase`, `[].map`, `1.to_s`: the receiver is a literal of a core
      # type, so the call says nothing about this codebase.
      LITERAL_RECEIVERS = [
        Prism::StringNode, Prism::SymbolNode, Prism::IntegerNode, Prism::FloatNode,
        Prism::ArrayNode, Prism::HashNode, Prism::RegularExpressionNode, Prism::RangeNode,
        Prism::NilNode, Prism::TrueNode, Prism::FalseNode, Prism::InterpolatedStringNode
      ].freeze

      # `send(:charge)` names its target in a literal; `send(name)` does not.
      DYNAMIC_DISPATCH = %i[send public_send __send__].freeze

      Call = Data.define(:receiver_kind, :receiver_name, :target_name)

      # @return [Call, nil] nil when the call is not worth an edge.
      def self.describe(node)
        return nil if literal_receiver?(node.receiver)

        DYNAMIC_DISPATCH.include?(node.name) ? dynamic_dispatch(node) : direct_call(node)
      end

      def self.direct_call(node)
        return nil unless TRACEABLE_NAME.match?(node.name.to_s)

        kind, name = receiver(node.receiver)
        Call.new(receiver_kind: kind, receiver_name: name, target_name: node.name.to_s)
      end
      private_class_method :direct_call

      # A dynamic dispatch always produces an edge: an unresolved call is a fact
      # about the program worth seeing, and silence would look like no call.
      def self.dynamic_dispatch(node)
        kind, name = receiver(node.receiver)
        target = node.arguments&.arguments&.first

        literal = target.is_a?(Prism::SymbolNode) ? target.unescaped : nil
        Call.new(receiver_kind: kind, receiver_name: name, target_name: literal)
      end
      private_class_method :dynamic_dispatch

      # @return [Array(String, String|nil)] receiver kind and constant name.
      def self.receiver(node)
        case node
        when nil, Prism::SelfNode
          [ExtractedReference::SELF, nil]
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          name = Constants.name_of(node)
          name ? [ExtractedReference::CONSTANT, name] : [ExtractedReference::UNKNOWN, nil]
        when Prism::CallNode
          instance_receiver(node)
        else
          [ExtractedReference::UNKNOWN, nil]
        end
      end
      private_class_method :receiver

      # `PaymentService.new.charge` - treating the result of `Foo.new` as a Foo
      # is an inference, not an observation, and the edge is labelled as such.
      def self.instance_receiver(node)
        name = node.name == :new ? Constants.name_of(node.receiver) : nil
        return [ExtractedReference::UNKNOWN, nil] if name.nil?

        [ExtractedReference::INSTANCE, name]
      end
      private_class_method :instance_receiver

      def self.literal_receiver?(node)
        LITERAL_RECEIVERS.any? { |type| node.is_a?(type) }
      end
      private_class_method :literal_receiver?
    end
  end
end
