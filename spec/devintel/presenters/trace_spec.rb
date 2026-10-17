# frozen_string_literal: true

RSpec.describe DevIntel::Presenters::Trace do
  def definition(qualified_name = "OrderService", type: "class", path: "app/services/order_service.rb")
    DevIntel::Graph::SymbolGraph::Definition.new(
      qualified_name: qualified_name, type: type, path: path, line_start: 3, line_end: 11
    )
  end

  def relation(qualified_name, type: "CALLS", resolution: "resolved", reaches: nil,
               location: "app/services/checkout_service.rb:5", occurrences: 1)
    DevIntel::Graph::Trace::Relation.new(
      qualified_name: qualified_name, type: type, resolution: resolution, reaches: reaches,
      location: location, occurrences: occurrences
    )
  end

  def result(**overrides)
    defaults = {
      query: "OrderService", definitions: [definition], callers: [], callees: [],
      untraced: {}, tests: []
    }

    DevIntel::Graph::Trace::Result.new(**defaults, **overrides)
  end

  def render(**overrides)
    described_class.new(result(**overrides)).to_s
  end

  it "leads with the symbol and where it is defined" do
    output = render

    expect(output).to start_with("OrderService\n")
    expect(output).to match(%r{class\s+app/services/order_service\.rb:3-11})
  end

  it "says plainly when the symbol is not defined in this repository" do
    expect(render(definitions: [])).to include("not defined in this repository")
  end

  it "lists callers with the evidence class of each" do
    output = render(callers: [relation("CheckoutService#execute")])

    expect(output).to match(/Callers/)
    expect(output).to match(/CheckoutService#execute\s+CALLS\s+FACT/)
    expect(output).to include("app/services/checkout_service.rb:5")
  end

  it "does not let an inference look like an observation" do
    output = render(callers: [relation("CheckoutService#execute", resolution: "inferred")])

    expect(output).to match(/CheckoutService#execute\s+CALLS\s+INFERENCE/)
  end

  it "shows which member of the symbol a relationship reaches" do
    output = render(callers: [relation("Indexer#run", reaches: "OrderService#execute")])

    expect(output).to include("#execute")
  end

  it "collapses repeated call sites but keeps the count" do
    expect(render(callers: [relation("A#run", occurrences: 4)])).to include("(4 sites)")
  end

  it "summarises relationships it could not follow rather than hiding them" do
    output = render(untraced: { "unknown_receiver" => 16, "named" => 3 })

    expect(output).to include("+ 19 relationships DevIntel could not follow")
    expect(output).to include("unknown receiver 16, named 3")
  end

  it "does not print an empty section" do
    output = render

    expect(output).not_to include("Callers")
    expect(output).not_to include("Tests")
  end

  it "lists the test files that name the symbol" do
    tests = [DevIntel::Graph::Trace::TestFile.new(path: "spec/services/order_service_spec.rb",
                                                  line: 3, type: "REFERENCES")]

    expect(render(tests: tests)).to include("spec/services/order_service_spec.rb")
  end

  it "keeps long lists readable while keeping the count exact" do
    callers = Array.new(30) { |i| relation("Caller#{i}#run") }

    output = render(callers: callers)

    expect(output).to include("Caller0#run")
    expect(output).to include("... and 5 more")
    expect(output).not_to include("Caller28#run")
  end
end
