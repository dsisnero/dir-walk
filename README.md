# dir-walk

High-performance parallel directory traversal for Crystal with full
`.gitignore` / `.ignore` / glob pattern support.

- **Fast**: raw `readdir` syscalls with `d_type` — avoids per-file `lstat`
- **Parallel**: channel-based worker pool — different directories processed
  concurrently by separate fibers
- **Filtered**: respects `.gitignore`, `.ignore`, hidden-file rules, and custom
  override patterns (glob includes/excludes)
- **Safe**: symlink loop detection, configurable depth limits, error handling

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  dir-walk:
    github: dsisnero/dir-walk
```

Then run `shards install`.

## Usage

### Basic walk

```crystal
require "dir-walk"

Dir::Walk.walk(nil, "/some/path") do |path, entry, error|
  puts path
end
```

### Walk with ignore rules

Reads `.gitignore` and `.ignore` files automatically:

```crystal
conf = Dir::Walk::Config.new(ignore: true)
Dir::Walk.walk(conf, "/repo") do |path, entry, error|
  puts path unless error
end
```

### Walk with custom glob includes

Include only files matching a glob pattern (non-matching files are excluded):

```crystal
require "dir-walk"

override = Dir::Walk::Ignore::OverrideBuilder.new("/repo")
  .add("*.rb")
  .add("*.js")
  .build

conf = Dir::Walk::Config.new(ignore: true, overrides: override)
Dir::Walk.walk(conf, "/repo") do |path, entry, error|
  puts path
end
```

Exclude specific files with `!`:

```crystal
override = Dir::Walk::Ignore::OverrideBuilder.new("/repo")
  .add("*.rb")
  .add("!spec/*_spec.rb")
  .build
```

Globs follow `.gitignore` semantics — see the table below for pattern syntax.

### Compute MD5 for each matching file

```crystal
require "digest/md5"

override = Dir::Walk::Ignore::OverrideBuilder.new("/repo")
  .add("*.rb")
  .build

conf = Dir::Walk::Config.new(ignore: true, overrides: override, num_workers: 4)
hashes = Channel({String, String}).new

Dir::Walk.walk(conf, "/repo") do |path, entry, error|
  next if error || !entry || !entry.file?
  hash = Digest::MD5.hexdigest(File.read(path))
  hashes.send({hash, path})
end

hashes.close
while h = hashes.receive?
  puts "#{h[0]}  #{h[1]}"
end
```

The walk callback runs inside each worker fiber — files in different directories
are processed in parallel by separate workers. Results stream back through the
channel as workers finish each directory.

### Walk with options

```crystal
opts = Dir::Walk::Ignore::IgnoreOptions.new(hidden: false, git_ignore: false)
conf = Dir::Walk::Config.new(ignore: true, ignore_opts: opts, num_workers: 4)
Dir::Walk.walk(conf, "/repo") do |path, entry, error|
  puts path
end
```

### How globbing works

Globs follow `.gitignore` semantics — patterns are applied per-directory:

| Pattern | Meaning |
|---------|---------|
| `*.rs` | Matches `.rs` files at any depth |
| `src/*.rs` | Matches `.rs` files only in `src/` |
| `/build` | Anchored to root — matches only `./build` |
| `build/` | Directories only — matches `./build/` not `./build` file |
| `!main.rs` | Negation — whitelists `main.rs` even if parent says `*.rs` |
| `**/foo` | Matches `foo` at any depth |
| `foo/**` | Matches everything inside `foo/` |

### Parallelism

The walker dispatches directories to a fixed-size worker pool. By default
`num_workers` is set to a platform-tuned value (4–32) — different directories
are processed by separate fibers.

The walk callback runs inside a worker fiber. Files in different directories
can be hashed, read, or processed simultaneously. Within a single directory,
entries are processed sequentially by one worker.

For true OS-level parallelism (multiple cores), resize the execution context
at startup:

```crystal
Fiber::ExecutionContext.default.resize(System.cpu_count)
```

Without this, fibers run concurrently one at a time — still correct, and the
channel-based dispatch works either way.

## Documentation

- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Testing](docs/testing.md)

## License

MIT — see [LICENSE](LICENSE).
