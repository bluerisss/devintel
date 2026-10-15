# frozen_string_literal: true

module DevIntel
  module Graph
    # How much DevIntel actually knows about where an edge points.
    #
    # These map onto the evidence model: a FACT was read from the source, an
    # INFERENCE was derived from a known relationship, and UNKNOWN means static
    # analysis could not decide. Keeping them as separate values rather than one
    # score is what stops an inference being reported as a fact later on.
    module Resolution
      # The edge points at a definition in this repository.           FACT
      RESOLVED = "resolved"
      # The target is named, but nothing in this repository defines it
      # (a gem, Rails, Kernel).                                       FACT
      NAMED = "named"
      # The receiver's type was inferred, e.g. `Foo.new.bar` -> `Foo#bar`.
      #                                                               INFERENCE
      INFERRED = "inferred"
      # The receiver is a class in this repository, but it does not define the
      # method called on it: inherited, from a gem, or metaprogrammed. The
      # dependency on the class is still observed.                    FACT
      RECEIVER_ONLY = "receiver_only"
      # The method name is known but not what it was called on.       UNKNOWN
      UNKNOWN_RECEIVER = "unknown_receiver"
      # Nothing could be determined: `object.send(method_name)`.      UNKNOWN
      DYNAMIC = "dynamic"
      # Stored at insert time; every edge is resolved before the run ends.
      PENDING = "pending"

      ALL = [RESOLVED, NAMED, INFERRED, RECEIVER_ONLY, UNKNOWN_RECEIVER, DYNAMIC, PENDING].freeze

      FACT      = [RESOLVED, NAMED, RECEIVER_ONLY].freeze
      INFERENCE = [INFERRED].freeze
      UNKNOWN   = [UNKNOWN_RECEIVER, DYNAMIC].freeze

      # Edges that point at a definition in this repository, and so can be
      # followed. The rest are real relationships DevIntel cannot trace further.
      TRACEABLE = [RESOLVED, INFERRED, RECEIVER_ONLY].freeze

      def self.evidence_class(resolution)
        return "FACT" if FACT.include?(resolution)
        return "INFERENCE" if INFERENCE.include?(resolution)

        "UNKNOWN"
      end

      def self.traceable?(resolution)
        TRACEABLE.include?(resolution)
      end
    end
  end
end
