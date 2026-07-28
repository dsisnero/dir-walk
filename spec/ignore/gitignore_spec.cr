require "../spec_helper"

describe Dir::Walk::Ignore do
  describe "GitignoreBuilder" do
    it "parses basic gitignore patterns" do
      builder = Dir::Walk::Ignore::GitignoreBuilder.new("/home/project")
      builder.add_line(nil, "*.lock")
      gi = builder.build
      gi.matched("Cargo.lock", false).ignore?.should be_true
      gi.matched("src/main.rs", false).ignore?.should be_false
    end

    it "respects whitelist negation" do
      builder = Dir::Walk::Ignore::GitignoreBuilder.new("/home/project")
      builder.add_line(nil, "*.rs")
      builder.add_line(nil, "!src/main.rs")
      gi = builder.build
      gi.matched("src/main.rs", false).whitelist?.should be_true
      gi.matched("src/lib.rs", false).ignore?.should be_true
    end

    it "treats trailing slash as directory-only" do
      builder = Dir::Walk::Ignore::GitignoreBuilder.new("/home/project")
      builder.add_line(nil, "foo/")
      gi = builder.build
      gi.matched("foo", true).ignore?.should be_true
      gi.matched("foo", false).ignore?.should be_false
    end

    it "anchors patterns with leading slash" do
      builder = Dir::Walk::Ignore::GitignoreBuilder.new("/home/project")
      builder.add_line(nil, "/src/*.rs")
      gi = builder.build
      gi.matched("src/main.rs", false).ignore?.should be_true
      gi.matched("src/grep/src/main.rs", false).ignore?.should be_false
    end

    it "matches ** globs across directories" do
      builder = Dir::Walk::Ignore::GitignoreBuilder.new("/home/project")
      builder.add_line(nil, "**/foo")
      gi = builder.build
      gi.matched("foo", false).ignore?.should be_true
      gi.matched("src/foo", false).ignore?.should be_true
    end

    it "skips comments" do
      builder = Dir::Walk::Ignore::GitignoreBuilder.new("/home/project")
      builder.add_line(nil, "# this is a comment")
      builder.add_line(nil, "*.rs")
      gi = builder.build
      gi.matched("main.rs", false).ignore?.should be_true
      gi.matched("main.go", false).ignore?.should be_false
    end

    it "skips blank lines" do
      builder = Dir::Walk::Ignore::GitignoreBuilder.new("/home/project")
      builder.add_line(nil, "")
      builder.add_line(nil, "  ")
      builder.add_line(nil, "*.rs")
      gi = builder.build
      gi.matched("main.rs", false).ignore?.should be_true
    end

    it "ignores empty gitignore" do
      builder = Dir::Walk::Ignore::GitignoreBuilder.new("/home/project")
      gi = builder.build
      gi.empty?.should be_true
      gi.matched("anything", false).none?.should be_true
    end

    it "handles escaped exclamation mark" do
      builder = Dir::Walk::Ignore::GitignoreBuilder.new("/home/project")
      builder.add_line(nil, "\\!important")
      gi = builder.build
      gi.matched("!important", false).ignore?.should be_true
    end
  end

  describe "Gitignore" do
    it "empty matcher never matches" do
      gi = Dir::Walk::Ignore::Gitignore.empty
      gi.empty?.should be_true
      gi.matched("foo", false).none?.should be_true
      gi.matched("foo", true).none?.should be_true
    end

    it "matches file names at any level" do
      builder = Dir::Walk::Ignore::GitignoreBuilder.new("/repo")
      builder.add_line(nil, "target")
      gi = builder.build
      gi.matched("target", false).ignore?.should be_true
      gi.matched("src/target", false).ignore?.should be_true
      gi.matched("foo.rs", false).none?.should be_true
    end

    it "respects negative patterns over positive" do
      builder = Dir::Walk::Ignore::GitignoreBuilder.new("/repo")
      builder.add_line(nil, "*.rs")
      builder.add_line(nil, "!main.rs")
      gi = builder.build
      gi.matched("main.rs", false).whitelist?.should be_true
      gi.matched("lib.rs", false).ignore?.should be_true
    end
  end
end
