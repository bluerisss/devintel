# frozen_string_literal: true

RSpec.describe DevIntel::Diff::HunkParser do
  def parse(patch)
    described_class.call(patch)
  end

  it "reads a single changed line" do
    patch = "--- a/a.rb\n+++ b/a.rb\n@@ -5 +5 @@\n-old\n+new\n"

    expect(parse(patch)).to eq("a.rb" => [5..5])
  end

  it "reads a run of added lines" do
    patch = "--- a/a.rb\n+++ b/a.rb\n@@ -20,0 +21,3 @@\n+one\n+two\n+three\n"

    expect(parse(patch)).to eq("a.rb" => [21..23])
  end

  it "keeps a deletion-only hunk, anchored at the surviving line" do
    patch = "--- a/a.rb\n+++ b/a.rb\n@@ -40,2 +42,0 @@\n-gone\n-also gone\n"

    expect(parse(patch)).to eq("a.rb" => [42..42])
  end

  it "never anchors below line 1, which is not a line number" do
    patch = "--- a/a.rb\n+++ b/a.rb\n@@ -1,2 +0,0 @@\n-gone\n"

    expect(parse(patch)).to eq("a.rb" => [1..1])
  end

  it "reads several hunks in one file" do
    patch = "--- a/a.rb\n+++ b/a.rb\n@@ -1 +1 @@\n@@ -10,0 +11,2 @@\n"

    expect(parse(patch)).to eq("a.rb" => [1..1, 11..12])
  end

  it "separates hunks by file" do
    patch = "--- a/a.rb\n+++ b/a.rb\n@@ -1 +1 @@\n--- a/b.rb\n+++ b/b.rb\n@@ -7 +7 @@\n"

    expect(parse(patch)).to eq("a.rb" => [1..1], "b.rb" => [7..7])
  end

  it "takes the whole file for a new one" do
    patch = "--- /dev/null\n+++ b/new.rb\n@@ -0,0 +1,4 @@\n"

    expect(parse(patch)).to eq("new.rb" => [1..4])
  end

  # A deleted file has no new side, so there are no lines to map a symbol to.
  it "records nothing for a deleted file" do
    patch = "--- a/old.rb\n+++ /dev/null\n@@ -1,3 +0,0 @@\n"

    expect(parse(patch)).to be_empty
  end

  it "unquotes a path git had to quote" do
    patch = %(--- a/x\n+++ b/"app/odd\\"name.rb"\n@@ -1 +1 @@\n)

    expect(parse(patch).keys).to eq(['app/odd"name.rb'])
  end

  it "returns nothing for an empty diff" do
    expect(parse("")).to be_empty
  end
end
