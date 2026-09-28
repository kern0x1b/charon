# selector-synthesize

A property with both an `@synthesize` binding and a hand-written accessor **in the same
`@implementation`** is two definitions of one method, and the compiler keeps one of them without saying
which. The cost is silent and total: the getter that survives can be the wrong one, and nothing in the
build, the link or the gate reports it.

A *category* redefining a selector the primary implementation synthesised is ordinary and is not this,
so `check.py` splits a file into `@implementation` blocks and counts a collision only inside one of
them. That scoping is the whole check; without it the same query over the package reports 52 files
instead of the ones below.

## Running it

```
./run.sh                    the whole package
./run.sh path/to/a.m        one file
./run.sh path/to/a/dir      every .m under one directory
```

It **proves itself first**, against the two files in `proofs/`:

- `trapped-PHASEEngine.m` — `PHASEEngine` with `@synthesize rootObject` and a `-rootObject` getter
  in the same implementation. Found.
- `clean-PHASEEngine.m` — the same class after the fix. Not found.

If either does not hold, the check says so and exits non-zero, because then its output is not evidence.

## What it does not do

It does not fail the tree and it does not fix anything. A collision is a question for the band that
owns the file: sometimes the hand-written accessor is deliberate — `SCNPhysicsWorld`'s
`contactDelegate` getter is written out for an atomic weak read, and reads the very ivar the
`@synthesize` binds — and the only way to tell that from the bug is to read the file.
