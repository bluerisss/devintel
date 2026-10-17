# frozen_string_literal: true

RSpec.describe DevIntel::Repository::Git do
  def statuses(changes)
    changes.map { |change| [change.status, change.path] }
  end

  it "finds the merge base rather than the branch tip" do
    with_git_repository("a.rb" => "class A; end\n") do |root, git|
      branch_point = git.head
      git.branch!("feature")
      write_file(root, "b.rb", "class B; end\n")
      git.commit_all!("on feature")

      expect(described_class.new(root).merge_base("base")).to eq(branch_point)
    end
  end

  # On a feature branch, diffing the base ref itself also reports whatever
  # landed on the base afterwards, as though the developer had reverted it.
  it "ignores commits made on the base after the branch point" do
    with_git_repository("a.rb" => "class A; end\n") do |root, git|
      git.branch!("feature")
      write_file(root, "feature.rb", "class Feature; end\n")
      git.commit_all!("feature work")
      git.run("checkout", "--quiet", "base")
      write_file(root, "later.rb", "class Later; end\n")
      git.commit_all!("moved on")
      git.run("checkout", "--quiet", "feature")

      changed = described_class.new(root).changed_files(described_class.new(root).merge_base("base"))

      expect(statuses(changed)).to eq([["added", "feature.rb"]])
    end
  end

  describe "#changed_files" do
    it "reports additions, modifications and deletions" do
      files = { "keep.rb" => "class Keep; end\n", "gone.rb" => "class Gone; end\n" }

      with_git_repository(files) do |root, git|
        base = git.head
        write_file(root, "keep.rb", "class Keep\n  def a; end\nend\n")
        root.join("gone.rb").delete
        write_file(root, "new.rb", "class New; end\n")
        git.commit_all!("change")

        expect(statuses(described_class.new(root).changed_files(base))).to contain_exactly(
          %w[modified keep.rb], %w[deleted gone.rb], %w[added new.rb]
        )
      end
    end

    it "reports a rename with the path it moved from" do
      with_git_repository("old.rb" => "class Thing\n  def a; end\n  def b; end\nend\n") do |root, git|
        base = git.head
        git.run("mv", "old.rb", "new.rb")
        git.commit_all!("rename")

        change = described_class.new(root).changed_files(base).first
        expect(change.status).to eq("renamed")
        expect(change.old_path).to eq("old.rb")
        expect(change.path).to eq("new.rb")
      end
    end

    # `-z` output is used precisely so these survive.
    it "handles paths containing spaces and non-ASCII characters" do
      with_git_repository("a.rb" => "class A; end\n") do |root, git|
        base = git.head
        write_file(root, "app/my service.rb", "class MyService; end\n")
        write_file(root, "app/café.rb", "class Cafe; end\n")
        git.commit_all!("odd names")

        paths = described_class.new(root).changed_files(base).map(&:path)
        expect(paths).to contain_exactly("app/my service.rb", "app/café.rb")
      end
    end

    it "includes changes that are not committed yet" do
      with_git_repository("a.rb" => "class A; end\n") do |root, git|
        base = git.head
        write_file(root, "a.rb", "class A\n  def b; end\nend\n")

        expect(statuses(described_class.new(root).changed_files(base))).to eq([%w[modified a.rb]])
      end
    end
  end

  describe "#untracked_files" do
    it "lists files git has never seen" do
      with_git_repository("a.rb" => "class A; end\n") do |root, _git|
        write_file(root, "brand_new.rb", "class BrandNew; end\n")

        expect(described_class.new(root).untracked_files).to eq(["brand_new.rb"])
      end
    end

    it "respects gitignore" do
      with_git_repository("a.rb" => "class A; end\n", ".gitignore" => "ignored.rb\n") do |root, _git|
        write_file(root, "ignored.rb", "class Ignored; end\n")

        expect(described_class.new(root).untracked_files).to be_empty
      end
    end
  end

  describe "#changed_lines" do
    it "reports the lines of the new version" do
      with_git_repository("a.rb" => "class A\n  def one; end\n  def two; end\nend\n") do |root, git|
        base = git.head
        write_file(root, "a.rb", "class A\n  def one; end\n  def two; 42; end\nend\n")

        expect(described_class.new(root).changed_lines(base)).to eq("a.rb" => [3..3])
      end
    end
  end

  describe "refusing to guess" do
    it "names an unknown base instead of comparing against nothing" do
      with_git_repository("a.rb" => "class A; end\n") do |root, _git|
        expect { described_class.new(root).merge_base("no-such-branch") }
          .to raise_error(DevIntel::Error, /Unknown base `no-such-branch`/)
      end
    end

    # The ref reaches git as one argv element, so it can only ever be a ref.
    it "treats a shell-looking base as a ref, not as a command" do
      with_git_repository("a.rb" => "class A; end\n") do |root, _git|
        expect { described_class.new(root).merge_base("; touch owned") }
          .to raise_error(DevIntel::Error, /Unknown base/)
        expect(root.join("owned")).not_to exist
      end
    end
  end
end
