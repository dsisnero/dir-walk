# dir-walk

High-performance parallel directory traversal for Crystal, combining the walker
from `charlievieth/fastwalk` with the ignore/glob rules from `BurntSushi/ripgrep`.

## Quickstart

```bash
shards install          # Install dependencies (ameba)
crystal spec            # Run tests
crystal tool format --check src spec  # Format check
./bin/ameba src spec    # Lint
```

## Principles

1. Upstream behavior is the source of truth. Port behavior first, then express
   it with Crystal idioms only where semantics stay unchanged.
2. Upstream tests are normative — port them first.
3. Preserve parameter order, edge cases, and invalid-input behavior.
4. Use `Bytes` for binary semantics instead of `String`.
5. Use small red-green cycles per feature.

## Source of Truth

- **Walker**: https://github.com/charlievieth/fastwalk — pinned v1.0.14 at `vendor/fastwalk`
- **Ignore/Glob**: https://github.com/BurntSushi/ripgrep — `vendor/ripgrep/crates/ignore`
- **Reference**: `fast_find.cr` for Crystal patterns and ideas

Ask questions via DeepWiki: `deepwiki_ask_question repoName: charlievieth/fastwalk ...`
or `deepwiki_ask_question repoName: BurntSushi/ripgrep ...`

## Project Structure

```
src/dir-walk.cr           -- Entry point
src/dir-walk/
  dirent.cr               -- DirEntry, Config, SortMode, sentinel errors
  walker.cr               -- Walk entry point, sequential/parallel dispatch
  raw_dirent.cr           -- LibC.opendir/readdir/closedir with d_type
  adapters.cr             -- Walk function adapters (ignore_*, stat helpers)
  ignore/                 -- Ignore/glob matching (ripgrep port)
spec/                     -- Crystal specs
fast_find.cr              -- Reference implementation
vendor/fastwalk/          -- Upstream Go source (submodule)
vendor/ripgrep/           -- Upstream Rust source (submodule)
plans/                    -- Design docs and parity tracking
```

## Quality Gates

```bash
crystal tool format --check src spec    # Format
./bin/ameba src spec                    # Lint
crystal spec                            # Tests
```

Parallelism is opt-in — resize the default execution context at startup:
`Fiber::ExecutionContext.default.resize(System.cpu_count)`
