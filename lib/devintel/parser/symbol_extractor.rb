# frozen_string_literal: true

require "prism"

module DevIntel
  module Parser
    # Walks a Prism AST and collects the definitions and relationships it states
    # outright.
    #
    # The rule this class follows is that it only records what the source
    # literally says. Ruby is dynamic: `define_method`, `send`, `eval` and
    # Rails' own metaprogramming create methods that no static pass can see.
    # Those are left out, or recorded as dynamic, rather than guessed at —
    # a fabricated symbol is worse than a missing one, because later milestones
    # cite symbols as evidence.
    class SymbolExtractor < Prism::Visitor
      Result = Data.define(:symbols, :references)

      MIXIN_TYPES = {
        include: ExtractedReference::INCLUDES,
        extend: ExtractedReference::EXTENDS,
        prepend: ExtractedReference::PREPENDS
      }.freeze

      def self.call(node)
        extractor = new
        node.accept(extractor)
        extractor.result
      end

      def initialize
        super
        @scope = Scope.new
        @symbols = []
        @references = []
      end

      def result
        Result.new(symbols: @symbols.freeze, references: @references.freeze)
      end

      def visit_class_node(node)
        path = Constants.name_of(node.constant_path)
        return visit_child_nodes(node) if path.nil?

        index = add_symbol(ExtractedSymbol::CLASS, path, node)
        @scope.descend(path, index) do
          record_superclass(node)
          node.body&.accept(self)
        end
      end

      def visit_module_node(node)
        path = Constants.name_of(node.constant_path)
        return visit_child_nodes(node) if path.nil?

        index = add_symbol(ExtractedSymbol::MODULE, path, node)
        @scope.descend(path, index) { node.body&.accept(self) }
      end

      def visit_def_node(node)
        type, qualified_name = MethodNaming.call(node, @scope, singleton: @scope.singleton?)
        index = add_symbol(type, node.name.to_s, node, qualified_name: qualified_name)

        # A call inside a method body belongs to that method, not to the class:
        # "who calls PaymentService#charge" must answer with a method.
        @scope.own(index) { node.body&.accept(self) }
      end

      # `class << self` turns the methods in its body into singleton methods.
      def visit_singleton_class_node(node)
        @scope.singleton { node.body&.accept(self) }
      end

      def visit_constant_write_node(node)
        add_symbol(ExtractedSymbol::CONSTANT, node.name.to_s, node)
        node.value&.accept(self)
      end

      # `Billing::LIMIT = 5`
      def visit_constant_path_write_node(node)
        path = Constants.name_of(node.target)
        if path
          add_symbol(ExtractedSymbol::CONSTANT, path.split("::").last, node, qualified_name: qualify(path))
        end
        node.value&.accept(self)
      end

      # A mixin is a *statement* in a body, never an expression nested inside
      # another call. That distinction matters: `expect(x).to include(y)` is a
      # receiverless call named `include` too, and treating it as a mixin would
      # invent relationships that do not exist in the program.
      def visit_statements_node(node)
        node.body.each do |statement|
          type = mixin_type(statement)
          type ? record_mixin(statement, type) : statement.accept(self)
        end
      end

      def visit_call_node(node)
        record_call(node)

        # A constant receiver is already named by the call edge; visiting it
        # again would record the same relationship twice.
        node.receiver&.accept(self) unless constant_receiver?(node)
        node.arguments&.accept(self)
        node.block&.accept(self)
      end

      # A constant used as a value: `RSpec.describe UserService`, `ROLES.first`.
      def visit_constant_read_node(node)
        add_reference(type: ExtractedReference::REFERENCES, target_name: node.name.to_s,
                      line: node.location.start_line)
      end

      def visit_constant_path_node(node)
        add_reference(
          type: ExtractedReference::REFERENCES,
          target_name: Constants.name_of(node),
          line: node.location.start_line
        )
      end

      private

      def add_symbol(type, name, node, qualified_name: nil)
        @symbols << ExtractedSymbol.new(
          type: type,
          name: name.split("::").last,
          qualified_name: qualified_name || qualify(name),
          line_start: node.location.start_line,
          line_end: node.location.end_line
        )
        @symbols.size - 1
      end

      def add_reference(type:, target_name:, line:, receiver_kind: nil, receiver_name: nil)
        @references << ExtractedReference.new(
          type: type,
          source_index: @scope.owner,
          source_scope: @scope.namespace,
          receiver_kind: receiver_kind,
          receiver_name: receiver_name,
          target_name: target_name,
          line: line
        )
      end

      def qualify(name)
        @scope.qualify(name)
      end

      def record_superclass(node)
        superclass = node.superclass
        return if superclass.nil?

        add_reference(
          type: ExtractedReference::INHERITS,
          target_name: Constants.name_of(superclass),
          line: superclass.location.start_line
        )
      end

      # @return [String, nil] the edge type when this statement is a mixin.
      def mixin_type(node)
        return nil unless node.is_a?(Prism::CallNode) && node.receiver.nil?

        MIXIN_TYPES[node.name]
      end

      def record_mixin(node, type)
        arguments = node.arguments&.arguments || []
        arguments.each do |argument|
          add_reference(type: type, target_name: Constants.name_of(argument), line: node.location.start_line)
        end
      end

      def record_call(node)
        call = CallSites.describe(node)
        return if call.nil?

        add_reference(
          type: ExtractedReference::CALLS,
          target_name: call.target_name,
          receiver_kind: call.receiver_kind,
          receiver_name: call.receiver_name,
          line: node.location.start_line
        )
      end

      def constant_receiver?(node)
        node.receiver.is_a?(Prism::ConstantReadNode) || node.receiver.is_a?(Prism::ConstantPathNode)
      end
    end
  end
end
