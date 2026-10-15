# frozen_string_literal: true

module Services
  class UserService < ApplicationService
    extend Forwardable
    prepend Instrumented

    DEFAULT_ROLE = "member"

    def execute(user)
      user.display_name
    end

    class << self
      def build
        new
      end
    end
  end
end
