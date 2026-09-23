---
name: corpus-regen
description: Regenerate the backports registry export and the corpus demand data after a push to charon main — export-registry.lua, regen.sh, and certifying any list of "missing" APIs through tools/verify.py. Use after every merge to main, when the demand ranking looks stale, or before handing anyone a list of APIs to implement.
---

# Registry export and corpus regeneration

Tools: `tools/corpus/` in this repository (`$HOME/Git/projects/ios/coordination/corpus-tools` is a
symlink to the shared checkout's copy). Data: `$HOME/Git/projects/ios/coordination/corpus/`
(`CHARON_CORPUS_ROOT` overrides the parent directory). Background and every generated file:
`tools/corpus/README.md`.

## 1. Registry export — after every push to main

From a checkout at the pushed commit:

```
sha=$(git rev-parse --short HEAD)
mkdir -p /private/tmp/charon-registry-export
xmake l tools/corpus/export-registry.lua "$PWD/packages/a/apple-backports" /private/tmp/charon-registry-export/carried-registry.tsv
wc -l /private/tmp/charon-registry-export/carried-registry.tsv
cp /private/tmp/charon-registry-export/carried-registry.tsv $HOME/Git/projects/ios/coordination/corpus/carried-registry-$sha.tsv
```

- The first argument is the **package root** `packages/a/apple-backports` (the script globs
  `<root>/registry/*.json`), not the checkout root the README names. A wrong root writes a
  header-only file without an error: compare the row count with the previous
  `carried-registry-*.tsv`.
- Every corpus tool reads the export at `/private/tmp/charon-registry-export/carried-registry.tsv`
  (`CHARON_REGISTRY_TSV` overrides). The system temp path is wiped: the durable copy is the one
  in `coordination/corpus/`.
- An export older than the last registry commit on `origin/main` makes every ranking stale:
  `git log -1 --format=%cd origin/main -- packages/a/apple-backports/registry` vs the file's mtime.

## 2. Regenerate the ranking

After a canon build (workspace skill `canon-install`), refresh what the 6.1.3 band exports;
`gen-report.py` reads it for `LAUNCH-BLOCK` and stops without it:

```
nm -gUj <canon-run>/build/stage/usr/lib/charon/org.charon.apple-backports/bands/6.1.3/*.dylib | grep -v ':$' | sort -u > $HOME/Git/projects/ios/coordination/corpus/built-exports-6.1.3.txt
```

```
PYTHONHASHSEED=0 $HOME/Git/projects/ios/coordination/corpus-tools/regen.sh <sha>
```

Order inside (do not reorder by hand): save `crash-demand-top.tsv` as `-prev`, `crash-demand.py`,
`hint-track.py <label>`, copy the export to `registry-last.tsv`, `observed.py`.

- Check the numbers, not the exit code: a tool pointed at a missing input writes a plausible,
  smaller or empty table. Compare row counts with the previous run.
- `PYTHONHASHSEED=0` makes tie order reproducible for a byte diff.
- `observed.py` still reads device logs from a deleted `emulator-lab/` path: its
  `observed-device.tsv` is empty for that reason, not because nothing was observed.

## 3. Certify before handing out

A list of "missing" APIs is not evidence. Every list goes through `tools/verify.py` (its
`check(name, rows)`: `rows` of `(api, kind, extra)`), which checks both the registry export and
the source tree, and prints how many rows are real. It reads `CHARON_REGISTRY_TSV` and
`CHARON_TREE_DIR` (default: this checkout's `packages/a/apple-backports`).

- "Not found" is reliable; "found" must be read: a declaration, a synthesized property and
  `@dynamic` all look like an implementation. `@dynamic` is evidence of absence.
- An explicit registry decision (`absent`/`ignored` with facts) outranks a find in the tree.
- Proving absence needs a control: show the probe finds something known to be there.
- `tools/verify.py` and `tools/corpus/verify.py` are separate copies; do not link one to the other.
