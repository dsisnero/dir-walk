require "spec"
require "file_utils"
require "random"
require "../src/dir-walk"

def with_fixtures(files : Hash(String, String), &)
  tempdir = Dir.tempdir
  root = File.join(tempdir, "fastwalk-spec-#{Random.rand(99999999)}")
  symlinks = {} of String => String
  files.each do |rel, contents|
    file = File.join(root, "src", rel)
    Dir.mkdir_p(File.dirname(file))
    if contents.starts_with?("LINK:")
      symlinks[file] = contents.lchop("LINK:")
    else
      File.write(file, contents)
    end
  end
  symlinks.each { |file, dst| File.symlink(dst, file) }
  begin
    yield root
  ensure
    FileUtils.rm_rf(root) if Dir.exists?(root)
  end
end

def with_ignore_files(files : Hash(String, String), &)
  tempdir = Dir.tempdir
  root = File.join(tempdir, "ignore-spec-#{Random.rand(99999999)}")
  files.each do |path, contents|
    file = File.join(root, path)
    Dir.mkdir_p(File.dirname(file))
    File.write(file, contents)
  end
  begin
    yield root
  ensure
    FileUtils.rm_rf(root) if Dir.exists?(root)
  end
end
