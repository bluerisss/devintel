# frozen_string_literal: true

class OrderService
  def execute(order)
    PaymentService.new.charge(order.total)
    OrderRepository.save(order)
    audit(order)
  end

  def audit(order); end
end
