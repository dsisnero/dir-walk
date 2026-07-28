require "./spec_helper"

describe "Walk + Ignore integration" do
  it "walks all files without ignore" do
    with_ignore_files({"src/foo.rs" => "rust", "src/bar.go" => "golang", "Cargo.lock" => "lock"}) do |dir|
      got = Set(String).new; mu = Mutex.new
      Dir::Walk.walk(nil, dir) do |path, de, err|
        err.should be_nil
        mu.synchronize { got << path.lchop(dir) }
      end
      got.should contain("")
      got.should contain("/src")
      got.should contain("/src/foo.rs")
      got.should contain("/src/bar.go")
      got.should contain("/Cargo.lock")
    end
  end

  it "ignores files matching .gitignore patterns" do
    with_ignore_files({"src/.gitignore" => "*.rs", "src/foo.rs" => "rust", "src/bar.go" => "golang"}) do |dir|
      conf = Dir::Walk::Config.new(ignore: true)
      got = Set(String).new; mu = Mutex.new
      Dir::Walk.walk(conf, dir) do |path, de, err|
        err.should be_nil
        mu.synchronize { got << path.lchop(dir) }
      end
      got.should contain("/src/bar.go")
      got.should_not contain("/src/foo.rs")
    end
  end

  it "ignores files matching root .gitignore" do
    with_ignore_files({".gitignore" => "*.lock", "src/foo.rs" => "rust", "src/Cargo.lock" => "lock"}) do |dir|
      conf = Dir::Walk::Config.new(ignore: true)
      got = Set(String).new; mu = Mutex.new
      Dir::Walk.walk(conf, dir) do |path, de, err|
        err.should be_nil
        mu.synchronize { got << path.lchop(dir) }
      end
      got.should contain("/src/foo.rs")
      got.should_not contain("/src/Cargo.lock")
    end
  end

  it "whitelist in child .gitignore overrides parent" do
    with_ignore_files({".gitignore" => "*.rs", "src/.gitignore" => "!foo.rs",
                       "src/foo.rs" => "rust", "src/bar.rs" => "rust"}) do |dir|
      conf = Dir::Walk::Config.new(ignore: true)
      got = Set(String).new; mu = Mutex.new
      Dir::Walk.walk(conf, dir) do |path, de, err|
        err.should be_nil
        mu.synchronize { got << path.lchop(dir) }
      end
      got.should contain("/src/foo.rs")
      got.should_not contain("/src/bar.rs")
    end
  end

  it "respects directory-only gitignore patterns" do
    with_ignore_files({"src/.gitignore" => "build/", "src/build/obj.o" => "obj",
                       "src/main.rs" => "rust", "src/lib.rs" => "rust"}) do |dir|
      conf = Dir::Walk::Config.new(ignore: true)
      got = Set(String).new; mu = Mutex.new
      Dir::Walk.walk(conf, dir) do |path, de, err|
        err.should be_nil
        mu.synchronize { got << path.lchop(dir) }
      end
      got.should contain("/src/main.rs")
      got.should contain("/src/lib.rs")
      got.should_not contain("/src/build")
      got.should_not contain("/src/build/obj.o")
    end
  end

  it "skips hidden files by default with ignore enabled" do
    with_ignore_files({"src/.hidden.txt" => "secret", "src/visible.txt" => "public"}) do |dir|
      conf = Dir::Walk::Config.new(ignore: true)
      got = Set(String).new; mu = Mutex.new
      Dir::Walk.walk(conf, dir) do |path, de, err|
        err.should be_nil
        mu.synchronize { got << path.lchop(dir) }
      end
      got.should contain("/src/visible.txt")
      got.should_not contain("/src/.hidden.txt")
    end
  end

  it "does not skip hidden files when ignore.hidden is false" do
    with_ignore_files({"src/.hidden.txt" => "secret", "src/visible.txt" => "public"}) do |dir|
      opts = Dir::Walk::Ignore::IgnoreOptions.new(hidden: false)
      conf = Dir::Walk::Config.new(ignore: true, ignore_opts: opts)
      got = Set(String).new; mu = Mutex.new
      Dir::Walk.walk(conf, dir) do |path, de, err|
        err.should be_nil
        mu.synchronize { got << path.lchop(dir) }
      end
      got.should contain("/src/.hidden.txt")
      got.should contain("/src/visible.txt")
    end
  end

  it "include override only includes matching files" do
    with_ignore_files({"src/foo.rb" => "ruby", "src/bar.go" => "golang",
                       "src/baz.rb" => "ruby2"}) do |dir|
      ov = Dir::Walk::Ignore::OverrideBuilder.new(dir)
        .add("*.rb")
        .build
      conf = Dir::Walk::Config.new(ignore: true, overrides: ov,
        ignore_opts: Dir::Walk::Ignore::IgnoreOptions.new(hidden: false))
      got = Set(String).new; mu = Mutex.new
      Dir::Walk.walk(conf, dir) do |path, de, err|
        err.should be_nil
        mu.synchronize { got << path.lchop(dir) }
      end
      got.should contain("/src/foo.rb")
      got.should contain("/src/baz.rb")
      got.should_not contain("/src/bar.go")
    end
  end

  it "exclude override skips matching files" do
    with_ignore_files({"src/foo.rb" => "ruby", "src/bar.go" => "golang"}) do |dir|
      ov = Dir::Walk::Ignore::OverrideBuilder.new(dir)
        .add("!*.go")
        .build
      conf = Dir::Walk::Config.new(ignore: true, overrides: ov,
        ignore_opts: Dir::Walk::Ignore::IgnoreOptions.new(hidden: false))
      got = Set(String).new; mu = Mutex.new
      Dir::Walk.walk(conf, dir) do |path, de, err|
        err.should be_nil
        mu.synchronize { got << path.lchop(dir) }
      end
      got.should contain("/src/foo.rb")
      got.should_not contain("/src/bar.go")
    end
  end

  it "include override excludes non-matching files even without .gitignore" do
    with_ignore_files({"a.txt" => "text", "b.rs" => "rust"}) do |dir|
      ov = Dir::Walk::Ignore::OverrideBuilder.new(dir)
        .add("*.rs")
        .build
      conf = Dir::Walk::Config.new(ignore: true, overrides: ov,
        ignore_opts: Dir::Walk::Ignore::IgnoreOptions.new(hidden: false))
      got = Set(String).new; mu = Mutex.new
      Dir::Walk.walk(conf, dir) do |path, de, err|
        err.should be_nil
        mu.synchronize { got << path.lchop(dir) }
      end
      got.should contain("/b.rs")
      got.should_not contain("/a.txt")
    end
  end

  it "disables gitignore processing when git_ignore is false" do
    with_ignore_files({"src/.gitignore" => "*.rs", "src/foo.rs" => "rust"}) do |dir|
      opts = Dir::Walk::Ignore::IgnoreOptions.new(git_ignore: false, hidden: false)
      conf = Dir::Walk::Config.new(ignore: true, ignore_opts: opts)
      got = Set(String).new; mu = Mutex.new
      Dir::Walk.walk(conf, dir) do |path, de, err|
        err.should be_nil
        mu.synchronize { got << path.lchop(dir) }
      end
      got.should contain("/src/foo.rs")
    end
  end
end
