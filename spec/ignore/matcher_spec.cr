require "../spec_helper"

def make_ignore_root(dir, opts = Dir::Walk::Ignore::IgnoreOptions.new)
  empty = Dir::Walk::Ignore::Matcher.new(dir: dir, opts: opts)
  empty.add_child(dir)
end

describe Dir::Walk::Ignore::Matcher do
  it "empty matcher never matches" do
    m = Dir::Walk::Ignore::Matcher.new
    m.matched("foo", false).none?.should be_true
  end

  it "add_child reads .gitignore from a directory" do
    with_ignore_files({"src/.gitignore" => "*.rs"}) do |dir|
      root = make_ignore_root(dir)
      child = root.add_child(File.join(dir, "src"))
      child.matched(File.join(dir, "src/main.rs"), false).ignore?.should be_true
      child.matched(File.join(dir, "src/main.go"), false).none?.should be_true
    end
  end

  it "add_child reads .ignore files" do
    with_ignore_files({"src/.ignore" => "*.py"}) do |dir|
      root = make_ignore_root(dir)
      child = root.add_child(File.join(dir, "src"))
      child.matched(File.join(dir, "src/main.py"), false).ignore?.should be_true
      child.matched(File.join(dir, "src/main.rs"), false).none?.should be_true
    end
  end

  it "matches against parent ignore rules" do
    with_ignore_files({".gitignore" => "*.lock"}) do |dir|
      root = make_ignore_root(dir)
      child = root.add_child(File.join(dir, "src"))
      child.matched(File.join(dir, "src/Cargo.lock"), false).ignore?.should be_true
      child.matched(File.join(dir, "src/main.rs"), false).none?.should be_true
    end
  end

  it "whitelist .gitignore overrides parent ignore" do
    with_ignore_files({".gitignore" => "*.rs", "src/.gitignore" => "!main.rs"}) do |dir|
      root = make_ignore_root(dir)
      child = root.add_child(File.join(dir, "src"))
      child.matched(File.join(dir, "src/main.rs"), false).whitelist?.should be_true
      child.matched(File.join(dir, "src/lib.rs"), false).ignore?.should be_true
    end
  end

  it "ignores hidden files by default" do
    with_ignore_files({} of String => String) do |dir|
      root = make_ignore_root(dir)
      child = root.add_child(dir)
      child.matched(File.join(dir, ".hidden.txt"), false).ignore?.should be_true
    end
  end

  it "hidden(false) disables hidden file filtering" do
    opts = Dir::Walk::Ignore::IgnoreOptions.new(hidden: false)
    with_ignore_files({} of String => String) do |dir|
      root = make_ignore_root(dir, opts)
      child = root.add_child(dir)
      child.matched(File.join(dir, ".hidden.txt"), false).none?.should be_true
    end
  end

  it "ignores .gitignore files when git_ignore(false)" do
    opts = Dir::Walk::Ignore::IgnoreOptions.new(git_ignore: false)
    with_ignore_files({"src/.gitignore" => "*.rs"}) do |dir|
      root = make_ignore_root(dir, opts)
      child = root.add_child(File.join(dir, "src"))
      child.matched(File.join(dir, "src/main.rs"), false).none?.should be_true
    end
  end

  it "ignores .ignore files when ignore(false)" do
    opts = Dir::Walk::Ignore::IgnoreOptions.new(ignore: false)
    with_ignore_files({"src/.ignore" => "*.py"}) do |dir|
      root = make_ignore_root(dir, opts)
      child = root.add_child(File.join(dir, "src"))
      child.matched(File.join(dir, "src/main.py"), false).none?.should be_true
    end
  end

  it "respects directory-only patterns (trailing slash)" do
    with_ignore_files({"src/.gitignore" => "build/"}) do |dir|
      root = make_ignore_root(dir)
      child = root.add_child(File.join(dir, "src"))
      child.matched(File.join(dir, "src/build"), true).ignore?.should be_true
      child.matched(File.join(dir, "src/build"), false).none?.should be_true
    end
  end
end
