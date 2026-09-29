# The Security host cases: how they are built, and the trap that made one measure the host

These are **not** builds. A case is a `clang` compile and a run on this Mac, so the machine's load does
not apply to them and there is no heavy job: the only heavy things are a `heavy.sh` build and the gates.

`run-cases.sh` is the one command that runs the cases here, `check-digests.py` included — the digests were the
one thing here that nothing ran, which is the defect this directory is about, so the driver runs it
first and counts its exit. Two scripts in this directory are still run by something else and not by the
driver, and this says so rather than leaving "everything" to mean them: `gen-security-cases.py` GENERATES
the case file and `run.sh` runs it, and `check-registered.py` is invoked by nothing in this tree at all —
it passes (18 in the list, 18 defined, 125 rows of kind constant, exit 0) and it has a `--control` of its own, so whether it belongs
in the driver's exit path is a decision about coverage and not a wording fix. The driver builds each case **with the port sources
it is given**, feeds the output to that case's comparator, runs the mutations, and ends with
`N cases, M mutants, M noticed`. Every case prints exactly one verdict line — `GREEN`, `RED`, `CRASH`,
`BUILD`, `MISSING` or `NOTRUN` — and the tail fails if the number of `GREEN` lines is not the number of
cases, so a run cannot report coverage its own output does not show. It exits non-zero on any failure, on a mutation that goes unnoticed, and
on a case whose expected symbols are missing from its own binary, and on a digest below that no longer
matches the file it is pinned to. The digest line is a check, not a case: it is deliberately not in the
case or `GREEN` counts, so `N cases` still means the cases and nothing else.

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

## The guard, and its measured limits

**The guard covers a case that reaches the port through a `sec_*` name, when the source defining that
name is linked.** It matches `sec_*` in the case and in the port sources and requires `_name` in the
case's own binary.

**It does NOT cover five cases**, and the list is what the code enforces, not what would be nice:

| case | why it is outside the guard | proven by |
| --- | --- | --- |
| `network-fetch` | the port's functions are named as the HEADER names them (`SecTrustSetNetworkFetchAllowed`, …), and the guard matches only `sec_*` | dropping `$N` leaves the case **GREEN, exit 0**, with `nm -u` showing those symbols undefined — the host answered |
| `supported`, `attributes`, `certificate-name` | they reach the port through `Charon*` helpers, which the guard does not match | same shape as `network-fetch` |
| `trust-result` | it resolves the port by `dlsym(RTLD_DEFAULT, …)`, so there is no link-time reference to find at all | reading the case: the name is a **string** |

**A source dropped from the link line CAN hide**, and `network-fetch` is the proof rather than my
assertion: the symbols resolve to the host's framework, the case compares numbers the host produced, and
it passes. What the guard does catch is a dropped source **whose functions the case reaches through a
`sec_*` name** — dropping `$PD`, `$PMA` or the 16.0 accessor source does fire `MISSING`.

The general fix is to stop matching a prefix and extract the port's definitions **by position** — the
last identifier before the `(` of a definition line — and then intersect that with every identifier the
case calls. I attempted the prefix route twice and it does not reach these names, so it is not claimed.

**`nm`'s own status is now captured where `set -e` cannot intercept it.** The earlier form
(`nm … > file` then `nmstatus=$?` on the next line) never reached the assignment: the script ended on the
failing command, so the branch was unreachable and an `nm` failure killed the run silently. A stub `nm`
that exits 1 now produces 19 `BUILD … nm -gU on the linked binary exited 1` lines, 0 cases counted, and
a non-zero exit, where the real run is unchanged at 19/14/13.

Still owed, none of it done:

1. **A source dropped from the link line is caught, and this was checked rather than assumed**: dropping
   `$PD`, `$PMA` or the 16.0 accessor source leaves the case calling a `sec_*` name, that name is still in
   the reference set **because the case file is itself on the link line**, the symbol is absent from the
   binary, and the guard fires. What it does **not** do is notice a
   source that was never linked because **nobody called its function** — the case has to reach the port
   through a `sec_*` name for the guard to have anything to check.
2. **The stale-mutant sweep is not landed**: `make-mutants.py` runs after the early `mutate()` calls, so a
   sweep there deletes the mutants this run has just written and the suite goes red
   (3 failures, 19 cases, 14 mutants, 10 noticed). It has to run before `make-mutants` and before the
   first `mutate()`.
3. **The missing-mutant-file check is reverted as unproven**: `must_not_compile` is required to see a
   build FAIL, and a mutant file that is simply absent makes the compiler fail for the wrong reason. Its
   control removed a file `make-mutants.py` rewrites at the start of every run, so the control could not
   fail. Proving it needs a function-level test on a path that cannot exist.
4. **F2 — the guard builds its reference set from the case's own link line** and does not cover a case
   that resolves the port by `dlsym(RTLD_DEFAULT, …)`, so `trust-result` can still measure the host and
   pass.

## Digests of the evidence this directory cites

Recomputed with `shasum -a 256` AFTER the last content change, on this tree, and checked by
`check-digests.py` - which exits non-zero when this block is missing, when it covers fewer files
than the command below cites, when any digest does not match, or when a cited file cannot be read.
`run-cases.sh` runs it, so a pin that has gone stale ends the run non-zero; to run it by hand, run
`python3 check-digests.py` from this directory, which is the invocation its own docstring gives: the
script resolves the README and the files cited below from its own location and not from the working
directory, so the same run comes out the same from here, from the repository root or from anywhere else.

```
shasum -a 256 tests/backports/host/security/sec-object-wrappers.m \
         tests/backports/host/security/compare-sec-object-wrappers.py \
         packages/a/apple-backports/Security/SecObjectWrappers12_0.m
```

    0e134f43b64166c4e55a12f1f000cd36b1ad422922c937c49ee27487b11ad00c  tests/backports/host/security/sec-object-wrappers.m
    47e215633006060820d6a7e6ce53797bc371889b79f35d0e3d06e08bee6f7354  tests/backports/host/security/compare-sec-object-wrappers.py
    c4fb20d9e4423c9127cbfdea7531b8a981a4aae89347106b2aa870ea33dbfbc9  packages/a/apple-backports/Security/SecObjectWrappers12_0.m

