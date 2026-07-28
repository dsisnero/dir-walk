# Benchmark: dir-walk vs fast_find.cr directory traversal
#
# Usage:
#   crystal run bench/traverse.cr -- [options]
#
# Options:
#   --depth=N     Directory depth (default: 5)
#   --width=N     Subdirectories per level (default: 5)
#   --files=N     Files per directory (default: 10)
#   --runs=N      Benchmark runs (default: 5)

require "../src/dir-walk"
require "../fast_find"
require "benchmark"
require "file_utils"

# --- Fixture generation ---

def create_tree(root : String, depth : Int32, width : Int32, files_per_dir : Int32)
  stack = [{root, 0}]
  created = 0
  while item = stack.shift?
    dir, level = item
    next if level >= depth
    width.times do |i|
      sub = File.join(dir, "d#{i}_l#{level}")
      Dir.mkdir(sub)
      files_per_dir.times do |j|
        File.write(File.join(sub, "f#{j}.txt"), "x" * 128)
        created += 1
      end
      stack << {sub, level + 1}
    end
  end
  created
end

# --- Benchmark harness ---

depth = (ARGV.find(&.starts_with?("--depth=")) || "--depth=5").split('=')[1].to_i
width = (ARGV.find(&.starts_with?("--width=")) || "--width=5").split('=')[1].to_i
files_per_dir = (ARGV.find(&.starts_with?("--files=")) || "--files=10").split('=')[1].to_i
runs = (ARGV.find(&.starts_with?("--runs=")) || "--runs=5").split('=')[1].to_i

tmpdir = File.join(Dir.tempdir, "dir-walk-bench-#{Process.pid}")
Dir.mkdir(tmpdir)

puts "Creating fixture: depth=#{depth} width=#{width} files=#{files_per_dir} ..."
  total_files = create_tree(tmpdir, depth, width, files_per_dir)
  puts "  #{total_files} files created in #{tmpdir} (#{depth} levels × #{width} subdirs × #{files_per_dir} files)"

if ARGV.includes?("--resize")
  Fiber::ExecutionContext.default.resize(System.cpu_count)
  puts "  Execution context resized to #{System.cpu_count} workers"
end

# Warm-up runs to avoid cold-start bias
puts "\nWarm-up..."
3.times do
  Dir::Walk.walk(nil, tmpdir) { |_, _, _| }
  FastFind.find(tmpdir) { |_| }
end

# --- Benchmark ---

puts "\nBenchmarking #{runs} runs:\n\n"

stats = {} of String => Array(Float64)

# dir-walk (sequential, num_workers = 1)
dirwalk_seq = [] of Float64
runs.times do
  t = Time.measure do
    Dir::Walk.walk(Dir::Walk::Config.new(num_workers: 1), tmpdir) { |_, _, _| }
  end
  dirwalk_seq << t.total_milliseconds
end
stats["dir-walk (seq)"] = dirwalk_seq

# dir-walk (parallel, default workers)
dirwalk_par = [] of Float64
runs.times do
  t = Time.measure do
    Dir::Walk.walk(nil, tmpdir) { |_, _, _| }
  end
  dirwalk_par << t.total_milliseconds
end
stats["dir-walk (par)"] = dirwalk_par

# fast_find.cr
fastfind = [] of Float64
runs.times do
  t = Time.measure do
    FastFind.find(tmpdir) { |_| }
  end
  fastfind << t.total_milliseconds
end
stats["fast_find.cr"] = fastfind

# --- Results ---
puts sprintf("%-25s %10s %10s %10s", "Method", "Min (ms)", "Avg (ms)", "Max (ms)")
puts "-" * 60
stats.each do |name, times|
  min = times.min
  avg = times.sum / times.size
  max = times.max
  puts sprintf("%-25s %10.2f %10.2f %10.2f", name, min, avg, max)
end

# Compare to fast_find (baseline)
baseline = stats["fast_find.cr"].sum / stats["fast_find.cr"].size
puts "\nSpeedup vs fast_find.cr (baseline avg: #{baseline.round(2)} ms):"
stats.each do |name, times|
  next if name == "fast_find.cr"
  avg = times.sum / times.size
  ratio = baseline / avg
  puts sprintf("  %-25s %5.2fx %s", name, ratio, ratio >= 1.0 ? "✓" : "✗")
end

# Wide-shallow test: 1 depth, 100 dirs, 100 files each
puts "\n--- Wide-shallow (depth=1 width=100 files=100) ---\n"
tmpdir2 = File.join(Dir.tempdir, "dir-walk-bench-wide-#{Process.pid}")
Dir.mkdir(tmpdir2)
wide_files = create_tree(tmpdir2, 1, 100, 100)
puts "  #{wide_files} files created"

3.times do
  Dir::Walk.walk(nil, tmpdir2) { |_, _, _| }
  FastFind.find(tmpdir2) { |_| }
end

wide_stats = {} of String => Float64
t = Time.measure { Dir::Walk.walk(Dir::Walk::Config.new(num_workers: 1), tmpdir2) { |_, _, _| } }
wide_stats["dir-walk (seq)"] = t.total_milliseconds
t = Time.measure { Dir::Walk.walk(nil, tmpdir2) { |_, _, _| } }
wide_stats["dir-walk (par)"] = t.total_milliseconds
t = Time.measure { FastFind.find(tmpdir2) { |_| } }
wide_stats["fast_find.cr"] = t.total_milliseconds

puts sprintf("\n%-25s %12s", "Method", "Time (ms)")
puts "-" * 40
wide_stats.each { |n, t| puts sprintf("%-25s %12.2f", n, t) }

ff_time = wide_stats["fast_find.cr"]
puts "\nSpeedup vs fast_find.cr:"
wide_stats.each do |name, t|
  next if name == "fast_find.cr"
  puts sprintf("  %-25s %5.2fx %s", name, ff_time / t, ff_time / t >= 1.0 ? "✓" : "✗")
end

FileUtils.rm_rf(tmpdir2)

# Cleanup
FileUtils.rm_rf(tmpdir)
