# Changelog

## [0.3.0] — 2025-07-28

### Added
- `Config#overrides` property: wire `Override` glob patterns directly into walk
- `examples/fdlike.cr`: CLI tool with `--md5` flag (path:hash output)
- README examples: glob includes, MD5 hashing, parallelism docs
- `CLAUDE.md`, `CHANGELOG.md`, `docs/` (architecture, development, testing)

### Changed
- AGENTS.md is now a symlink to CLAUDE.md
- README rewritten for users (porting notes moved to docs/development.md)
- Makefile: removed deprecated `-Dpreview_mt`, clean removes `temp/`
- .gitignore: added `temp/`, `.crystal-cache/`, `*.tmp`

## [0.2.0] — 2025-07-28

### Added
- Parallel walker: channel-based worker pool (workc/enqueuec/resc/donec)
- Ignore system: .gitignore, .ignore matching (ported from ripgrep)
- Override matcher: include/exclude glob patterns
- Ignore::Matcher hierarchy: persistent, fiber-safe ignore rules
- Integration: walk + ignore filtering
- 35 new specs (ignore, overrides, matcher, integration)

### Changed
- `num_workers > 1` now activates parallel dispatch
- Ignore matcher passed through call chain, not stored on shared Walker
- Removed deprecated `-Dpreview_mt` dependency for parallel path

## [0.1.0] — 2025-06-15

### Added
- Sequential walker with raw readdir syscalls
- DirEntry, Config, SortMode, sentinel errors
- Adapters: ignore permission errors, duplicate files/dirs
- Darwin zero-inode skip, "."/".." skip without allocation
- 32 specs covering basic walk, symlinks, skip, sorting, depth
