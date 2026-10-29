# frozen_string_literal: true

RSpec.describe DevIntel::Impact::Analyzer do
  # A chain deep enough to tell direct from indirect, with one branch reached
  # through an inferred receiver and one through an observed singleton call.
  APP = {
    "app/services/payment_service.rb" =>
      "class PaymentService\n  def self.charge(amount)\n    amount\n  end\nend\n",
    "app/services/order_service.rb" =>
      "class OrderService\n  def checkout(order)\n    PaymentService.charge(1)\n  end\nend\n",
    "app/controllers/payments_controller.rb" =>
      "class PaymentsController\n  def create\n    OrderService.new.checkout(order)\n  end\nend\n",
    "spec/services/payment_service_spec.rb" =>
      "RSpec.describe PaymentService do\nend\n"
  }.freeze

  CHARGED_TWICE =
    "class PaymentService\n  def self.charge(amount)\n    amount * 2\n  end\nend\n"

  def analyze(root, base: "base")
    DevIntel::Index::Indexer.new(DevIntel::Workspace.new(root)).call
    described_class.call(DevIntel::Workspace.new(root), base: base)
  end

  def with_change(files = APP, change: CHARGED_TWICE)
    with_git_repository(files) do |root, _git|
      write_file(root, "app/services/payment_service.rb", change) if change
      yield root
    end
  end

  def names(impacted)
    impacted.map(&:qualified_name)
  end

  it "reports the symbols the diff landed on" do
    with_change do |root|
      expect(names(analyze(root).changed)).to eq(["PaymentService.charge"])
    end
  end

  describe "traversal" do
    it "reports a caller of a changed symbol as direct impact" do
      with_change do |root|
        expect(names(analyze(root).direct)).to eq(["OrderService#checkout"])
      end
    end

    it "reports a caller of a caller as indirect impact" do
      with_change do |root|
        indirect = analyze(root).indirect

        expect(names(indirect)).to eq(["PaymentsController#create"])
        expect(indirect.first.depth).to eq(2)
      end
    end

    it "records each symbol at its shortest distance from the change" do
      files = APP.merge(
        "app/services/order_service.rb" =>
          "class OrderService\n  def checkout(order)\n    PaymentService.charge(1)\n  end\n  " \
          "def retry_it\n    PaymentService.charge(2)\n  end\nend\n"
      )

      with_change(files) do |root|
        expect(analyze(root).impacted.map(&:depth)).to all(be <= 2)
      end
    end

    it "does not revisit a symbol, so a cycle terminates" do
      files = {
        "a.rb" => "class A\n  def go\n    B.go\n  end\nend\n",
        "b.rb" => "class B\n  def self.go\n    C.go\n  end\nend\n",
        "c.rb" => "class C\n  def self.go\n    A.new.go\n  end\nend\n"
      }

      with_change(files, change: nil) do |root|
        write_file(root, "b.rb", "class B\n  def self.go\n    C.go\n    1\n  end\nend\n")

        expect(names(analyze(root).impacted).uniq.size).to eq(names(analyze(root).impacted).size)
      end
    end

    it "stops at the depth limit instead of walking the whole repository" do
      with_change do |root|
        expect(analyze(root).impacted.map(&:depth).max).to be <= described_class::MAX_DEPTH
        expect(analyze(root).depth_limit).to eq(described_class::MAX_DEPTH)
      end
    end

    it "leaves test files out of the impact set, reporting them separately" do
      with_change do |root|
        expect(names(analyze(root).impacted)).not_to include(a_string_matching(/spec/))
      end
    end
  end

  describe "confidence" do
    it "is HIGH for a direct call observed in the source" do
      with_change do |root|
        expect(analyze(root).direct.first.confidence).to eq("HIGH")
      end
    end

    # PaymentsController reaches checkout through `OrderService.new`, which is
    # an inference about the receiver's type, on top of being two steps away.
    it "is lowered when a step was inferred" do
      with_change do |root|
        expect(analyze(root).indirect.first.confidence).to eq("LOW")
      end
    end
  end

  describe "evidence" do
    it "points at the exact line that creates the relationship" do
      with_change do |root|
        impacted = analyze(root).direct.first

        expect(impacted.evidence).to eq("app/services/order_service.rb:3")
        expect(impacted.relation).to eq("calls")
        expect(impacted.via).to eq("PaymentService.charge")
      end
    end
  end

  describe "entry points" do
    it "reports impacted symbols nothing else calls" do
      with_change do |root|
        expect(analyze(root).entry_points).to eq(["PaymentsController#create"])
      end
    end

    it "does not count a symbol a test merely references as an entry point" do
      with_change do |root|
        expect(analyze(root).entry_points).not_to include("PaymentService.charge")
      end
    end
  end

  describe "tests" do
    it "lists test files that reference anything in the impact set" do
      with_change do |root|
        expect(analyze(root).tests.map(&:first)).to eq(["spec/services/payment_service_spec.rb"])
      end
    end

    it "names the changed symbols no test file references" do
      files = APP.reject { |path, _| path.start_with?("spec/") }

      with_change(files) do |root|
        expect(names(analyze(root).untested)).to eq(["PaymentService.charge"])
      end
    end

    it "reports nothing untested when a spec names the changed symbol" do
      with_change do |root|
        expect(analyze(root).untested).to be_empty
      end
    end
  end

  describe "when there is nothing to say" do
    it "returns an empty result for an unchanged tree" do
      with_change(APP, change: nil) do |root|
        result = analyze(root)

        expect(result.changed).to be_empty
        expect(result.impacted).to be_empty
      end
    end

    it "passes through changes the diff could not map" do
      files = APP.merge("config/app.yml" => "a: 1\n")

      with_change(files, change: nil) do |root|
        write_file(root, "config/app.yml", "a: 2\n")

        expect(analyze(root).unmapped.map(&:path)).to eq(["config/app.yml"])
      end
    end

    it "requires an index" do
      with_git_repository(APP) do |root, _git|
        expect { described_class.call(DevIntel::Workspace.new(root), base: "base") }
          .to raise_error(DevIntel::IndexNotFoundError)
      end
    end
  end
end
