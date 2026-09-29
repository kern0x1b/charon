# The Security host cases: how they are built, and the trap that made one measure the host

These are **not** builds. A case is a `clang` compile and a run on this Mac, so the machine's load does
not apply to them and there is no heavy job: the only heavy things are a `heavy.sh` build and the gates.

`run-cases.sh` is the one command that runs everything here. It builds each case **with the port sources
it calls**, feeds the output to that case's comparator, runs the mutations, and ends with
`N cases, M mutants, M noticed`. It exits non-zero on any failure, on a mutation that goes unnoticed, and
on a case whose expected symbols are missing from its own binary.

## The trap: a case that links too little measures the HOST, silently

A case compiled without one of the port sources it needs does not fail to build. The names it calls
resolve to the **host framework**, which has the same API, the case runs, prints plausible numbers, and
the comparator reports a difference that looks like a port bug. It is not one: the port code was never
in the process.

This happened for real. `protocol-metadata-accessors` was linked without
`SecProtocolMetadataAccessors13_0.m`, so three of its calls answered from the host — the port's binary
defines only **3 of the 17** port accessors, and `ciphersuite` came back `65535`, a value the port cannot
return at all.

**`nm -m` does not catch this.** It prints an address for a symbol the binary does not define, and the
address reads like a definition:

```
nm -m case | grep ciphersuite
  0000000100001254 (__TEXT,__text) external _sec_protocol_metadata_get_negotiated_ciphersuite
```

which looks defined. `nm -u` and the plain symbol table tell the truth:

```
nm -m case | grep ciphersuite
  (undefined) external _sec_protocol_metadata_get_negotiated_ciphersuite (from Security)
nm case | grep ' T _sec_protocol'
  _sec_protocol_metadata_get_negotiated_tls_ciphersuite     <- the TLS one, and only the TLS ones
```

`run-cases.sh` now checks, after every build, that every function each source defines is **defined** in
the binary, and fails with `MISSING <case> _<sym> ... it resolved to a dylib` when one did not. The
lesson generalises: **a case proves the port only if you check the port is in the process.**

## Two more things that look like findings and are not

- A warning in a case's log is not necessarily a defect. The metadata-accessors case emits
  `-Wdeprecated-declarations` for `sec_protocol_metadata_get_negotiated_protocol_version` and
  `kSSLProtocolUnknown`, which the SDK deprecates in favour of the `tls_` spellings. The case calls the
  non-`tls_` names on purpose: those are the functions the port implements.
- A `-Wnonnull` warning in a port source usually means the header's result annotation, and the library's
  flags are `-Wall` without `-Werror`, so it compiles. It is recorded, not silenced.

## Output is unbuffered

The cases that can be crashed by a mutation call `setvbuf(stdout, NULL, _IONBF, 0)` at the top, so a
segfault cannot lose the rows printed before it. Without that, a crash makes the comparator say a row
"did not measure", which names a truncated buffer rather than the crash.

## Why the four red metadata-accessor rows were NOT a defect in the port or the case

They were red, and the worry was the right one: those accessors were merged on the reviewer's approval
**with no case running them**, so a red four rows could have meant the merged code was wrong. These are
the two explanations that were **ruled out, with the evidence**, so that the answer is on disk rather
than in a commit subject and a deleted file.

**1. It was not the host answering.** `nm -m` on the case binary the driver built:

```
0000000100001254 (__TEXT,__text) external _sec_protocol_metadata_get_negotiated_ciphersuite
0000000100001284 (__TEXT,__text) external _sec_protocol_metadata_peers_are_equal
0000000100001318 (__TEXT,__text) external _sec_protocol_metadata_challenge_parameters_are_equal
```

`(__TEXT,__text)` with an address **looks** like a definition, and that is the trap: `nm -m` prints an
address for a symbol the binary does not define. The truth is in the plain table and in `nm -u`, and it
is also visible as a count:

```
the driver's binary defined        3 port accessors
the same sources built by hand    17
nm -m case | grep ciphersuite  ->  (undefined) external _…_ciphersuite (from Security)
```

The host *could* have answered — `otool -L` shows `Security.framework` linked — and did.

**2. It was not a disagreement between the port and the case.** Built by hand from the same three sources
(`SecProtocolMetadata13_0.m`, `SecProtocolMetadataAccessors13_0.m`, `SecProtocolMetadataAccessors16_0.m`),
every row matched:

```
ciphersuite 0 0   peers-same-object 1 1   peers-two-objects 1 1   peers-one-null 0 0
peers-both-null 1 1   challenge-same 1 1   challenge-one-null 0 0
```

and reading the bodies agrees: both comparators return `true` for the same object and for two objects and
`false` when exactly one is NULL, and `get_negotiated_ciphersuite` returns `SSL_NULL_WITH_NULL_NULL`.
**65535 is a value the port cannot return at all.**

**The cause was mine, in the driver.** `protocol_case()` read `sources=$2` and was called with two source
arguments, so `$PMA` was dropped on the floor and never reached the link. `protocol-options-blocks` and the
metadata case are wired through the same `protocol_case`, which is why they were affected too.

**How to check this class in a second**, since it is not obvious: do not grep the driver for a comparator's
name — the driver constructs it as `compare-$name.py`, so a literal grep for
`compare-protocol-options-blocks.py` returns **0 while the case runs and is green**. Grep for the
`protocol_case` line, or read the summary line, which names how many cases were driven.
