# frozen_string_literal: true

RSpec.describe DevIntel::Graph::Trace do
  def trace(root, query)
    workspace = DevIntel::Workspace.new(root)
    DevIntel::Index::Indexer.new(workspace).call
    described_class.call(workspace, query)
  end

  def with_traced_app(&block)
    with_fixture_repository("traced_app", &block)
  end

  def names(relations)
    relations.map(&:qualified_name)
  end

  it "reports where the symbol is defined" do
    with_traced_app do |root|
      definition = trace(root, "OrderService").definitions.first

      expect(definition.type).to eq("class")
      expect(definition.path).to eq("app/services/order_service.rb")
      expect(definition.line_start).to eq(3)
    end
  end

  it "finds callers across files" do
    with_traced_app do |root|
      expect(names(trace(root, "OrderService").callers)).to include("CheckoutService#execute")
    end
  end

  it "finds what the symbol reaches" do
    with_traced_app do |root|
      expect(names(trace(root, "OrderService").callees)).to include(
        "PaymentService#charge", "OrderRepository.save", "OrderService#audit"
      )
    end
  end

  it "identifies tests by what they reference, not by their filename" do
    with_traced_app do |root|
      expect(trace(root, "OrderService").tests.map(&:path)).to eq(
        ["spec/services/order_service_spec.rb"]
      )
    end
  end

  it "does not count an unrelated spec as a test for the symbol" do
    with_traced_app do |root|
      expect(trace(root, "PaymentService").tests).to be_empty
    end
  end

  it "keeps the evidence class of each relationship" do
    with_traced_app do |root|
      charge = trace(root, "OrderService").callees.find { |r| r.qualified_name == "PaymentService#charge" }
      save = trace(root, "OrderService").callees.find { |r| r.qualified_name == "OrderRepository.save" }

      expect(charge.evidence_class).to eq("INFERENCE") # via PaymentService.new
      expect(save.evidence_class).to eq("FACT")        # a singleton call on the constant
    end
  end

  it "does not report a symbol's own members as its callers" do
    with_traced_app do |root|
      # OrderService#execute calls OrderService#audit; that is internal, and
      # already visible under callees.
      expect(names(trace(root, "OrderService").callers)).not_to include("OrderService#execute")
    end
  end

  it "still reports callers written at file scope, which have no source symbol" do
    with_traced_app do |root|
      expect(names(trace(root, "OrderService").callers)).to include("(file scope)")
    end
  end

  it "names the member an unresolved call lands on" do
    with_traced_app do |root|
      relation = trace(root, "OrderService").callers
                                            .find do |r|
        r.qualified_name == "CheckoutService#execute" &&
          r.resolution == "receiver_only"
      end

      expect(relation.reaches).to eq("OrderService.new")
    end
  end

  it "summarises relationships it could not follow instead of listing them" do
    with_repository("a.rb" => "class A\n  def run(x); x.whatever; end\nend\n") do |root|
      result = trace(root, "A")

      expect(result.callees).to be_empty
      expect(result.untraced).to eq("unknown_receiver" => 1)
    end
  end

  it "accepts a simple name when it is unambiguous" do
    with_repository("a.rb" => "module Billing\n  class Invoice; end\nend\n") do |root|
      expect(trace(root, "Invoice").query).to eq("Billing::Invoice")
    end
  end

  it "prefers an exact qualified name over a simple one" do
    files = { "a.rb" => "class Invoice; end\n", "b.rb" => "module Billing\n  class Invoice; end\nend\n" }

    with_repository(files) do |root|
      expect(trace(root, "Invoice").query).to eq("Invoice")
    end
  end

  it "refuses to pick for the developer when a simple name is ambiguous" do
    files = {
      "a.rb" => "module Sales\n  class Invoice; end\nend\n",
      "b.rb" => "module Billing\n  class Invoice; end\nend\n"
    }

    with_repository(files) do |root|
      expect { trace(root, "Invoice") }
        .to raise_error(DevIntel::AmbiguousSymbolError, /Billing::Invoice.*Sales::Invoice/m)
    end
  end

  it "says so when the symbol is not in the index" do
    with_repository("a.rb" => "class A; end\n") do |root|
      expect do
        trace(root, "Missing")
      end.to raise_error(DevIntel::SymbolNotFoundError, /No symbol named Missing/)
    end
  end

  it "says to index first when there is no index" do
    with_repository("a.rb" => "class A; end\n") do |root|
      workspace = DevIntel::Workspace.new(root)

      expect { described_class.call(workspace, "A") }
        .to raise_error(DevIntel::IndexNotFoundError, /Run `devintel index` first/)
    end
  end

  it "counts repeated call sites once, keeping the number of occurrences" do
    source = "class A\n  def run\n    B.go\n    B.go\n  end\nend\nclass B\n  def self.go; end\nend\n"

    with_repository("a.rb" => source) do |root|
      relation = trace(root, "B").callers.find { |r| r.qualified_name == "A#run" }

      expect(relation.occurrences).to eq(2)
    end
  end
end
