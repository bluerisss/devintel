# frozen_string_literal: true

RSpec.describe Services::UserService do
  it "returns the display name" do
    expect(described_class.new.execute(user)).to eq("A B")
  end
end
