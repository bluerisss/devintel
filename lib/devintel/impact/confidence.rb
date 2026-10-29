# frozen_string_literal: true

module DevIntel
  module Impact
    # How sure DevIntel is that a symbol is really affected.
    #
    # Deliberately separate from risk, which is about how dangerous a change
    # is. A change can be dangerous and certain, or dangerous and a guess, and
    # collapsing the two into one number would hide which.
    #
    # The rule is one line so it can be argued with: **one point per step away
    # from the change, plus one if any step on the path was inferred rather
    # than observed.**
    #
    #   1  HIGH    a direct call, observed in the source
    #   2  MEDIUM  a direct call through an inferred receiver, or two
    #              observed steps
    #   3+ LOW     further away, or inference compounded by distance
    #
    # Distance counts because each hop is a place the change can be absorbed:
    # if A calls B calls C and C changed, B may well handle it.
    module Confidence
      HIGH   = "HIGH"
      MEDIUM = "MEDIUM"
      LOW    = "LOW"

      LEVELS = [HIGH, MEDIUM, LOW].freeze

      RULE = "one point per step from the change, plus one if any step was inferred"

      def self.for(depth:, inferred:)
        LEVELS[[depth + (inferred ? 1 : 0), LEVELS.size].min - 1]
      end
    end
  end
end
