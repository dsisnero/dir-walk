#!/usr/bin/env crystal
# Usage: crystal run examples/fdlike.cr -- [options] <pattern> <dir>
#        crystal build examples/fdlike.cr -o fdlike && ./fdlike "*.rb" /repo

require "../src/dir-walk"
require "option_parser"
require "digest/md5"

dir = "."
Fiber::ExecutionContext.default.resize(System.cpu_count)

args = ARGV.dup
show_md5 = args.delete("--md5") ? true : false
show_help = args.delete("--help") || args.delete("-h") ? true : false

pattern = args[0]? || "*"
dir = args[1]? || "."

if show_help
  puts "Usage: #{PROGRAM_NAME} [--md5] <pattern> [directory]"
  puts "  --md5    Print md5:path instead of just path"
  exit 0
end

override = Dir::Walk::Ignore::OverrideBuilder.new(dir)
  .add(pattern)
  .build

conf = Dir::Walk::Config.new(ignore: true, overrides: override,
  ignore_opts: Dir::Walk::Ignore::IgnoreOptions.new(hidden: false))

results = Channel({String, String?}).new

spawn do
  Dir::Walk.walk(conf, dir) do |path, entry, error|
    next if error || !entry || !entry.file?
    next if File.basename(path).starts_with?("._")
    if show_md5
      hash = Digest::MD5.hexdigest(File.read(path))
      results.send({path, hash})
    else
      results.send({path, nil})
    end
  end
  results.close
end

while item = results.receive?
  path, hash = item
  if hash
    puts "#{path}: #{hash}"
  else
    puts path
  end
end
