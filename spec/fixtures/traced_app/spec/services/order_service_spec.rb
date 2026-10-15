# frozen_string_literal: true

RSpec.describe OrderService do
  it "executes" do
    OrderService.new.execute(order)
  end
end
