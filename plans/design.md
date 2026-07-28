# The Fastest Crystal Directory Walker: Design & Implementation Plan

## Goal

Combine `charlievieth/fastwalk` (parallel directory traversal) with
`BurntSushi/ripgrep`'s `crates/ignore` (glob/ignore/file-type matching) into
a single, maximally-performant Crystal library.

---

## 1. What Makes Each Upstream Fast

### charlievieth/fastwalk (Go)

| Technique | Why It's Fast |
|-----------|---------------|
| **Raw `readdir` syscall** | On Linux: `getdents(2)` over `open(2)`+`readdir(3)`. On Darwin: `getdirentries64` over `opendir`+`readdir`. Avoids libc per-entry locking/allocation. |
| **Platform-specialized readDir** | `fastwalk_darwin.go` vs `fastwalk_unix.go` vs `fastwalk_portable.go`. Each uses the fastest available syscall. |
| **`d_type` from dirent** | Skips `lstat(2)` call for each entry when the filesystem provides the type in the directory entry (ext4, btrfs, apfs, etc.). Only falls back to `lstat` for `DT_UNKNOWN`. |
| **Zero-inode skip** | On macOS, entries with `d_ino == 0` are deleted-but-not-removed; skipping them avoids a useless `lstat`. |
| **EINTR retry** | Retries `open` and `ReadDirent` on `EINTR` instead of propagating error. |
| **Batched channel dispatch** | Workers read from `workc`, send results to `resc`, and enqueue subdirs on `enqueuec`. Main goroutine multiplexes these three channels in a single `select` loop. Buffered channels (size = numWorkers) prevent stalls. |
| **`sync.Pool` for dirent slices** | Reuses `[]*unixDirent` across sort-enabled walks, capping at 256KB to avoid holding large allocations. |
| **sync.Once / atomic lazy Info/Stat** | `fileInfo` uses `sync.Once` + atomic CAS to compute `Info()`/`Stat()` at most once per dirent. |
| **Minimal string allocations** | Compares name bytes against `"."` and `".."` before calling `string(name)`. |
| **Size-bounded work queue** | The main loop's `todo` slice averages ~170 entries and is bounded by the rate of enqueue/dequeue, preventing unbounded memory growth. |
| **Depth limit checked before readDir** | Avoids entering a directory at all when `MaxDepth` is exceeded. |
| **Follow-symlink loop detection** | `shouldSkipDir` tracks all previously-entered dir `FileInfo`s via `os.SameFile`. |

### BurntSushi/ripgrep crates/ignore (Rust)

| Technique | Why It's Fast |
|-----------|---------------|
| **`GlobSet` compiled from all globs** | All `.gitignore`/`.ignore` globs for a directory are compiled into a single regex set via `globset`. Matching is O(n) over the glob count, with globs ordered by precedence. |
| **`Candidate` / `matches_candidate_into`** | Uses `regex-automata`'s meta regex engine for multi-pattern matching. The `Pool<Vec<usize>>` avoids allocating match storage per call. |
| **Arc/Rc sharing across hierarchy** | `IgnoreInner` uses `Arc` + persistent data structure so that child directories share parent matchers. Adding a child is O(1) pointer bump + optional file reads. |
| **IgnoreFile probing via readdir** | `add_child_with_entries` accepts the `readdir` results directly — instead of stat-ing `.gitignore`, `.ignore`, `.git`, `.jj` individually, it checks entry names from the already-read directory listing. Zero extra syscalls. |
| **Short-circuit on empty** | Every `matched()` call checks `is_empty()` first — returns `Match::None` immediately if no rules exist. |
| **Override > gitignore > types > hidden** | Evaluated in strict precedence order so that whitelist overrides short-circuit all other checks. |
| **git-required barrier** | `require_git` means `.gitignore` rules are skipped entirely when walking outside a git repo. |
| **`matched_path_or_any_parents`** | Walks parent directory matchers only while `any_git` holds, stopping at the first `.git` boundary. |
| **`is_hidden_entry` cheap check** | Hidden-file detection checks the file name only — no stat required. |
| **`create_gitignore` skips missing files** | Uses `path.exists()` check before opening — a stat call that's cheaper than open+read on many systems. |

---

## 2. Shared Design Principles (Both Upstreams)

Both fastwalk and ripgrep/ignore independently converge on the same principles:

1. **Minimize syscalls** — batch reads, avoid stat when d_type suffices, skip missing files without opening them.
2. **Platform specialization** — the fastest I/O path differs per OS. Abstract the walker but specialize the readdir.
3. **Lazy evaluation** — `Info()`/`Stat()` are computed only on demand, only once, and cached.
4. **Share-and-clone immutable state** — parent ignore rules are shared via reference-counted pointers (Arc in Rust, implicit in Go closures).
5. **Pre-compile globs** — glob patterns are compiled into a set once, then matching is fast membership checks.
6. **Short-circuit always** — check empty/none/noop paths before any work.
7. **Channel-based concurrency** — Go uses goroutines+channels directly; Rust's `WalkParallel` uses `rayon` internally. Both use fixed-size worker pools.

---

## 3. Crystal Architecture

```
┌─────────────────────────────────────────┐
│              Dir::Walk.walk              │  Public API
├─────────────────────────────────────────┤
│           Dir::Walk::Walker              │  Core traversal + ignore integration
├──────────────┬──────────────────────────┤
│   fastwalk   │   ripgrep/ignore          │
│   readdir    │   gitignore matching      │
│   platform   │   .ignore matching        │
│   d_type     │   file type matching      │
│   workers    │   override globs          │
│   symlinks   │   hidden-file filter      │
└──────────────┴──────────────────────────┘
```

### Module Layout

```
src/dir-walk.cr              # Require all submodules
src/dir-walk/
├── dirent.cr                # DirEntry, Config, SortMode, sentinel errors
├── walker.cr                # Config, Walk entry point (top-level dispatch)
├── raw_dirent.cr            # LibC.opendir/readdir/closedir wrapper
├── adapters.cr              # Walk function adapters (ignore_*, stat helpers)
├── platform/
│   ├── darwin.cr            # Darwin-optimized readdir (getdirentries64)
│   └── unix.cr              # Generic POSIX readdir
├── worker_pool.cr           # Fiber-based parallel worker pool (channels)
├── ignore/
│   ├── matcher.cr           # Ignore: top-level matching logic
│   ├── gitignore.cr          # .gitignore parser / Glob / Gitignore
│   ├── overrides.cr          # Override globs
│   ├── types.cr              # File type definitions
│   ├── glob_set.cr           # Globs → compiled set for fast matching
│   └── pathutil.cr           # is_hidden, strip_prefix, file_name
spec/
├── spec_helper.cr
├── dir-walk_spec.cr          # fastwalk parity tests (existing + new)
└── ignore_spec.cr            # ripgrep ignore/glob parity tests
```

### Key Crystal Design Decisions

#### 3.1 Worker Pool (Parallel Walk)

- Use `Channel` for work dispatch (matching fastwalk's `workc`/`enqueuec`/`resc`)
- Fixed-size worker pool of `num_workers` fibers consuming from `workc`
- Main fiber dispatches from a `Deque(WorkItem)` (backed by `Array`), multiplexing:
  1. Send work to idle workers (`workc`)
  2. Receive enqueued subdirectories from workers (`enqueuec`)
  3. Receive results/errors from workers (`resc`)
- Buffered channels: capacity = `num_workers`
- Guards: track `outstanding` counter — when `outstanding == 0 && todo.empty?`, drain `enqueuec` one last time, then return

```
Main fiber:
  todo = [root_entry]
  loop:
    select:
    workc <- todo.pop      # give work to a worker
    enqueuec <- it          # worker enqueued a subdir
    resc <- err             # worker finished a directory
      if outstanding==0 && todo.empty?:
        drain enqueuec one more time
        return
```

```
Worker fiber:
  loop:
    it = workc.receive
    if callback not yet done, call walk_fn
    if depth < max_depth:
      read_dir(dir_path, depth+1):
        for each entry:
          if dir:
            enqueuec.send({joined, de, callback_done: false})
          else:
            walk_fn.call(file_path, de, nil)
    resc.send(nil_or_error)
```

#### 3.2 Platform readdir

- **Unix (generic)**: `LibC.opendir` + `LibC.readdir` + `d_type` (already done in `raw_dirent.cr`)
- **Darwin**: `getdirentries64` via `LibC` for batch reads (future, lower priority)
- Skip zero-inode entries on BSD/macOS
- Skip `"."` and `".."` at byte level before string allocation

#### 3.3 Ignore System

Modeled after ripgrep's `Ignore` family:

```crystal
class Ignore::Matcher
  # Build once per root. Add child matchers during walk.
  # Each matcher encapsulates:
  #   - override globs (highest precedence)
  #   - custom ignore file matchers (.customignore, etc.)
  #   - .ignore matcher
  #   - .gitignore matcher
  #   - .git/info/exclude matcher
  #   - global gitignore matcher ($XDG_CONFIG_HOME/git/ignore)
  #   - file type matcher
  #   - hidden file setting
  #   - parent matcher (chained for hierarchy)

  def matched(path, is_dir) : Match
    # 1. Check overrides first (short-circuit on whitelist/ignore)
    # 2. Check ignore files (custom > .ignore > .gitignore > exclude > global)
    # 3. Check file types
    # 4. Check hidden
  end

  def add_child(dir_path, entries = nil) : Matcher
    # If entries provided, scan for .gitignore/.ignore/.git/.jj names
    # without extra stats. Otherwise, stat individually.
    # Create new matcher sharing parent's compiled globs + overrides via reference.
  end
end
```

#### 3.4 GlobSet

ripgrep uses `globset` + `regex-automata` for multi-pattern matching. There is no
Crystal equivalent with matching performance. Options:

| Option | Pros | Cons |
|--------|------|------|
| **A) Port a minimal glob-to-regex compiler + regex set** | No runtime dependency; full control | Significant implementation effort |
| **B) Use Crystal's `Regex` + concatenated pattern** `^(p1)$|^(p2)$|...` | Simple; fast enough for moderate glob counts | Slow with many patterns; no literal_separator semantics |
| **C) Use `glob` shard** (if available/suitable) | Quick to implement | May not match gitignore semantics |
| **D) Iterate globs linearly** | Simple; predictable | O(globs) per match — fine for small sets, poor for large |

**Recommendation**: Start with (D) for correctness, optimize to (B) or (A) with
detailed benchmarks. ripgrep's `GlobSet` typically has <100 globs per directory,
so linear iteration with `File.match?` may be fast enough.

#### 3.5 Integration Points

The walker and ignore matcher must interact at two points:

1. **Before queuing a directory** (`on_dir_ent`-equivalent):
   - Check `matcher.matched(dir_path, is_dir: true)`
   - If `Match::Ignore` → skip (like `ErrSkipDir`)
   - Otherwise → enqueue

2. **Before calling walk_fn for a file** (`on_dir_ent`-equivalent):
   - Check `matcher.matched(file_path, is_dir: false)`
   - If `Match::Ignore` → skip file
   - Otherwise → call walk_fn

The matcher is created once per root and cloned via `add_child` for each subdirectory.
Since the matcher tree is immutable (persistent), it can be shared across worker fibers
without synchronization.

---

## 4. Testing Strategy

### Phase 1: Fastwalk Parity (already ~80% done)

- Port remaining upstream Go tests to Crystal specs
- Tracked in `plans/inventory/fastwalk-parity.md`

### Phase 2: Ignore/Glob Parity

- Port ripgrep `gitignore.rs` tests to Crystal specs
- Port ripgrep `overrides.rs` tests
- Port ripgrep `types.rs` tests
- Port ripgrep `dir.rs` tests (IgnoreBuilder)
- Port ripgrep `walk.rs` tests (integration: walk + ignore together)
- Each test creates a temp directory with specific ignore files, walks it, asserts which paths are visited

Test categories:
- **.gitignore patterns**: `/foo`, `foo/`, `*.rs`, `**/foo`, `!negations`, whitespace handling, comments, escaped chars
- **.ignore patterns**: same as gitignore semantics
- **Custom ignore files**: .customignore, multiple custom filenames with precedence
- **Overrides**: `--include`, `--exclude` semantics (whitelist > ignore)
- **File types**: `--type rust` selects `*.rs`, `--type-not c` excludes `*.c`
- **Hidden files**: default-on filtering of `.*`, skip-dir vs skip-file
- **Parent hierarchy**: gitignore in parent applies to child
- **Git barrier**: gitignore stops at `.git` directory boundary
- **`require_git`**: rules apply only when `.git` exists
- **`no_require_git`**: rules apply everywhere
- **Global gitignore**: `$XDG_CONFIG_HOME/git/ignore` respected
- **Symlink handling**: ignore rules + symlinks interaction

### Phase 3: Integration Tests

- Walk with ignore rules applied
- Walk with overrides
- Walk with file type selection
- Verify error handling (partial errors, I/O errors)

### Phase 4: Performance Benchmarks

Crystal benchmark harnesses (using `Benchmark` module or similar):

| Benchmark | What It Measures |
|-----------|-----------------|
| `BenchmarkFastWalk_Normal` | Cold traversal of typical source tree (e.g., Crystal compiler src) |
| `BenchmarkFastWalk_Gitignored` | Traversal with .gitignore, .ignore files (e.g., $HOME or large repo) |
| `BenchmarkFastWalk_Empty` | Traversal of empty directory |
| `BenchmarkFastWalk_Deep` | Deeply nested directory tree (1000+ levels) |
| `BenchmarkFastWalk_Wide` | Flat directory with 10K files |
| `BenchmarkFastWalk_Mixed` | Mixed hierarchy — 100 dirs × 100 files |
| `BenchmarkFastWalk_NumWorkers` | Sweep 1..32 workers to find optimal |
| `BenchmarkIgnore_Globs` | Match path against glob sets of varying size |
| `BenchmarkIgnore_RealWorld` | Full walk of a large repo with ignore rules |

Compare against:
- Crystal `Dir.glob` / `Dir.[]`
- Crystal `FileUtils` recursive operations
- `find` command (via shell)
- Go fastwalk (via `go test -bench`)
- ripgrep's own `Walk` iterator (via `cargo bench`)

---

## 5. Phased Implementation

### Phase 0: Foundation (current state)
- [x] raw_dirent.cr (LibC.opendir/readdir with d_type)
- [x] DirEntry, Config, SortMode, sentinel errors
- [x] Sequential walker
- [x] Basic test suite (~80% fastwalk parity)

### Phase 1: Parallel Worker Pool
- [ ] Implement worker pool with channels (workc/enqueuec/resc)
- [ ] Buffered channel sizing
- [ ] Outstanding-work tracking + shutdown protocol
- [ ] `Walk` entry point dispatches to parallel or sequential
- [ ] Port remaining fastwalk tests
- [ ] Benchmarks vs sequential

### Phase 2: Ignore System — Core Types
- [ ] `Match(T)` enum (None/Ignore/Whitelist) with `or`/`invert`/`is_*`
- [ ] `Glob` struct with gitignore semantics parsing
- [ ] `Gitignore` matcher (single directory's ignore rules)
- [ ] `GitignoreBuilder` (parse .gitignore files)
- [ ] Port ripgrep `gitignore.rs` tests

### Phase 3: Ignore System — Hierarchy
- [ ] `Ignore::Matcher` persistent data structure
- [ ] `add_child` — build child matcher (share parent's compiled state)
- [ ] `add_parents` — walk ancestors to find ignore rules
- [ ] Ignore-file probing during readdir (no extra stat)
- [ ] `matched(path, is_dir)` with precedence: override > custom > .ignore > .gitignore > exclude > global > file types > hidden
- [ ] Port ripgrep `dir.rs` tests
- [ ] Port ripgrep integration tests

### Phase 4: Override & File Type Matching
- [ ] `Overrides` matcher (build from glob strings)
- [ ] `Types`/`TypesBuilder` (file type by extension glob)
- [ ] Port ripgrep `overrides.rs` tests
- [ ] Port ripgrep `types.rs` tests

### Phase 5: Integration — Walker + Ignore
- [ ] Walk with ignore filtering (on_dir_ent calls matcher)
- [ ] Option to configure ignore behavior on `Config`
- [ ] Integration tests: walk with .gitignore, .ignore, overrides, file types
- [ ] Verify symlink + ignore interaction

### Phase 6: Optimization
- [ ] GlobSet: compile globs to regex set for fast multi-match
- [ ] Darwin getdirentries64 specialization
- [ ] Dirent slice pool (reuse arrays for sorting)
- [ ] Minimize string allocations in hot path (name bytes, path joining)
- [ ] Profile-driven tuning (allocations, syscalls, GC pressure)

---

## 6. Benchmark Harness Design

```crystal
require "benchmark"

# Generation helpers
def create_tree(root, depth, width, files_per_dir)
  # Create a directory tree for benchmarking
end

def create_ignore_files(root, patterns)
  # Write .gitignore/.ignore files
end

# Benchmark each traversal method
Benchmark.ips do |x|
  x.report("dir-walk (no ignore)") { ... }
  x.report("dir-walk (with ignore)") { ... }
  x.report("Dir.glob") { Dir.glob("#{tree}/**/*") }
end
```

Benchmarks live in `bench/` directory and are runnable via `crystal run bench/`.

---

## 7. Open Questions & Risks

| Question | Status |
|----------|--------|
| How to handle Crystal's lack of `preview_mt` by default? | Use single-fiber sequential walk when `!flag?(:preview_mt)`; parallel when available. Same as current design. |
| Crystal `Regex` performance with alternation for glob set? | Measure. May need to port a dedicated glob matcher. |
| How to implement `GlobSet` with literal_separator semantics? | Crystal's `File.match?` may not support `**` correctly across dir boundaries. Need custom implementation. |
| Signal safety of LibC.readdir vs getdents? | LibC.readdir is not signal-safe. getdents64 is. Low priority for correctness. |
| macOS APFS performance with many fibers? | Already handled by Darwin-specific `default_num_workers`. |
| Are there Crystal shard dependencies we can leverage? | Use `wait_group` shard (already in fast_find.cr). Consider `regex` for glob compilation. |

---

## 8. Reference Files

- **Walker upstream**: `vendor/fastwalk/fastwalk.go`, `vendor/fastwalk/fastwalk_unix.go`, `vendor/fastwalk/fastwalk_darwin.go`
- **Ignore upstream**: `vendor/ripgrep/crates/ignore/src/{gitignore,dir,walk,overrides,types,lib}.rs`
- **Current port**: `src/dir-walk/walker.cr`, `src/dir-walk/dirent.cr`, `src/dir-walk/raw_dirent.cr`
- **Reference impl**: `fast_find.cr` — Crystal patterns for concurrent traversal
- **Parity tracking**: `plans/inventory/fastwalk-parity.md`
