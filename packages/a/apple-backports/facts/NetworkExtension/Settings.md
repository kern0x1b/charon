# NEDNSSettings: pure state, and what each answer was measured against

The settings objects are state and nothing else: the system reads them when a configuration is
applied, and the port's object holds what a caller sets. That is why the implementations here are
property storage with the `NSCopying`/`NSSecureCoding` behaviour the header declares, and why no daemon
is involved — an object that answered from a daemon would be a different API.

## What the host's own NetworkExtension answers, and the dladdr proof

The differential is **two binaries**, because one process cannot hold both implementations of a class
with the same name and a comparison that cannot say which answered proves nothing:

```
$ sh tests/backports/host/netext-settings/run.sh
=== host: Apple's own answers, and the image that answered
dladdr	NetworkExtension          <- from /System/Library/Frameworks/NetworkExtension.framework
=== port: the port's own answers, Apple's framework not linked at all
dladdr	port
=== compared, name by name
ok  fresh.servers (nil)          ok  fresh.searchDomains (nil)   ok  fresh.matchDomains (nil)
ok  fresh.matchDomainsNoSearch YES   ok  copy.isSameObject NO      ok  copy.isKindOfClass YES
ok  archive.hasData YES          ok  archive.errorDomain (none)  ok  roundTrip.isKindOfClass YES
ok  roundTrip.servers (nil)
=== the three names Apple's class does not carry, against the iOS 26.2 header
ok  dnsProtocol    declared in the 26.2 header (@property (readonly) NEDNSProtocol dnsProtocol)
ok  domainName     declared in the 26.2 header (@property (copy, nullable) NSString *domainName)
ok  allowFailover  declared in the 26.2 header (@property BOOL allowFailover)
compared=13 failed=0
```

`dladdr` on the `servers` selector's implementation pointer names the answering image in each binary,
which is the proof the comparison rests on: `NetworkExtension` on the host side, `port` on the port
side. The host's class does **not** carry `dnsProtocol`, `domainName` or `allowFailover`, so those three
are checked against the 26.2 header's own declarations and `run.sh` fails if the header does not have
them — a different oracle, named as such rather than dressed up as a host comparison.

## What the differential found

`fresh.matchDomainsNoSearch`: the host answers **YES** on a fresh object, and the port answered **NO**
— the zero a fresh `BOOL` ivar gives. The default is now YES, with a line saying the differential
caught it. That is the whole reason the two answers are in two binaries and compared, rather than the
port's defaults being written down from the header and believed.

## The mutants

One per comparison, seven of them, each has to go red naming its own comparison and a mutation that
does not build is RUN FAILED, never counted as noticed:

```
$ sh tests/backports/host/netext-settings/run.sh --mutation
noticed fresh.servers   noticed fresh.searchDomains   noticed fresh.matchDomains
noticed fresh.matchDomainsNoSearch                   noticed copy.isSameObject
noticed copy.isKindOfClass                           noticed roundTrip.servers
mutations noticed: 7, failures: 0
```

## The compile, with the gate's flags and no -w

```
$ clang -target armv7-apple-ios6.1.3 -isysroot <16.4 SDK> -fobjc-arc -Os -g0 -Wall \
        -Wno-unguarded-availability-new -Wno-unguarded-availability \
        -Werror=objc-missing-property-synthesis -I… -c NetworkExtension/NEDNSSettings.m
exit=0  errors=0  warnings=1
  the one warning is the sysroot line every file in this package prints
```

## The rest of the family

`NEDNSSettingsManager` and the other manager classes are the half of NetworkExtension that talks to the
system's preference daemon, and they are a different job: they answer as Apple does without an
entitlement, with the documented error domain and codes, measured on the host. The four classes
`NEProxySettings`, `NEProxyServer`, `NEIPv4Settings` and `NEIPv4Route` are settings objects like this
one, and the ledger's spelling of two of `NEProxySettings`'s properties is wrong: the 26.2 header
declares **`HTTPEnabled`, `HTTPSEnabled` and `HTTPSServer`**, capitalised, where the ledger rows are
lowercase. Noted here for the ledger owner; the rows are written as the header declares them.
