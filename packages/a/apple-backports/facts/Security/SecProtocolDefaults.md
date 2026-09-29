# The four default-version values, measured rather than chosen

`sec_protocol_options_get_default_{min,max}_{tls,dtls}_protocol_version` answer what the release's own
SSL stack negotiates by default. These numbers were **measured**, on 6.1.3 and on 6.0, and the two runs
agree exactly.

## The probe, and its evidence

A program that creates an `SSLContext` and reads `SSLGetProtocolVersionMin` and `SSLGetProtocolVersionMax`
from it, for **both** a stream context and a datagram context — a stream context answers about TLS only,
so asking it about DTLS would have measured nothing. It also asks the release the 1.3 question directly,
by calling `SSLSetProtocolVersionMax(kTLSProtocol13)` and printing both the status and what the maximum
then reads.

| run | log | sha256 |
| --- | --- | --- |
| 6.1.3 | `.agent-work/runs/p613/run.log` | `055fc9f3a914c2065fe9cb9ad850d329f6fed47ab5d22e299b866ca28f90a00a` |
| 6.0 | `.agent-work/runs/p60/run.log` | `0edb2075612936a22a45ee1d46297f289eb46e7c79471410faa3a6e22bd4482e` |

## What it found

```
ssl-defaults-probe	start      context	ok
min	2                          max	8
datagram-context	ok          dgram-min	9        dgram-max	9
set-max-13	-9830           set-max-13-illegal-param	1
max-after-set-13	8         max-after-set-13-is-13	0
ssl-defaults-probe	done
```

| row | measured | the value the port returns |
| --- | --- | --- |
| min TLS | `2` — `kSSLProtocol3`, **SSL 3.0** | `TLSv10` = `0x0301` |
| max TLS | `8` — `kTLSProtocol12` | `TLSv12` = `0x0303` |
| min DTLS | `9` — `kDTLSProtocol1` | `DTLSv10` = `0xfeff` |
| max DTLS | `9` — `kDTLSProtocol1` | `DTLSv10` = `0xfeff` |

## Two findings that changed what the rows say

**The min is not expressible.** The release's default floor is **SSL 3.0**, and
`tls_protocol_version_t` has **no SSLv3 member** — its lowest is `TLSv10` = `0x0301`. So the row returns
the enum's lowest member and the difference is recorded as a crutch rather than papered over. The earlier
value for this row was a decision, and the measurement **contradicted** it: SSL 3.0 is a worse floor than
TLS 1.0, so the decision was wrong in the direction that matters.

**TLS 1.3 is refused by the release, and that is now a measurement.** `SSLSetProtocolVersionMax
(kTLSProtocol13)` returns `-9830` = `errSSLIllegalParam`, and the maximum then reads back as 8. The row
is therefore not declining to mention 1.3 — the release declines it, on both releases tested.
