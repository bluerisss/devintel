# frozen_string_literal: true

RSpec.describe DevIntel::Presenters::Diff do
  def symbol(name, type: "method", path: "app/a.rb", line_start: 4, line_end: 7)
    DevIntel::Diff::Analyzer::ChangedSymbol.new(
      qualified_name: name, type: type, path: path, line_start: line_start, line_end: line_end
    )
  end

  def file(path, status: "modified", lines: [4..7], state: DevIntel::Diff::Analyzer::MAPPED, symbols: [])
    DevIntel::Diff::Analyzer::FileChange.new(
      path: path, status: status, lines: lines, state: state, symbols: symbols
    )
  end

  def render(files: [], base: "origin/develop", merge_base: "a1b2c3d4e5f6")
    result = DevIntel::Diff::Analyzer::Result.new(
      root: Pathname.new("/workspace/app"), base: base, merge_base: merge_base, files: files
    )

    described_class.new(result).to_s
  end

  it "names the repository and what it compared against" do
    output = render

    expect(output).to start_with("DevIntel Diff\n")
    expect(output).to include("Repository  /workspace/app")
    expect(output).to include("Base        origin/develop  (merge base a1b2c3d)")
  end

  describe "changed files" do
    it "lists each file with its status and changed lines" do
      output = render(files: [file("app/a.rb", lines: [4..7])])

      expect(output).to match(%r{modified\s+app/a\.rb\s+lines 4-7})
    end

    it "writes a single changed line in the singular" do
      expect(render(files: [file("app/a.rb", lines: [9..9])])).to match(/line 9/)
    end

    it "joins separate ranges" do
      expect(render(files: [file("app/a.rb", lines: [2..2, 10..12])])).to match(/lines 2, 10-12/)
    end

    it "keeps the count exact when there are too many ranges to list" do
      ranges = Array.new(9) { |i| (i * 10)..(i * 10) }

      expect(render(files: [file("app/a.rb", lines: ranges)])).to include("+3 more")
    end

    it "says so when nothing changed" do
      expect(render).to include("Changed files\n  none")
    end
  end

  describe "changed symbols" do
    it "lists them with their type and location" do
      changed = file("app/a.rb", symbols: [symbol("PaymentService#execute")])

      expect(render(files: [changed])).to match(%r{method\s+PaymentService#execute\s+app/a\.rb:4-7})
    end

    it "reports none rather than leaving the section out" do
      expect(render(files: [file("app/a.rb")])).to include("Changed symbols  none")
    end

    it "does not repeat a symbol reached from two files" do
      shared = symbol("A#b")
      files = [file("app/a.rb", symbols: [shared]), file("app/b.rb", symbols: [shared])]

      expect(render(files: files).scan("A#b").size).to eq(1)
    end
  end

  describe "changes with no symbols" do
    it "gives the reason, so a gap is not read as an absence" do
      files = [
        file("app/old.rb", status: "deleted", lines: [], state: DevIntel::Diff::Analyzer::DELETED),
        file("config/a.yml", state: DevIntel::Diff::Analyzer::NOT_RUBY)
      ]

      output = render(files: files)

      expect(output).to match(%r{app/old\.rb\s+deleted})
      expect(output).to match(%r{config/a\.yml\s+not Ruby})
    end

    it "tells the developer how to fix a stale index" do
      stale = file("app/a.rb", state: DevIntel::Diff::Analyzer::STALE)

      expect(render(files: [stale])).to include("changed since the last index  ->  run `devintel index`")
    end

    it "leaves the section out when every file mapped" do
      mapped = file("app/a.rb", symbols: [symbol("A#b")])

      expect(render(files: [mapped])).not_to include("No symbols mapped")
    end
  end
end
