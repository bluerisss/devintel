# frozen_string_literal: true

RSpec.describe DevIntel::Diff::Analyzer do
  SERVICE = <<~RUBY
    class PaymentService
      MAX_RETRIES = 3

      def execute(order)
        charge(order.total)
      end

      def charge(amount)
        amount
      end
    end
  RUBY

  # Same shape, with `charge` returning something different.
  CHARGE_CHANGED = SERVICE.sub("    amount\n", "    amount * 2\n")

  RETRIES_CHANGED = SERVICE.sub("MAX_RETRIES = 3", "MAX_RETRIES = 9")

  MIXIN_ADDED = SERVICE.sub("class PaymentService\n", "class PaymentService\n  include Retryable\n")

  BLANK_LINE_ADDED = SERVICE.sub("  def charge", "\n  def charge")

  def index(root)
    DevIntel::Index::Indexer.new(DevIntel::Workspace.new(root)).call
  end

  def analyze(root, base: "base")
    described_class.call(DevIntel::Workspace.new(root), base: base)
  end

  def changed_names(result)
    result.symbols.map(&:qualified_name)
  end

  def state_of(result, path)
    result.files.find { |file| file.path == path }&.state
  end

  describe "mapping changed lines to symbols" do
    it "reports the innermost symbol a changed line falls in" do
      with_git_repository("app/payment_service.rb" => SERVICE) do |root, _git|
        write_file(root, "app/payment_service.rb", CHARGE_CHANGED)
        index(root)

        expect(changed_names(analyze(root))).to eq(["PaymentService#charge"])
      end
    end

    it "does not report the enclosing class when a method body changes" do
      with_git_repository("app/payment_service.rb" => SERVICE) do |root, _git|
        write_file(root, "app/payment_service.rb", RETRIES_CHANGED)
        index(root)

        expect(changed_names(analyze(root))).to eq(["PaymentService::MAX_RETRIES"])
      end
    end

    it "reports the class when the change is in the class body itself" do
      with_git_repository("app/payment_service.rb" => SERVICE) do |root, _git|
        write_file(root, "app/payment_service.rb", MIXIN_ADDED)
        index(root)

        expect(changed_names(analyze(root))).to eq(["PaymentService"])
      end
    end

    # An added blank line's innermost symbol is the whole class, which would
    # report the entire class as changed over nothing at all.
    it "ignores a blank line" do
      with_git_repository("app/payment_service.rb" => SERVICE) do |root, _git|
        write_file(root, "app/payment_service.rb", BLANK_LINE_ADDED)
        index(root)

        expect(changed_names(analyze(root))).to be_empty
        expect(state_of(analyze(root), "app/payment_service.rb")).to eq(described_class::NO_SYMBOL)
      end
    end

    it "reports every symbol of a brand new file git has never seen" do
      with_git_repository("app/payment_service.rb" => SERVICE) do |root, _git|
        write_file(root, "app/refund_service.rb", "class RefundService\n  def execute; end\nend\n")
        index(root)

        expect(changed_names(analyze(root))).to contain_exactly("RefundService", "RefundService#execute")
      end
    end

    it "reports symbols of a file added in a commit" do
      with_git_repository("app/payment_service.rb" => SERVICE) do |root, git|
        git.branch!("feature")
        write_file(root, "app/refund_service.rb", "class RefundService; end\n")
        git.commit_all!("add refund")
        index(root)

        expect(changed_names(analyze(root))).to eq(["RefundService"])
      end
    end
  end

  describe "changes it cannot map, which it says out loud" do
    # The index describes the working tree. Mapping line numbers through a
    # stale index would name whichever symbol used to sit on those lines.
    it "refuses to map a file that changed after the last index" do
      with_git_repository("app/payment_service.rb" => SERVICE) do |root, _git|
        index(root)
        write_file(root, "app/payment_service.rb", CHARGE_CHANGED)

        result = analyze(root)

        expect(state_of(result, "app/payment_service.rb")).to eq(described_class::STALE)
        expect(result.symbols).to be_empty
      end
    end

    it "lists a deleted file without inventing the symbols it used to hold" do
      with_git_repository("app/payment_service.rb" => SERVICE) do |root, _git|
        root.join("app/payment_service.rb").delete
        index(root)

        result = analyze(root)

        expect(state_of(result, "app/payment_service.rb")).to eq(described_class::DELETED)
        expect(result.symbols).to be_empty
      end
    end

    it "says when a changed file is not Ruby" do
      with_git_repository("config/database.yml" => "development:\n",
                          "a.rb" => "class A; end\n") do |root, _git|
        write_file(root, "config/database.yml", "development:\nproduction:\n")
        index(root)

        expect(state_of(analyze(root), "config/database.yml")).to eq(described_class::NOT_RUBY)
      end
    end

    it "says when a Ruby file is missing from the index" do
      with_git_repository("app/payment_service.rb" => SERVICE) do |root, _git|
        index(root)
        write_file(root, "vendor/thing.rb", "class Vendored; end\n")

        # vendor/ is excluded from indexing, so the file is changed but unknown.
        expect(state_of(analyze(root), "vendor/thing.rb")).to eq(described_class::NOT_INDEXED)
      end
    end

    it "collects the unmapped files for the caller to report" do
      with_git_repository("a.rb" => "class A; end\n", "x.yml" => "a: 1\n") do |root, _git|
        write_file(root, "x.yml", "a: 2\n")
        index(root)

        expect(analyze(root).unmapped.map(&:path)).to eq(["x.yml"])
      end
    end
  end

  describe "the comparison itself" do
    it "records which base and merge base it used" do
      with_git_repository("a.rb" => "class A; end\n") do |root, git|
        base = git.head
        index(root)

        result = analyze(root)
        expect(result.base).to eq("base")
        expect(result.merge_base).to eq(base)
      end
    end

    it "reports nothing when the working tree matches the base" do
      with_git_repository("a.rb" => "class A; end\n") do |root, _git|
        index(root)

        result = analyze(root)
        expect(result.files).to be_empty
        expect(result.symbols).to be_empty
      end
    end

    it "requires an index" do
      with_git_repository("a.rb" => "class A; end\n") do |root, _git|
        expect { analyze(root) }.to raise_error(DevIntel::IndexNotFoundError, /devintel index/)
      end
    end
  end
end
