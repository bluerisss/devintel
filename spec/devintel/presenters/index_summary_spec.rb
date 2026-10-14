# frozen_string_literal: true

RSpec.describe DevIntel::Presenters::IndexSummary do
  def result(**overrides)
    DevIntel::Index::Indexer::Result.new(
      root: Pathname.new("/workspace/app"),
      database_path: Pathname.new("/workspace/app/.devintel/index.sqlite"),
      discovered: 842, added: 840, modified: 2, unchanged: 0, removed: 0, duration: 1.234, **overrides
    )
  end

  it "reports the repository, counts and database location" do
    output = described_class.new(result).to_s

    expect(output).to start_with("DevIntel Index\n\n")
    expect(output).to include("Repository:\n  /workspace/app")
    expect(output).to include("Ruby files:\n  842")
    expect(output).to include("Indexed:\n  842")
    expect(output).to include("Database:\n  .devintel/index.sqlite")
    expect(output).to include("Duration:\n  1.23s")
  end

  it "breaks the changed count down so a run is auditable" do
    output = described_class.new(result(added: 1, modified: 2, removed: 3, unchanged: 836)).to_s

    expect(output).to include("Changed:\n  6  (new 1, modified 2, removed 3)")
  end

  it "shows nothing to do as zero rather than hiding it" do
    output = described_class.new(result(added: 0, modified: 0, unchanged: 842)).to_s

    expect(output).to include("Changed:\n  0  (new 0, modified 0, removed 0)")
    expect(output).to include("Indexed:\n  0")
  end
end
