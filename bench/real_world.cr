# Real-world benchmark: dir-walk vs fast_find.cr on a large repo
#
# Usage:
#   crystal run bench/real_world.cr -- /path/to/repo

require "../src/dir-walk"
require "../fast_find"
require "file_utils"

target = ARGV[0]?
unless target
  puts "Usage: crystal run bench/real_world.cr -- /path/to/repo"
  exit 1
end

unless Dir.exists?(target)
  puts "Not a directory: #{target}"
  exit 1
end

puts "Benchmarking: #{target}"
all_files = `find '#{target}' -type f -not -path '*/.git/*' 2>/dev/null | wc -l`.strip
git_files = `find '#{target}/.git' -type f 2>/dev/null | wc -l`.strip
puts "  #{all_files} non-.git files, #{git_files} .git files"

runs = 3

# Warm-up
puts "\nWarming up..."
ff_cfg = FastFind::Config.new; ff_cfg.ignore_hidden = false
ff_hid_cfg = FastFind::Config.new  # ignore_hidden defaults to true

2.times do
  Dir::Walk.walk(nil, target) { |_, _, _| }
end

puts "\nBenchmarking #{runs} runs each...\n"

seq_times = [] of Float64
par_times = [] of Float64

runs.times do |i|
  t = Time.measure { Dir::Walk.walk(Dir::Walk::Config.new(num_workers: 1), target) { |_, _, _| } }
  seq_times << t.total_milliseconds
  puts "  dir-walk seq run #{i + 1}: #{t.total_milliseconds.round(2)} ms"
end

runs.times do |i|
  t = Time.measure { Dir::Walk.walk(nil, target) { |_, _, _| } }
  par_times << t.total_milliseconds
  puts "  dir-walk par run #{i + 1}: #{t.total_milliseconds.round(2)} ms"
end

puts "\n--- dir-walk with ignore (skips .git + hidden) ---\n"
ig_times = [] of Float64
runs.times do |i|
  conf = Dir::Walk::Config.new(ignore: true)
  t = Time.measure { Dir::Walk.walk(conf, target) { |_, _, _| } }
  ig_times << t.total_milliseconds
  puts "  dir-walk ignore run #{i + 1}: #{t.total_milliseconds.round(2)} ms"
end

puts "\n--- dir-walk with include *.cr override ---\n"
ov_times = [] of Float64
override = Dir::Walk::Ignore::OverrideBuilder.new(target).add("*.cr").build
runs.times do |i|
  conf = Dir::Walk::Config.new(ignore: true, overrides: override,
    ignore_opts: Dir::Walk::Ignore::IgnoreOptions.new(hidden: false))
  t = Time.measure { Dir::Walk.walk(conf, target) { |_, _, _| } }
  ov_times << t.total_milliseconds
  puts "  dir-walk *.cr only run #{i + 1}: #{t.total_milliseconds.round(2)} ms"
end

puts "\n--- fast_find.cr (all files, ignore_hidden: false) ---\n"
ff_times = [] of Float64
runs.times do |i|
  t = Time.measure { FastFind.find(target, ff_cfg) { |_| } }
  ff_times << t.total_milliseconds
  puts "  fast_find  run #{i + 1}: #{t.total_milliseconds.round(2)} ms"
end

puts "\n--- fast_find.cr (default: ignore_hidden: true, skips .git) ---\n"
ff_hidden_times = [] of Float64
runs.times do |i|
  t = Time.measure { FastFind.find(target, ff_hid_cfg) { |_| } }
  ff_hidden_times << t.total_milliseconds
  puts "  fast_find hidden run #{i + 1}: #{t.total_milliseconds.round(2)} ms"
end

results = {
  "dir-walk (seq)"      => seq_times,
  "dir-walk (par)"      => par_times,
  "dir-walk (ignore)"   => ig_times,
  "dir-walk (*.cr)"     => ov_times,
  "fast_find (no hid)"  => ff_times,
  "fast_find (hidden)"  => ff_hidden_times,
}

puts "\n" + "=" * 60
puts sprintf("%-25s %10s %10s", "Method", "Avg (ms)", "Rel")
puts "=" * 60
baseline = seq_times.sum / seq_times.size
results.each do |name, times|
  avg = times.sum / times.size
  rel = avg / baseline
  puts sprintf("%-25s %10.2f %5.2fx vs seq", name, avg, rel)
end
