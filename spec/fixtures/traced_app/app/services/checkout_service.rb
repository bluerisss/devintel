# frozen_string_literal: true

class CheckoutService
  def execute(order)
    OrderService.new.execute(order)
  end
end
