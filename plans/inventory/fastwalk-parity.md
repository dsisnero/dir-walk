# Fastwalk v1.0.14 Parity Inventory

Upstream: https://github.com/charlievieth/fastwalk
Pinned:   v1.0.14 (d0efdb6)
Language: Go -> Crystal

## Status Legend

- [x] Complete
- [~] Partial / alternate implementation
- [-] Not applicable (platform, internal)
- [ ] Not started

## Core API

| # | Item | Upstream | Crystal | Status |
|---|------|----------|---------|--------|
| 1 | SortMode enum | fastwalk.go:181-240 | src/dir-walk/dirent.cr | [x] |
| 2 | Config struct + Copy | fastwalk.go:265-322 | src/dir-walk/dirent.cr | [x] |
| 3 | DefaultConfig | fastwalk.go:257-263 | Config defaults | [~] |
| 4 | DirEntry struct | fastwalk.go:330-343 | src/dir-walk/dirent.cr | [x] |
| 5 | Walk function | fastwalk.go:411-507 | src/dir-walk/walker.cr | [~] |
| 6 | walker + readDir + walk | fastwalk.go:527-661 | src/dir-walk/walker.cr | [x] |
| 7 | Sentinels: ErrTraverseLink, ErrSkipFiles | fastwalk.go:49-56 | src/dir-walk/dirent.cr | [x] |
| 8 | SkipDir sentinel | fastwalk.go:61 | src/dir-walk/dirent.cr | [x] |
| 9 | DefaultNumWorkers | fastwalk.go:75-105 | src/dir-walk/dirent.cr | [x] |
|10 | DefaultToSlash | fastwalk.go:132-161 | src/dir-walk/dirent.cr | [x] |
|11 | SortMode.String() | fastwalk.go:249-254 | src/dir-walk/dirent.cr | [x] |
|12 | cleanRootPath | fastwalk.go:665-683 | src/dir-walk/walker.cr | [x] |
|13 | joinPaths | fastwalk.go:591-607 | src/dir-walk/walker.cr | [x] |

## DirEntry + Helpers

| # | Item | Upstream | Crystal | Status |
|---|------|----------|---------|--------|
|14 | DirEntry struct with Info/Stat caching | dirent_unix.go:14-46 | src/dir-walk/dirent.cr | [x] |
|15 | fileInfo / loadFileInfo (atomic lazy init) | dirent.go:12-32 | src/dir-walk/dirent.cr | [~] |
|16 | StatDirEntry helper | dirent.go:44-56 | src/dir-walk/adapters.cr | [x] |
|17 | DirEntryDepth helper | dirent.go:68-73 | src/dir-walk/adapters.cr | [x] |
|18 | fileInfoToDirEntry | dirent_unix.go:57-68 | Walker#make_root_entry | [x] |
|19 | direntSlicePool + sortDirents | dirent_unix.go:70-146 | Walker#sort_entries | [~] |

## Platform readDir

| # | Item | Upstream | Crystal | Status |
|---|------|----------|---------|--------|
|20 | readDir Unix (getdents via ReadDirent) | fastwalk_unix.go | raw_read_dir (LibC.readdir + d_type) | [x] |
|21 | readDir Portable | fastwalk_portable.go | same code path | [x] |
|22 | open/readDirent EINTR retry | fastwalk_unix.go:115-131 | LibC handles internally | [-] |
|23 | d_type to File::Type conversion | dirent_linux.go:27-49 | dt_to_type in raw_dirent.cr | [x] |
|24 | Zero-inode skip (deleted files) | fastwalk_darwin.go:52-54 | raw_dirent.cr | [x] |
|25 | "."/".." skip without allocation | fastwalk_darwin.go:67-69 | raw_dirent.cr | [x] |

## Adapters

| # | Item | Upstream | Crystal | Status |
|---|------|----------|---------|--------|
|23 | IgnorePermissionErrors | adapters.go:95-102 | src/dir-walk/adapters.cr | [x] |
|24 | IgnoreDuplicateDirs | adapters.go:42-64 | src/dir-walk/adapters.cr | [x] |
|25 | IgnoreDuplicateFiles | adapters.go:75-91 | src/dir-walk/adapters.cr | [x] |
|26 | EntryFilter | entry_filter_*.go | src/dir-walk/adapters.cr | [x] |

## Parallel walk (Go: goroutines, Crystal: fibers)

| # | Item | Upstream | Crystal | Status |
|---|------|----------|---------|--------|
|27 | Worker pool with channels | fastwalk.go:411-507 | src/dir-walk/walker.cr | [x] |
|28 | Main dispatch loop | fastwalk.go:468-506 | src/dir-walk/walker.cr | [x] |

## Ignore/Glob System (Rust: BurntSushi/ripgrep crates/ignore)

| # | Item | Upstream | Crystal | Status |
|---|------|----------|---------|--------|
|29 | Match enum | lib.rs:416-487 | src/dir-walk/ignore/match.cr | [x] |
|30 | Glob struct | gitignore.rs:32-76 | src/dir-walk/ignore/gitignore.cr | [x] |
|31 | Gitignore matcher | gitignore.rs:80-316 | src/dir-walk/ignore/gitignore.cr | [x] |
|32 | GitignoreBuilder | gitignore.rs:320-576 | src/dir-walk/ignore/gitignore.cr | [x] |
|33 | Ignore (Matcher) hierarchy | dir.rs:1-750 | src/dir-walk/ignore/matcher.cr | [x] |
|34 | IgnoreBuilder | dir.rs:752-1006 | src/dir-walk/ignore/matcher.cr | [~] |
|35 | Override + OverrideBuilder | overrides.rs:46-184 | src/dir-walk/ignore/overrides.cr | [x] |
|36 | Types + TypesBuilder | types.rs:163-493 | src/dir-walk/ignore/types.cr | [~] |
|37 | Walk + Ignore integration | walk.rs, dir.rs | src/dir-walk/walker.cr | [x] |
|38 | Gitignore spec tests | gitignore.rs:704-883 | spec/ignore/gitignore_spec.cr | [x] |
|39 | Override spec tests | overrides.rs:186-293 | spec/ignore/overrides_spec.cr | [x] |

## Darwin Specialization

| # | Item | Upstream | Crystal | Status |
|---|------|----------|---------|--------|
|40 | Darwin fastwalk | fastwalk_darwin.go | Not yet | [ ] |
|41 | Darwin getdirentries64 | zsyscall_darwin.go | Not yet | [ ] |

## Ported Tests

| # | Test | Upstream | Crystal | Status |
|---|------|----------|---------|--------|
|31 | TestFastWalk_Basic | fastwalk_test.go:176 | spec/dir-walk_spec.cr:30 | [x] |
|32 | TestFastWalk_Symlink | fastwalk_test.go:602 | spec/dir-walk_spec.cr:69 | [x] |
|33 | TestFastWalk_DirEntryType | fastwalk_test.go:627 | implicit in tests | [x] |
|34 | TestFastWalk_SkipDir | fastwalk_test.go:658 | spec/dir-walk_spec.cr:106 | [x] |
|35 | TestFastWalk_SkipFiles | fastwalk_test.go:699 | spec/dir-walk_spec.cr:295 | [x] |
|36 | TestFastWalk_TraverseSymlink | fastwalk_test.go:756 | spec/dir-walk_spec.cr:170 | [x] |
|37 | TestFastWalk_Follow | fastwalk_test.go:782 | Not yet | [ ] |
|38 | TestFastWalk_Follow_SkipDir | fastwalk_test.go:849 | Not yet | [ ] |
|39 | TestFastWalk_Follow_SymlinkLoop | fastwalk_test.go:888 | Not yet | [ ] |
|40 | TestFastWalk_Error | fastwalk_test.go:957 | spec/dir-walk_spec.cr:151 | [x] |
|41 | TestFastWalk_ErrNotExist | fastwalk_test.go:979 | spec/dir-walk_spec.cr:161 | [x] |
|42 | TestFastWalk_LongFileName | fastwalk_test.go:226 | Not yet | [ ] |
|43 | TestFastWalk_LongPath | fastwalk_test.go:339 | Not yet | [ ] |
|44 | TestFastWalk_SortMode | fastwalk_test.go:1100 | spec/dir-walk_spec.cr:328 | [x] |
|45 | TestSortModeString | fastwalk_test.go:1169 | spec/dir-walk_spec.cr:5 | [x] |
|46 | TestFastWalk_Depth | fastwalk_test.go:1189 | spec/dir-walk_spec.cr:209 | [x] |
|47 | TestFastWalk_DepthSymlink | fastwalk_test.go:1221 | Not yet | [ ] |
|48 | TestConfigCopy | fastwalk_test.go:1290 | spec/dir-walk_spec.cr:12 | [x] |
|49 | TestSkipAll | fastwalk_test.go:1337 | spec/dir-walk_spec.cr:142 | [x] |

## Notes

- Parallel worker pool implemented with Channel-based dispatch matching Go's
  workc/enqueuec/resc/donec pattern. Main loop multiplexes three channels.
- Sequential walk uses BFS deque (unchanged). Parallel activated when
  `num_workers > 1`.
- Ignore system implements ripgrep's gitignore/override/type matching with
  persistent (immutable) hierarchy for safe parallel traversal.
- `Ignore::Matcher#add_child` reads ignore files from readdir entry names to
  avoid extra stat calls.
- Glob matching uses Crystal's `File.match?` with gitignore semantics adapters.
  A dedicated GlobSet / regex-set optimization is left for future work.
- `read_dir` uses `LibC.readdir` with d_type (raw_dirent.cr). No Dir.each
  wrapper needed.
- `File::Info#same_file?` is used for symlink loop detection, matching Go's
  `os.SameFile`.
- Crystal `File::Type` enum maps to Go `os.FileMode` type bits.
