require "../spec_helper"

describe Dir::Walk::Ignore::Override do
  it "empty override never matches" do
    ov = Dir::Walk::Ignore::Override.empty
    ov.empty?.should be_true
    ov.matched("a.foo", false).none?.should be_true
    ov.matched("a", true).none?.should be_true
  end

  it "simple include pattern" do
    ov = build_override("/root", ["*.foo"])
    ov.matched("a.foo", false).whitelist?.should be_true
    ov.matched("a.rs", false).ignore?.should be_true
  end

  it "include with exclude negation" do
    ov = build_override("/root", ["*.foo", "!*.bar"])
    ov.matched("a.foo", false).whitelist?.should be_true
    ov.matched("a.bar", false).ignore?.should be_true
    ov.matched("a.rs", false).ignore?.should be_true
  end

  it "directories are not ignored by default" do
    ov = build_override("/root", ["*.rs"])
    ov.matched("foo.rs", false).whitelist?.should be_true
    ov.matched("foo.c", false).ignore?.should be_true
    ov.matched("foo", true).none?.should be_true
  end

  it "respects gitignore semantics" do
    ov = build_override("/root", ["/foo", "bar/*.rs", "baz/**"])
    ov.matched("bar/lib.rs", false).whitelist?.should be_true
    ov.matched("bar/wat/lib.rs", false).ignore?.should be_true
    ov.matched("wat/bar/lib.rs", false).ignore?.should be_true
    ov.matched("foo", false).whitelist?.should be_true
    ov.matched("wat/foo", false).ignore?.should be_true
    ov.matched("baz", false).ignore?.should be_true
    ov.matched("baz/a", false).whitelist?.should be_true
    ov.matched("baz/a/b", false).whitelist?.should be_true
  end
end

def build_override(root : String, globs : Array(String))
  builder = Dir::Walk::Ignore::OverrideBuilder.new(root)
  globs.each { |g| builder.add(g) }
  builder.build
end
