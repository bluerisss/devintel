# frozen_string_literal: true

class User < ApplicationRecord
  include Trackable

  ROLES = %w[admin member].freeze

  def display_name
    "#{first_name} #{last_name}"
  end

  def self.active
    where(active: true)
  end
end
