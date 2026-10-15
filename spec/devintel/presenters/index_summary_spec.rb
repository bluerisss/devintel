# frozen_string_literal: true

RSpec.describe DevIntel::Presenters::IndexSummary do
  def result(**overrides)
    defaults = {
      root: Pathname.new("/workspace/app"),
      database_path: Pathname.new("/workspace/app/.devintel/index.sqlite"),
      discovered: 842, added: 840, modified: 2, unchanged: 0, removed: 0,
      symbols: 5120, symbol_types: { "method" => 4000, "class" => 1120 },
      references: 318, reference_types: { "INHERITS" => 200, "CALLS" => 118 },
      resolutions: { "resolved" => 200, "unknown_receiver" => 118 },
      unattributed_self_calls: 0, parse_error_paths: [],
      duration: 1.234
    }

    DevIntel::Index::Indexer::Result.new(**defaults, **overrides)
  end

  def render(**overrides)
    described_class.new(result(**overrides)).to_s
  end

  it "names the repository and the database" do
    output = render

    expect(output).to start_with("DevIntel Index\n\n")
    expect(output).to include("Repository  /workspace/app")
    expect(output).to include("Database    .devintel/index.sqlite")
  end

  describe "the work this run did" do
    it "reports the elapsed time in its heading" do
      expect(render).to include("This run took 1.23s")
    end

    it "accounts for every discovered file as parsed or skipped" do
      output = render(discovered: 10, added: 1, modified: 2, unchanged: 7)

      expect(output).to match(/10\s+Ruby files\s+found on disk/)
      expect(output).to match(/3\s+parsed\s+1 added, 2 modified/)
      expect(output).to match(/7\s+skipped\s+unchanged since the last run/)
    end

    it "reports files that left the repository" do
      expect(render(removed: 4)).to match(/4\s+removed\s+no longer on disk/)
    end

    it "makes a no-op run obvious instead of silent" do
      output = render(discovered: 10, added: 0, modified: 0, unchanged: 10)

      expect(output).to match(/0\s+parsed/)
      expect(output).to match(/10\s+skipped/)
    end

    it "uses the singular for a single file" do
      expect(render(discovered: 1, added: 1, modified: 0)).to match(/1\s+Ruby file\s+found on disk/)
    end
  end

  describe "what the index holds" do
    it "is reported separately from the work of this run" do
      output = render(discovered: 10, added: 0, modified: 0, unchanged: 10)

      # The run did nothing, yet the index is full: the two sections must not
      # be confusable.
      expect(output).to match(/0\s+parsed/)
      expect(output).to match(/Index now holds\n.*5120\s+symbols/m)
    end

    it "breaks symbols down by type so the totals mean something" do
      expect(render).to match(/5120\s+symbols\s+method 4000, class 1120/)
    end

    it "breaks relationships down by edge type" do
      expect(render).to match(/318\s+relationships\s+INHERITS 200, CALLS 118/)
    end

    it "separates edges that reach this codebase from those that do not" do
      output = render(
        references: 10,
        resolutions: { "resolved" => 4, "inferred" => 2, "unknown_receiver" => 3, "dynamic" => 1 }
      )

      expect(output).to match(/6\s+traced to code\s+resolved 4, inferred 2/)
      expect(output).to match(/4\s+left untraced\s+unknown receiver 3, dynamic 1/)
    end

    it "reports receiverless calls it refused to attribute" do
      expect(render(unattributed_self_calls: 37))
        .to match(/37\s+self-calls dropped\s+receiverless call not defined in its own scope/)
    end

    it "does not claim a problem when there is none" do
      output = render(parse_error_paths: [])

      expect(output).to match(/0\s+unparsed files/)
      expect(output).not_to include("syntax error")
    end
  end

  describe "files that could not be parsed" do
    it "counts them and names them, because a count alone is not actionable" do
      output = render(parse_error_paths: ["app/models/broken.rb"])

      expect(output).to match(/1\s+unparsed file\s+syntax error, so no symbols were stored/)
      expect(output).to include("      app/models/broken.rb")
    end

    it "keeps the count exact when the list is cut short" do
      paths = Array.new(8) { |i| "app/broken_#{i}.rb" }

      output = render(parse_error_paths: paths)

      expect(output).to match(/8\s+unparsed files/)
      expect(output).to include("      app/broken_0.rb")
      expect(output).to include("      ... and 3 more")
      expect(output).not_to include("app/broken_5.rb")
    end
  end

  it "renders an empty repository without special-casing" do
    output = render(
      discovered: 0, added: 0, modified: 0, unchanged: 0, removed: 0,
      symbols: 0, symbol_types: {}, references: 0, reference_types: {}, resolutions: {}
    )

    expect(output).to match(/0\s+Ruby files\s+found on disk/)
    expect(output).to match(/0\s+symbols/)
  end
end
