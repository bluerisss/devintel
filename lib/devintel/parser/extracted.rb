# frozen_string_literal: true

module DevIntel
  module Parser
    # A definition observed directly in source. Always a FACT: every field comes
    # from the AST, nothing is inferred.
    #
    # `qualified_name` uses Ruby's own notation so it reads the way a developer
    # would write it: "Billing::Invoice", "Billing::Invoice#total" for an
    # instance method, "Billing::Invoice.create" for a singleton method.
    #
    # Written as a subclass of Data so that the constants below land on this
    # class rather than on the enclosing module.
    class ExtractedSymbol < Data.define(:type, :name, :qualified_name, :line_start, :line_end)
      CLASS            = "class"
      MODULE           = "module"
      METHOD           = "method"
      SINGLETON_METHOD = "singleton_method"
      CONSTANT         = "constant"

      TYPES = [CLASS, MODULE, METHOD, SINGLETON_METHOD, CONSTANT].freeze
    end

    # Something a definition names: a superclass, a mixin, a method call or a
    # constant it uses.
    #
    # The extractor records only what the source says; it does not decide what
    # the name points at, because that needs the whole index. Graph::Resolver
    # does that afterwards and assigns the `resolution` stored in the database.
    #
    # The invariant that keeps this honest: **a nil `target_name` means the
    # source gave us nothing to name** - `class X < Struct.new(:a)`,
    # `include build_module`, `object.send(method_name)`. Such a reference is
    # recorded as dynamic rather than dropped, so the gap stays visible.
    class ExtractedReference < Data.define(
      :type, :source_index, :source_scope, :receiver_kind, :receiver_name, :target_name, :line
    )
      INHERITS   = "INHERITS"
      INCLUDES   = "INCLUDES"
      EXTENDS    = "EXTENDS"
      PREPENDS   = "PREPENDS"
      CALLS      = "CALLS"
      REFERENCES = "REFERENCES"

      TYPES = [INHERITS, INCLUDES, EXTENDS, PREPENDS, CALLS, REFERENCES].freeze

      # How the receiver of a call was written. Only meaningful for CALLS.
      SELF     = "self"     # `charge(x)` or `self.charge(x)`
      CONSTANT = "constant" # `PaymentService.charge(x)`
      INSTANCE = "instance" # `PaymentService.new.charge(x)`
      UNKNOWN  = "unknown"  # `service.charge(x)` - receiver's type is not known

      RECEIVER_KINDS = [SELF, CONSTANT, INSTANCE, UNKNOWN].freeze

      def dynamic?
        target_name.nil?
      end
    end

    # Why a file produced no symbols.
    ParseError = Data.define(:message, :line)
  end
end
