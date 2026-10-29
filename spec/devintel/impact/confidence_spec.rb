# frozen_string_literal: true

RSpec.describe DevIntel::Impact::Confidence do
  def level(depth, inferred)
    described_class.for(depth: depth, inferred: inferred)
  end

  it "is highest for a direct call read straight from the source" do
    expect(level(1, false)).to eq("HIGH")
  end

  it "drops a level when the receiver's type was inferred" do
    expect(level(1, true)).to eq("MEDIUM")
  end

  it "drops a level for each step away from the change" do
    expect(level(2, false)).to eq("MEDIUM")
    expect(level(3, false)).to eq("LOW")
  end

  it "compounds distance with inference" do
    expect(level(2, true)).to eq("LOW")
  end

  it "does not fall below the lowest level" do
    expect(level(99, true)).to eq("LOW")
  end
end
