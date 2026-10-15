# frozen_string_literal: true

RSpec.describe DevIntel::Graph::ConstantLookup do
  subject(:lookup) { described_class.new(known) }

  let(:known) { Set["Billing", "Billing::Invoice", "Billing::Base", "Base", "Billing::Invoice::Line"] }

  it "finds a constant defined in the current scope" do
    expect(lookup.call("Line", "Billing::Invoice")).to eq("Billing::Invoice::Line")
  end

  it "walks outwards the way Ruby does, innermost scope winning" do
    expect(lookup.call("Base", "Billing::Invoice")).to eq("Billing::Base")
  end

  it "falls back to the top level when no enclosing scope defines it" do
    expect(lookup.call("Base", "Something::Else")).to eq("Base")
  end

  it "resolves a qualified name written from the top" do
    expect(lookup.call("Billing::Invoice", "")).to eq("Billing::Invoice")
  end

  it "honours a root-scoped constant instead of searching outwards" do
    expect(lookup.call("::Base", "Billing::Invoice")).to eq("Base")
  end

  it "returns nil for a root-scoped constant that is not defined here" do
    expect(lookup.call("::Missing", "Billing")).to be_nil
  end

  it "returns nil rather than guessing when nothing matches" do
    expect(lookup.call("Unknown", "Billing::Invoice")).to be_nil
  end

  it "returns nil for a name that was never determined" do
    expect(lookup.call(nil, "Billing")).to be_nil
  end

  it "does not search a class's ancestors, which it cannot know statically" do
    # `Billing::Invoice < Billing::Base`, and Base defines Line in Ruby terms;
    # a lexical lookup must not pretend to see that.
    expect(described_class.new(Set["Billing::Base::Line"]).call("Line", "Billing::Invoice")).to be_nil
  end
end
