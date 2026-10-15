# frozen_string_literal: true

RSpec.describe DevIntel::Parser::RubyParser do
  describe "a file that does not parse" do
    subject(:result) { described_class.parse("class Foo\n  def oops(\nend") }

    it "reports failure" do
      expect(result).to be_failed
      expect(result.errors).not_to be_empty
    end

    it "extracts nothing at all, rather than guessing from a partial tree" do
      expect(result.symbols).to be_empty
      expect(result.references).to be_empty
    end

    it "reports the message and line of each error" do
      error = result.errors.first

      expect(error.message).to be_a(String).and(satisfy { |m| !m.empty? })
      expect(error.line).to be_a(Integer)
    end
  end

  describe "a file that parses" do
    it "reports no errors" do
      expect(described_class.parse("class Foo; end")).not_to be_failed
    end

    it "handles an empty file" do
      result = described_class.parse("")

      expect(result).not_to be_failed
      expect(result.symbols).to be_empty
    end

    it "handles a comment-only file" do
      expect(described_class.parse("# just a note\n").symbols).to be_empty
    end

    it "handles non-ASCII identifiers" do
      expect(described_class.parse("class Café; end").symbols.first.qualified_name).to eq("Café")
    end

    it "handles a frozen_string_literal magic comment" do
      source = "# frozen_string_literal: true\n\nclass User; end"

      expect(described_class.parse(source).symbols.first.line_start).to eq(3)
    end
  end

  describe ".parse_file" do
    it "reads and parses a file from disk" do
      with_directory("app/models/user.rb" => "class User\n  def name; end\nend\n") do |root|
        result = described_class.parse_file(root.join("app/models/user.rb"))

        expect(result.symbols.map(&:qualified_name)).to eq(["User", "User#name"])
      end
    end
  end
end
