# Why `protocol-metadata-accessors` was red, and what it is NOT

Four rows were red in the driver: `ciphersuite` got 65535 where the case claims 0, and
`peers-two-objects`, `peers-both-null` and `challenge-same` got 0 where the case claims 1.

The concern this file answers is the right one: those accessors were merged in r8 on the reviewer's
approval **with no case running them**, so a red four rows could have meant the merged code was wrong. It
is not.

## 1. The port's own code answers, not the host

`nm -m` on the case binary the driver built:

```
0000000100001254 (__TEXT,__text) external _sec_protocol_metadata_get_negotiated_ciphersuite
0000000100001284 (__TEXT,__text) external _sec_protocol_metadata_peers_are_equal
0000000100001318 (__TEXT,__text) external _sec_protocol_metadata_challenge_parameters_are_equal
```

`(__TEXT,__text)` with an address is **defined in the binary**. An answer that came from a dylib would
appear as an undefined external next to the dylib's name. So the "case silently measures the host"
hypothesis — the class of mistake I made with the wiring — **does not apply to this case**.

`otool -L` shows Security.framework linked, so the host *could* have answered, and did not.

## 2. The port's code and the case agree: built by hand, every row is green

With the same three sources — `SecProtocolMetadata13_0.m`, `SecProtocolMetadataAccessors13_0.m`,
`SecProtocolMetadataAccessors16_0.m` — the case prints:

```
ciphersuite          0  0
peers-same-object    1  1
peers-two-objects    1  1
peers-one-null       0  0
peers-both-null      1  1
challenge-same       1  1
challenge-one-null   0  0
```

Every one matches its expectation. Reading the bodies confirms the port's answers are what the case
expects: `peers_are_equal` and `challenge_parameters_are_equal` return `true` for the same object and
for two objects, and `false` when exactly one is NULL — and `get_negotiated_ciphersuite` returns
`SSL_NULL_WITH_NULL_NULL`.

**So the merged r8 implementation is right, the case's expectations are right, and 65535 is a value the
port cannot return at all.**

## 3. The red is in the driver's build, and the difference is visible in its log

The driver's binary, built from the same three sources, prints `65535` and `0`. Its own build log is
not empty — it carries a clang diagnostic about the case that a hand build does not:

```
want("protocol-version", sec_protocol_metadata_get_negotiated_protocol_version(m),
   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   sec_protocol_metadata_get_negotiated_tls_protocol_version
```

So the driver is not compiling the same thing the hand build compiles, even though both name the same
three sources. That is the defect, and it is in `run-cases.sh`'s invocation for this case, **not** in the
merged accessors and **not** in the case.

Not yet found: which part of the driver's build differs. `PMA` is quoted correctly and does split into
two files, and the driver's binary does define all three symbols, so it is linking the port's code and
still answering differently — which is the part of this that remains open.
