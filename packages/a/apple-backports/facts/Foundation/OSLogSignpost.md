# os_signpost, over this port's own os_log

`os_signpost` arrived in iOS 12 and it is a software subsystem, not hardware and not a service: an
application says "this interval began" and "it ended", with a name, and the system shows the
intervals in Instruments. The armv7 6.1.3 cache exports **none** of it — `_os_signpost_emit_with_name_impl`,
`os_signpost_enabled`, `os_signpost_id_generate`, `os_signpost_id_make_with_pointer` are all absent —
while this package has carried the log it sits on since 6.0 (`facts/Foundation/OSLog.md`,
`registry/Foundation/oslog.json`, `Foundation/OSLog9.m` and `OSLog10.m`).

## Four functions carry the family

Everything else in `signpost.h` is a macro over these four, so carrying them carries the whole family:
`os_signpost_interval_begin`, `os_signpost_interval_end`, `os_signpost_event_emit`,
`os_signpost_emit_with_type` and the `_os_signpost_emit_with_type` shape all end at
`_os_signpost_emit_with_name_impl`, and the two id sources and the enabled check stand beside it.

- **`os_signpost_enabled` answers true, and that is load-bearing.** The header's own macro is
  `if (os_signpost_enabled(_log_tmp)) { … } __extension__({})` — an answer of `false` compiles the whole
  emit away, so a family that answered false would record nothing and the metrics over it would be
  empty by construction. The port's log records what it is handed at fault and above and keeps every
  signpost interval, so a mark is always worth making.
- **The two id sources stay apart**, because the header says they must: a generated id carries the
  high bit, a pointer's does not, and `OS_SIGNPOST_ID_NULL` is never returned by a generate.
- **The emit records.** An interval begin remembers a monotonic reading under its id, an interval end
  takes the difference and keeps it with the name and the subsystem and category of the handle it was
  marked through, and an event is kept at zero length. That store is what MetricKit's signpost metrics
  are read out of (`facts/MetricKit/MetricKit.md`), so a mark an application makes is measurable
  afterwards — which is the difference between carrying the family and stubbing it.

## How another of this package's libraries reaches the store

Not by a link. Measured on a built `libFoundationBackports.dylib`: it exports **six** `os_log*`
symbols and **zero** `charon_`-prefixed C symbols and zero `Charon*` classes, and the registry lists
**no** name beginning with `charon` — a library of this package exports only the names the registry
lists, and the registry lists only names an SDK header declares. So there is no name of ours that
another of our libraries can link, in either direction, and a first attempt at two C functions across
the boundary failed at link with exactly that:

```
Undefined symbols for architecture armv7:
  "_charon_signpost_intervals", referenced from: _CharonSignpostMetrics in MXMetricManager.o
```

MetricKit therefore looks the store up by its own name with `NSClassFromString` and messages it,
once, behind a `respondsToSelector:`. That is the port's own idiom for a class in another image —
`NSClassFromString` in `AVFoundation/AVCaptureDevice+Authorization.m`,
`CoreSpotlight/CSSearchableIndex.m` and `CallKit/CharonCallAudio.m` — and it costs one string lookup
per process.

## The snapshot pointer

MetricKit's private header (`MXSignpost_Private.h`, whose own comment says the header must be public
to let clients compile properly) appends a public `signpost:metrics` field to every signpost it emits
and passes `_MXSignpostMetricsSnapshot()` as that field's one argument. So the pointer is not an
address and nothing: it is the snapshot the metrics came from, carried on the mark itself. The port's
emit path records that pointer on the interval it takes, so the signpost the application marked and the
snapshot the metrics are read from are the same fact.

## Not measured against a host

The host's macOS has its own `os_signpost`, and a differential is worth writing — printing the host's
`os_signpost_id_generate()` twice to show the ids differ and never come back NULL, a
`os_signpost_id_make_with_pointer` round trip, and the description of a handle made with
`os_log_create("com.apple.metrickit.log", "test")` against the port's — but it is not written, and the
delivery says so. What *is* measured is the release side: that the four symbols are absent from the
6.1.3 cache, which is why they are here at all.
