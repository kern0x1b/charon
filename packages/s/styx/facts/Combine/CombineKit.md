# The layer of our own, and what was measured

`packages/s/styx/files/CombineKit` closes the measured gap between the module
`charon@styx` builds and the Combine Apple's SDK 26.2 declares. It is compiled into the
same module, so it sees the fork's internal helpers, and no vendored file is edited.

## The measurements, and how they were taken

**The gap, before.** `swift-api-digester -dump-sdk` was run on Apple's 26.2
`Combine.swiftinterface` and on the armv7 module, and the two dumps were compared by
declared name:

```
apple declarations: 1035   ours: 1099
in both:    806
in apple, not ours: 229
in ours, not apple: 293
```

Row coverage was then measured with the corpus's own tool: `swiftinterface-surface.py`
reads Apple's declarations from its `.swiftinterface`, and reads ours from the
`.swiftinterface` the toolchain synthesises out of the built `.swiftmodule`, so both sides
are spelled the way the corpus spells them.

```
corpus rows for Combine: 1224
covered by the built module: 946        # as it stood
```

**After the layer**, the same two measurements:

```
corpus rows for Combine: 1224
covered by the built module: 1131
not covered: 93
  class         10 /    10
  constant       9 /     9
  enum           7 /     7
  method       561 /   636
  property     256 /   265
  protocol      13 /    13
  struct       100 /   102
  typealias    175 /   182
```

```
apple declarations: 1035   ours: 1235
in both:    963
in apple, not ours: 72
in ours, not apple: 272
```

## The 93 rows that are not covered, each with the reason

**73 rows — `Optional.Publisher.*` and `Result.Publisher.*` members.** The module
declares Apple's names: `Optional.Publisher`, `Optional.publisher`, `Result.Publisher` and
`Result.publisher` are all there, with every operator on them, and a client that writes
`someOptional.publisher.map { }` compiles against the module (the armv7 probe does exactly
that and it runs). What differs is where the members are *printed*: the fork nests the
type under an intermediate `OCombine` namespace (`Optional.OCombine.Publisher`) and
`Optional.Publisher` is a typealias for it, which upstream added for
[SR-11183](https://bugs.swift.org/browse/SR-11183) — the ambiguity when a client has both
OpenCombine and Combine imported. A module named `Combine` cannot be that pair, so the
namespace is dead weight here, but removing it means editing the fork's own files, which
this layer does not do. The printed path is the divergence; the API a caller writes is
Apple's.

**9 rows — witnesses the compiler derives.** `CombineIdentifier.==(a:b:)` and
`hash(into:)`, `Subscribers.Demand.==(a:b:)`, `hash(into:)`, `hashValue`,
`Subscribers.Completion.==(a:b:)`, `hash(into:)`, `hashValue` and `AnyCancellable.hashValue`.
Each of these types declares `Equatable` or `Hashable`, so every one of them answers
`==` and hashes; Apple's framework interface prints the operators under their public names
because Apple writes them out, and the interface synthesised out of a module built for a
target prints the derived ones under the compiler's own name (`__derived_struct_equals`,
`__derived_struct_hash`). The `PrefetchStrategy` operator *was* written out, because that
one the compiler derives for an enum and the fork's file could be left alone; the others
are witnesses the compiler owns, and re-declaring them from another file is an
`invalid redeclaration`.

**3 rows — `Record.encode(to:)`, `Record.init(from:)`, and
`ImmediateScheduler.SchedulerTimeType.Stride.init(from:)` / `encode(to:)`.** `Record` and
`Stride` are already `Codable`; the fork declares the conformance in its own file and the
compiler synthesises the two methods, so the same printed-name difference applies. Writing
them from this layer is a redeclaration.

**3 rows — `Record.Recording.output`, `Record.Recording.completion`,
`Subscribers.Assign.object`.** The fork declares them `public private(set) var`; Apple
declares `public var … { get }`. A client sees the same access (a public getter, no public
setter); only the printed form differs, and changing it means editing the fork's files.

**1 row — `Published.wrappedValue`.** Marked `@available(*, unavailable, message:
"@Published is only available on properties of classes")` in Apple's interface too, with
the same reason. A `@Published` property is read and written through the enclosing-instance
subscript the wrapper declares, which the corpus lists separately and the module carries.

**4 rows — the `__AsyncSequence_Failure` and `__AsyncIteratorProtocol_Failure`
typealiases.** These are the names the compiler synthesises for an `AsyncSequence` and
`AsyncIteratorProtocol` conformance, and it prints them in a framework's interface but not
in the interface synthesised out of a module built for a target. The conformances are
there: `AsyncPublisher`, `AsyncPublisher.Iterator`, `AsyncThrowingPublisher` and their
`AsyncIterator`s all conform, and the corpus's own rows for them are covered.

## The host differential

`tests/swift/combine/differential` in this branch's `.agent-work` — the same
`Harness.swift`, `Table.swift` and `main.swift` compiled twice, once against the host's own
`Combine` and once against the module this port builds for the host, and the two runs
compared line for line. 40 cases over the four groups the work is grouped by: the merge and
combineLatest families, `collect(byTime:)`, the schedulers (with a scheduler whose time the
test drives, so the time-based operators are the same on both sides), demand and
backpressure, and cancellation.

```
cases: cases 40
DIFFERENTIAL: 8 differing lines
```

Every differing line is in the new merge operator, in two shapes:

1. **`merge/two/holds-until-demanded` and `merge/many/sequence`** — the last upstream's
   value, and the stream's own `finished`, are missing where the host has them. A
   publisher that sends at subscription time (`Just` does) is the only one that reaches
   this: the host delivers every value and the finish, the module delivers all but the
   last of each. This is a defect, not a divergence to copy: it is recorded here as open.
2. **`merge/demand/limited`** — with a downstream that asked for one value, the host leaves
   each upstream having been asked for `.max(1)` and the module leaves each having been
   asked for `.max(2)`, because the module asks each upstream for one more once a value has
   been delivered. The values delivered are the same; the shape of the demand is not.

Two things the differential found and that were fixed here rather than copied: a
`Publishers.Drop`, `Publishers.CollectByCount`, `Publishers.Retry` and
`Publishers.Output` that compared only their upstream, where the host compares the count,
the count, the retries and the range as well; and a merged publisher that delivered
`.finished` downstream as soon as any upstream finished, because its completion branch
accepted only one of the three states the publisher is in. Both were found by the table and
both are now measured equal.

The host copy of the module is called `CombineKit`, and the staged sources have the module's
own `Combine.` prefix rewritten to that name. The reason is the host, not the module: on
macOS the SDK's own Foundation imports Apple's Combine, and a module called `Combine` links
Apple's Combine beside it through the autolink its interface carries, and the two sets of
classes then collide — the run refuses to start if `otool` finds Apple's Combine in the
binary, and that refusal is a check the suite has already made once. The Foundation-
integrated part of the module (`NotificationCenter.Publisher`, `Timer.publish`, the run loop
and operation queue schedulers, KVO) is therefore measured on the device instead, because
the host copy cannot carry it.

## The armv7 probe

`.agent-work/runs/combine/port` is a port that writes `import Combine` and calls the layer's
surface: the merge family, the combineLatest family, `collect(byTime:)` and
`collect(_:options:)`, the equality and hashing, `Publishers.MapError`'s labelled
initializer, and the `Optional` and `Result` publishers under Apple's own names. It is
built for `armv7-apple-ios6.1.3` with the addon toolchain, and the driver's own check of it:

```
imports: every non-weak import of the armv7 slices of 20 binaries resolves against 158520 exports; 81 weak imports it does not export, each named in a warning above
[100%]: build ok
build/iphoneos/armv7/release/combinekit: Mach-O executable arm_v7
```

It runs on the emulated iPhone 4S at 6.1.3 (`xmake emulate -s 120 run /usr/libexec/combinekit`).
The last run reported 36 checks held and 8 that did not: five are the open merge defect above
seen from the device, two are `collect(byTime:)` and `collect(_:options:)` not sending what
they collected, and one is a fault in the probe itself (the merge case expects one value
where the module correctly sends two). Each is a line the next round starts from.

## What the equality operators compare, and where the host is the oracle

The rule is Apple's own declarations, and the host is what settled each question. Apple's
interface constrains `Publishers.Collect.==` by the upstream alone, which reads as "the
upstream is all that is compared" — and the host disagreed for `Drop`, `CollectByCount`,
`Retry` and `Output`, where two publishers that differ only in their count, retries or range
are *not* equal. Those four compare every stored property here. Where Apple's declaration
constrains another property as well — `ReplaceEmpty`'s and `ReplaceError`'s output,
`DropUntilOutput`'s other, `Concatenate`'s both — this follows the declaration.
`Publishers.Output.range` is a `CountableRange<Int>`, compared by its two bounds rather
than by a conformance, so that no new one is needed.
