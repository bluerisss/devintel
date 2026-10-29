# frozen_string_literal: true

RSpec.describe DevIntel::Presenters::Impact do
  def changed(name = "PaymentService#charge")
    DevIntel::Diff::Analyzer::ChangedSymbol.new(
      qualified_name: name, type: "method", path: "app/services/payment_service.rb",
      line_start: 2, line_end: 4
    )
  end

  def impacted(name, depth: 1, confidence: "HIGH", via: "PaymentService#charge",
               relation: "calls", evidence: "app/services/order_service.rb:3")
    DevIntel::Impact::Analyzer::Impacted.new(
      qualified_name: name, type: "method", path: "app/services/order_service.rb",
      line_start: 2, line_end: 4, depth: depth, confidence: confidence,
      via: via, relation: relation, evidence: evidence
    )
  end

  def render(**overrides)
    defaults = {
      root: Pathname.new("/workspace/app"), base: "origin/develop", merge_base: "a1b2c3d4",
      changed: [], impacted: [], entry_points: [], tests: [], untested: [], unmapped: [],
      truncated: false, depth_limit: 3
    }

    described_class.new(DevIntel::Impact::Analyzer::Result.new(**defaults, **overrides)).to_s
  end

  it "names the repository and what it compared against" do
    output = render

    expect(output).to start_with("DevIntel Impact\n")
    expect(output).to include("Base        origin/develop  (merge base a1b2c3d)")
  end

  it "lists the symbols the diff landed on" do
    expect(render(changed: [changed])).to match(/method\s+PaymentService#charge/)
  end

  describe "impact" do
    it "separates direct callers from those further away" do
      output = render(impacted: [impacted("OrderService#checkout"),
                                 impacted("PaymentsController#create", depth: 2, confidence: "LOW")])

      expect(output).to match(/Direct impact\s+1.*\n.*OrderService#checkout/)
      expect(output).to match(/Indirect impact\s+1.*\n.*PaymentsController#create/)
    end

    # The point of the whole command: a reader must be able to tell what was
    # observed from what was inferred.
    it "shows the confidence and the line that is the evidence" do
      output = render(impacted: [impacted("OrderService#checkout")])

      expect(output).to match(%r{HIGH\s+OrderService#checkout\s+app/services/order_service\.rb:3\s+calls})
    end

    it "puts the most certain findings first" do
      low = impacted("Far#away", confidence: "LOW")
      high = impacted("Near#by", confidence: "HIGH")

      expect(render(impacted: [low,
                               high]).index("Near#by")).to be < render(impacted: [low,
                                                                                  high]).index("Far#away")
    end

    it "leaves out a section with nothing in it" do
      expect(render).not_to include("Direct impact")
    end

    it "says when the walk stopped early rather than implying it finished" do
      expect(render(truncated: true)).to include("the change reaches further")
    end
  end

  describe "entry points" do
    # Static analysis cannot tell an entry point from dead code, so the
    # heading states what was actually checked.
    it "says exactly what was checked" do
      output = render(entry_points: ["PaymentsController#create"])

      expect(output).to include("nothing outside the tests calls these")
      expect(output).to include("PaymentsController#create")
    end
  end

  describe "tests" do
    it "lists the files and what they reach" do
      output = render(tests: [["spec/services/payment_service_spec.rb", ["PaymentService#charge"]]])

      expect(output).to match(%r{spec/services/payment_service_spec\.rb\s+covers PaymentService#charge})
    end

    it "says plainly when nothing references the impact set" do
      expect(render).to include("Tests  none reference anything in this impact set")
    end

    it "names changed symbols no test file references" do
      output = render(untested: [changed])

      expect(output).to include("No test names these")
      expect(output).to match(/PaymentService#charge/)
    end
  end

  it "carries through changes the diff could not map" do
    file = DevIntel::Diff::Analyzer::FileChange.new(
      path: "config/app.yml", status: "modified", lines: [], state: DevIntel::Diff::Analyzer::NOT_RUBY,
      symbols: []
    )

    expect(render(unmapped: [file])).to match(%r{config/app\.yml\s+not Ruby})
  end
end
