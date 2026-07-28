require "./spec_helper"

describe Dir::Walk do
  describe "types" do
    it "SortMode string representation" do
      Dir::Walk::SortMode::SortNone.to_s.should eq("None")
      Dir::Walk::SortMode::SortLexical.to_s.should eq("Lexical")
      Dir::Walk::SortMode::SortFilesFirst.to_s.should eq("FilesFirst")
      Dir::Walk::SortMode::SortDirsFirst.to_s.should eq("DirsFirst")
    end
    it "Config#copy creates independent copy" do
      a = Dir::Walk::Config.new
      c = a.copy
      c.num_workers *= 2
      a.num_workers.should_not eq(c.num_workers)
    end
    it "Config#copy of nil-like works" do
      Dir::Walk::Config.new(num_workers: 0).num_workers.should eq(0)
    end
    it "default_num_workers" do
      Dir::Walk.default_num_workers.should be >= 4
    end
  end

  describe "basic walk" do
    it "walks all files and directories" do
      files = {"foo/foo.go" => "one", "bar/bar.go" => "two", "skip/skip.go" => "skip"}
      want = Set{"", "/src", "/src/bar", "/src/bar/bar.go", "/src/foo", "/src/foo/foo.go", "/src/skip", "/src/skip/skip.go"}
      with_fixtures(files) do |root|
        got = Set(String).new
        mu = Mutex.new
        Dir::Walk.walk(nil, root) do |path, de, err|
          err.should be_nil
          key = path.lchop(root)
          mu.synchronize { got << key }
        end
        got.should eq(want)
      end
    end

    it "calls walk function for symlinks but does not follow" do
      files = {"foo/foo.go" => "one", "bar/bar.go" => "LINK:../foo/foo.go", "symdir" => "LINK:foo", "broken/broken.go" => "LINK:../nonexistent"}
      want = {"" => File::Type::Directory, "/src" => File::Type::Directory, "/src/bar" => File::Type::Directory, "/src/bar/bar.go" => File::Type::Symlink,
              "/src/foo" => File::Type::Directory, "/src/foo/foo.go" => File::Type::File, "/src/symdir" => File::Type::Symlink,
              "/src/broken" => File::Type::Directory, "/src/broken/broken.go" => File::Type::Symlink}
      with_fixtures(files) do |root|
        got = {} of String => File::Type; mu = Mutex.new
        Dir::Walk.walk(nil, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got[path.lchop(root)] = de.type }
        end
        got.should eq(want)
      end
    end

    it "respects SkipDir" do
      files = {"foo/foo.go" => "one", "bar/bar.go" => "two", "skip/skip.go" => "skip"}
      want = Set{"", "/src", "/src/bar", "/src/bar/bar.go", "/src/foo", "/src/foo/foo.go", "/src/skip"}
      with_fixtures(files) do |root|
        got = Set(String).new; mu = Mutex.new
        Dir::Walk.walk(nil, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          key = path.lchop(root)
          mu.synchronize { got << key }
          raise Dir::Walk::ErrSkipDir.new if de.dir? && key.ends_with?("skip")
        end
        got.should eq(want)
      end
    end

    it "SkipAll error propagates from walk function" do
      with_fixtures({"f.txt" => "data"}) do |root|
        expect_raises(Exception, "skip all") do
          Dir::Walk.walk(nil, root) { |_, _, _| raise "skip all" }
        end
      end
    end

    it "raises error from walk function" do
      with_fixtures({"f.txt" => "one"}) do |root|
        expect_raises(Exception, "expected") do
          Dir::Walk.walk(nil, root) { |_, _, _| raise "expected" }
        end
      end
    end

    it "handles non-existent root" do
      expect_raises(File::NotFoundError) do
        Dir::Walk.walk(nil, "/nonexistent/path/12345") { |_, _, _| }
      end
    end

    it "traverses symlinks with ErrTraverseLink" do
      files = {"foo/foo.go" => "one", "bar/bar.go" => "two", "symdir" => "LINK:foo"}
      want = {"" => File::Type::Directory, "/src" => File::Type::Directory, "/src/bar" => File::Type::Directory,
              "/src/bar/bar.go" => File::Type::File, "/src/foo" => File::Type::Directory,
              "/src/foo/foo.go" => File::Type::File, "/src/symdir" => File::Type::Symlink, "/src/symdir/foo.go" => File::Type::File}
      with_fixtures(files) do |root|
        got = {} of String => File::Type; mu = Mutex.new
        Dir::Walk.walk(nil, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got[path.lchop(root)] = de.type }
          raise Dir::Walk::ErrTraverseLink.new if de.symlink?
        end
        got.should eq(want)
      end
    end

    it "follows symlinks with Follow config" do
      files = {"foo/foo.go" => "one", "bar/bar.go" => "two", "foo/symlink" => "LINK:foo.go", "bar/symdir" => "LINK:../foo/", "bar/link1" => "LINK:../foo/"}
      want = {"" => File::Type::Directory, "/src" => File::Type::Directory, "/src/bar" => File::Type::Directory,
              "/src/bar/bar.go" => File::Type::File, "/src/bar/link1" => File::Type::Symlink, "/src/bar/link1/foo.go" => File::Type::File,
              "/src/bar/link1/symlink" => File::Type::Symlink, "/src/bar/symdir" => File::Type::Symlink,
              "/src/bar/symdir/foo.go" => File::Type::File, "/src/bar/symdir/symlink" => File::Type::Symlink,
              "/src/foo" => File::Type::Directory, "/src/foo/foo.go" => File::Type::File, "/src/foo/symlink" => File::Type::Symlink}
      conf = Dir::Walk::Config.new(follow: true)
      with_fixtures(files) do |root|
        got = {} of String => File::Type; mu = Mutex.new
        Dir::Walk.walk(conf, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got[path.lchop(root)] = de.type }
        end
        got.should eq(want)
      end
    end

    it "follows symlinks with ErrTraverseLink+Follow (ignored when Follow true)" do
      files = {"foo/foo.go" => "one", "bar/bar.go" => "two", "foo/symlink" => "LINK:foo.go", "bar/symdir" => "LINK:../foo/", "bar/link1" => "LINK:../foo/"}
      want = {"" => File::Type::Directory, "/src" => File::Type::Directory, "/src/bar" => File::Type::Directory,
              "/src/bar/bar.go" => File::Type::File, "/src/bar/link1" => File::Type::Symlink, "/src/bar/link1/foo.go" => File::Type::File,
              "/src/bar/link1/symlink" => File::Type::Symlink, "/src/bar/symdir" => File::Type::Symlink,
              "/src/bar/symdir/foo.go" => File::Type::File, "/src/bar/symdir/symlink" => File::Type::Symlink,
              "/src/foo" => File::Type::Directory, "/src/foo/foo.go" => File::Type::File, "/src/foo/symlink" => File::Type::Symlink}
      conf = Dir::Walk::Config.new(follow: true)
      with_fixtures(files) do |root|
        got = {} of String => File::Type; mu = Mutex.new
        Dir::Walk.walk(conf, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got[path.lchop(root)] = de.type }
          if de.symlink?
            fi = Dir::Walk.stat_dir_entry(path, de) rescue nil
            raise Dir::Walk::ErrTraverseLink.new if fi.try(&.directory?)
          end
        end
        got.should eq(want)
      end
    end

    it "respects SkipDir with Follow" do
      files = {".dot/baz.go" => "one", "bar/bar.go" => "three", "bar/dot" => "LINK:../.dot/", "bar/symdir" => "LINK:../foo/", "foo/foo.go" => "two", "foo/symlink" => "LINK:foo.go"}
      want = {"" => File::Type::Directory, "/src" => File::Type::Directory, "/src/.dot" => File::Type::Directory,
              "/src/bar" => File::Type::Directory, "/src/bar/bar.go" => File::Type::File, "/src/bar/dot" => File::Type::Symlink,
              "/src/bar/dot/baz.go" => File::Type::File, "/src/bar/symdir" => File::Type::Symlink,
              "/src/bar/symdir/foo.go" => File::Type::File, "/src/bar/symdir/symlink" => File::Type::Symlink,
              "/src/foo" => File::Type::Directory, "/src/foo/foo.go" => File::Type::File, "/src/foo/symlink" => File::Type::Symlink}
      conf = Dir::Walk::Config.new(follow: true)
      with_fixtures(files) do |root|
        got = {} of String => File::Type; mu = Mutex.new
        Dir::Walk.walk(conf, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got[path.lchop(root)] = de.type }
          raise Dir::Walk::ErrSkipDir.new if de.name.starts_with?('.')
        end
        got.should eq(want)
      end
    end

    it "detects and ignores symlink loops with Follow" do
      d = File.join(Dir.tempdir, "fwl-#{Random.rand(9999)}")
      Dir.mkdir_p(File.join(d, "src")); File.write(File.join(d, "src/foo.go"), "x"); File.symlink("../src", File.join(d, "src/loop"))
      conf = Dir::Walk::Config.new(follow: true); count = 0
      begin
        Dir::Walk.walk(conf, d) do |_, _, err|
          err.should be_nil; count += 1; raise "loop: #{count}" if count > 20
        end
        count.should be < 20
      ensure
        FileUtils.rm_rf(d) if Dir.exists?(d)
      end
    end

    it "ignores ErrTraverseLink when Follow true and would cause loop" do
      files = {"foo/foo.go" => "one", "bar/bar.go" => "two", "bar/symdir" => "LINK:../foo/", "bar/loop" => "LINK:../bar/"}
      want = {"" => File::Type::Directory, "/src" => File::Type::Directory, "/src/bar" => File::Type::Directory,
              "/src/bar/bar.go" => File::Type::File, "/src/bar/loop" => File::Type::Symlink, "/src/bar/symdir" => File::Type::Symlink,
              "/src/bar/symdir/foo.go" => File::Type::File, "/src/foo" => File::Type::Directory, "/src/foo/foo.go" => File::Type::File}
      conf = Dir::Walk::Config.new(follow: true)
      with_fixtures(files) do |root|
        got = {} of String => File::Type; mu = Mutex.new
        Dir::Walk.walk(conf, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got[path.lchop(root)] = de.type }
          if de.symlink?
            fi = Dir::Walk.stat_dir_entry(path, de) rescue nil
            raise Dir::Walk::ErrTraverseLink.new if fi.try(&.directory?)
          end
        end
        got.should eq(want)
      end
    end
  end

  describe "DirEntry" do
    it "returns correct depth" do
      d = File.join(Dir.tempdir, "fwd-#{Random.rand(9999)}")
      Dir.mkdir_p(File.join(d, "a1/a2/a3")); File.write(File.join(d, "a1/a2/a3/a4.txt"), "x")
      begin
        Dir::Walk.walk(nil, d) do |_, de, _|
          de.try { |x| x.depth.should eq(4) if x.name == "a4.txt" }
        end
      ensure
        FileUtils.rm_rf(d) if Dir.exists?(d)
      end
    end
    it "StatDirEntry works" do
      with_fixtures({"f.txt" => "data"}) do |root|
        Dir::Walk.walk(nil, root) do |path, de, _|
          de.try { |x| Dir::Walk.stat_dir_entry(path, x).size.should eq(4) if x.name == "f.txt" }
        end
      end
    end
    it "DirEntryDepth helper" do
      d = File.join(Dir.tempdir, "fwd2-#{Random.rand(9999)}")
      Dir.mkdir_p(File.join(d, "a1/a2/a3")); File.write(File.join(d, "a1/a2/a3/a4.txt"), "x")
      begin
        Dir::Walk.walk(nil, d) do |_, de, _|
          de.try { |x| Dir::Walk.dir_entry_depth(x).should eq(4) if x.name == "a4.txt" }
        end
      ensure
        FileUtils.rm_rf(d) if Dir.exists?(d)
      end
    end
  end

  describe "Config" do
    it "cleans root path" do
      root_path = ""
      begin
        Dir::Walk.walk(nil, "///") { |path, _, _| root_path = path if root_path.empty?; raise "stop" }
      rescue
      end
      root_path.should eq("/")
    end
    it "default config" do
      c = Dir::Walk::Config.new
      c.follow.should be_false; c.sort.should eq(Dir::Walk::SortMode::SortNone); c.max_depth.should eq(0)
    end
    it "max_depth with symlinks via Follow" do
      files = {"d1/d2/f3.txt" => "one", "symdir1" => "LINK:d1", "symdir2" => "LINK:d1/d2"}
      want = {"" => File::Type::Directory, "/src" => File::Type::Directory, "/src/d1" => File::Type::Directory,
              "/src/d1/d2" => File::Type::Directory, "/src/symdir1" => File::Type::Symlink, "/src/symdir1/d2" => File::Type::Directory,
              "/src/symdir2" => File::Type::Symlink, "/src/symdir2/f3.txt" => File::Type::File}
      conf = Dir::Walk::Config.new(follow: true, max_depth: 3)
      with_fixtures(files) do |root|
        got = {} of String => File::Type; mu = Mutex.new
        Dir::Walk.walk(conf, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got[path.lchop(root)] = de.type }
        end
        got.should eq(want)
      end
    end
    it "max_depth without follow" do
      files = {"d1/d2/f3.txt" => "one", "symdir1" => "LINK:d1", "symdir2" => "LINK:d1/d2"}
      want = {"" => File::Type::Directory, "/src" => File::Type::Directory, "/src/d1" => File::Type::Directory,
              "/src/d1/d2" => File::Type::Directory, "/src/symdir1" => File::Type::Symlink, "/src/symdir2" => File::Type::Symlink}
      conf = Dir::Walk::Config.new(follow: false, max_depth: 3)
      with_fixtures(files) do |root|
        got = {} of String => File::Type; mu = Mutex.new
        Dir::Walk.walk(conf, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got[path.lchop(root)] = de.type }
        end
        got.should eq(want)
      end
    end
    it "max_depth limits traversal" do
      files = {"d1/d2/d3/f4.txt" => "data"}
      conf = Dir::Walk::Config.new(max_depth: 2)
      with_fixtures(files) do |root|
        got = Set(String).new; mu = Mutex.new
        Dir::Walk.walk(conf, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got << path.lchop(root) }
        end
        got.should contain(""); got.should contain("/src"); got.should contain("/src/d1")
        got.should_not contain("/src/d1/d2")
      end
    end
  end

  describe "permission error handling" do
    it "ignores permission errors on unreadable directories" do
      {% if flag?(:win32) %}; pending "not supported on Windows"; return; {% end %}
      d = File.join(Dir.tempdir, "fwp-#{Random.rand(9999)}")
      Dir.mkdir_p(d)
      bad = File.join(d, "bad"); Dir.mkdir(bad, 0o755); File.write(File.join(bad, "bad.txt"), "x")
      File.chmod(bad, 0o355)
      begin
        got = Set(String).new; mu = Mutex.new
        Dir::Walk.walk(nil, d) do |path, de, err|
          if err && err.is_a?(File::AccessDeniedError)
            next
          end
          de = de.not_nil!; mu.synchronize { got << path.lchop(d) }
        end
        got.should contain(""); got.should contain("/bad")
        got.should_not contain("/bad/bad.txt")
      ensure
        File.chmod(bad, 0o755) rescue nil
        File.delete(File.join(bad, "bad.txt")) rescue nil
        File.delete(bad) rescue nil
        FileUtils.rm_rf(d) if Dir.exists?(d)
      end
    end
  end

  describe "ErrSkipFiles" do
    it "skips remaining files in directory" do
      files = {"a_skip.go" => "a", "b_skip.go" => "b", "zzz/c.go" => "c"}
      with_fixtures(files) do |root|
        got = Set(String).new; mu = Mutex.new
        Dir::Walk.walk(nil, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          key = path.lchop(root); mu.synchronize { got << key }
          raise Dir::Walk::ErrSkipFiles.new if key.ends_with?("_skip.go")
        end
        got.should contain(""); got.should contain("/src"); got.should contain("/src/zzz"); got.should contain("/src/zzz/c.go")
        (got.includes?("/src/a_skip.go") || got.includes?("/src/b_skip.go")).should be_true
        got.size.should be <= 5
      end
    end
  end

  describe "sorting" do
    it "SortLexical visits entries alphabetically" do
      conf = Dir::Walk::Config.new(sort: Dir::Walk::SortMode::SortLexical)
      with_fixtures({"z.txt" => "z", "a.txt" => "a"}) do |root|
        got = [] of String; mu = Mutex.new
        Dir::Walk.walk(conf, root) do |_, de, _|
          de.try { |x| mu.synchronize { got << x.name } unless x.dir? }
        end
        got.should eq(["a.txt", "z.txt"])
      end
    end
    it "handles long file names" do
      d = File.join(Dir.tempdir, "fwl2-#{Random.rand(9999)}")
      Dir.mkdir_p(d); want = Set{""}
      ("a".."b").each do |r|
        rs = r.to_s; long = rs * 256; dir = File.join(d, rs)
        Dir.mkdir(dir); want << "/#{rs}"
        [1, 10, 50, 100, 200, 255].each do |n|
          File.write(File.join(dir, long[0, n]), "x"); want << "/#{rs}/#{long[0, n]}"
        end
      end
      begin
        got = Set(String).new; mu = Mutex.new
        Dir::Walk.walk(nil, d) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got << path.lchop(d) }
        end
        got.should eq(want)
      ensure
        FileUtils.rm_rf(d) if Dir.exists?(d)
      end
    end
    it "handles deeply nested paths" do
      d = File.join(Dir.tempdir, "fwd3-#{Random.rand(9999)}")
      Dir.mkdir_p(d); cur = d
      ("a".."j").each { |p| cur = File.join(cur, p); Dir.mkdir(cur) }
      File.write(File.join(cur, "file.txt"), "x")
      begin
        got = Set(String).new; mu = Mutex.new
        Dir::Walk.walk(nil, d) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got << path.lchop(d) }
        end
        got.should contain(""); got.should contain("/a/b/c/d/e/f/g/h/i/j"); got.should contain("/a/b/c/d/e/f/g/h/i/j/file.txt")
        got.size.should eq(12)
      ensure
        FileUtils.rm_rf(d) if Dir.exists?(d)
      end
    end
    it "SortFilesFirst visits files before non-files" do
      conf = Dir::Walk::Config.new(sort: Dir::Walk::SortMode::SortFilesFirst)
      d = File.join(Dir.tempdir, "fws-#{Random.rand(9999)}"); Dir.mkdir_p(d)
      Dir.mkdir(File.join(d, "subdir")); File.write(File.join(d, "a.txt"), "a"); File.symlink(File.join(d, "a.txt"), File.join(d, "z.lnk"))
      begin
        got = [] of {String, Bool}; mu = Mutex.new
        Dir::Walk.walk(conf, d) do |_, de, _|
          de.try { |x| mu.synchronize { got << {x.name, x.file?} } unless x.dir? }
        end
        fi = got.index { |(_, f)| f }; nfi = got.index { |(_, f)| !f }
        (fi < nfi).should be_true if fi && nfi
      ensure
        FileUtils.rm_rf(d) if Dir.exists?(d)
      end
    end
    it "works with multiple workers configured" do
      files = {} of String => String; 6.times { |i| files["d#{i}/f.txt"] = "data" }
      conf = Dir::Walk::Config.new(num_workers: 4)
      with_fixtures(files) do |root|
        got = Set(String).new; mu = Mutex.new
        Dir::Walk.walk(conf, root) do |path, de, err|
          err.should be_nil; de = de.not_nil!
          mu.synchronize { got << path.lchop(root) }
        end
        got.size.should be >= 8
        got.should contain(""); got.should contain("/src")
        6.times { |i| got.should contain("/src/d#{i}") }
      end
    end

    it "uses multiple fibers with parallel workers" do
      files = {} of String => String
      10.times { |i| files["d#{i}/f.txt"] = "data" }
      fibers = Set(UInt64).new; mu = Mutex.new
      conf = Dir::Walk::Config.new(num_workers: 8)
      with_fixtures(files) do |root|
        Dir::Walk.walk(conf, root) do |_, _, _|
          mu.synchronize { fibers << Fiber.current.object_id }
        end
      end
      fibers.size.should be >= 2
    end
  end
end
