# The browser of Network, and what a browse result is

`nw_browser_*` and `nw_browse_result_*` are the surface iOS 13 added for looking for Bonjour services,
and this is what they are built on.

## The substrate is the release's own DNS-SD

A browse is a PTR query for a service type in a domain, so the port asks it with `DNSServiceQueryRecord`
and reads each instance name out of the answer; `DNSServiceResolve` then answers for each instance with
the port it publishes and the record it advertises. Both are the documented C interface of
mDNSResponder (`dns_sd.h`, shipped in the SDK) and both are on the armv7 ladder's releases:

| entry point | 6.0 cache |
| --- | --- |
| `DNSServiceQueryRecord` | `libSystem.dylib` (`coordination/corpus/caches/6.0.tsv`, `_DNSServiceQueryRecord`) |
| `DNSServiceResolve` | `libSystem.dylib` (same file, `_DNSServiceResolve`) |
| `DNSServiceProcessResult` | `libSystem.dylib` (same file, `_DNSServiceProcessResult`) |
| `DNSServiceRefSockFD` | `libSystem.dylib` (same file, `_DNSServiceRefSockFD`) |
| `DNSServiceRefDeallocate` | `libSystem.dylib` (same file, `_DNSServiceRefDeallocate`) |

Every callback runs on the queue the program gave the browser: each reference is driven by a dispatch
source over its own descriptor (`DNSServiceRefSockFD`, `DNSServiceProcessResult`), created on that
queue, and no handler runs before `nw_browser_start` has returned to its caller.

**The floor of the ladder is not measured.** The armv7 ladder this package builds ends at 10.3.4 and
the oldest export list this machine holds is iOS 6.0, so the five entry points are weak imports and a
band without them gets the browser's own documented failure, `nw_browser_state_failed` with
`nw_error_domain_dns`. Nothing else is conditional on their absence.

## Why the browse is a PTR query and not `DNSServiceBrowse`

The build SDK is iOS 16.4 and its `dns_sd.h` declares

```
DNSServiceErrorType DNSServiceBrowse(DNSServiceRef *sdRef, DNSServiceFlags flags, uint32_t interfaceIndex,
                                     const char *regtype, const char *domain,
                                     DNSServiceBrowseReply callBack, void *context);
```

with an `interfaceIndex` this port's releases do not pass - the parameter was added to the header
years after they shipped, so a call written as the 16.4 header declares it reads a register the
release never wrote. The release's own symbol is six parameters. `DNSServiceQueryRecord` and
`DNSServiceResolve` have carried `interfaceIndex` since the API was introduced, so their signatures are
the same on every release this port builds, and the browse is expressed with them instead: a PTR query
for `<type>.<domain>` enumerates exactly the instances a browse enumerates, and each answer carries the
`interfaceIndex` a browse callback carries.

`DNSServiceBrowse` is not weak-imported and never called, so the band that has it says nothing.

## Which file holds which call, and why

An object carries the API of one release, measured from the export trie of the caches the ladder holds
and not from the SDK's `API_AVAILABLE`, and this family splits along that measurement:

| file | calls | measured |
| --- | --- | --- |
| `nw12-browser.m` | `nw_browser_create`, `nw_browser_cancel`, and the object | 12.0 |
| `nw16-browser.m` | the two copy calls, `nw_browser_set_queue`, the two handler setters, `nw_browser_start`, and the five `nw_browse_result_*` | 16.0 |

`coordination/corpus/caches/12.0.tsv` carries `_nw_browser_create` and `_nw_browser_cancel` in
`libnetwork.dylib` and carries neither `nw_browser_set_queue` nor any `nw_browse_result_*`; the 16.0
file carries `_nw_browser_set_queue` and `_nw_browse_result_get_changes` in `Network`. The ladder has
no rung between 12.0 and 16.0, so everything the SDK's header calls iOS 13 is placed at 16.0 - the same
reason `nw16-listener.m` holds the listener's iOS 13 and iOS 15 calls.

## The interfaces of a result

A browse result hands out `nw_interface_t`. The only objects of that type anywhere on a release with no
Network.framework are the ones `Foundation/NWPathMonitor.m` makes for the path, so the browser keeps one
object per index as the path monitor reports it and an answer naming an index picks its object out of
that table (`nw_interface_get_index` is the port's own way of saying which interface an object is).
Two consequences, both of them what the port can see and neither of them a guess:

* an answer naming an interface the port has no object for - one that went down between the answer and
  the last path update - contributes no interface, and `nw_browse_result_get_interfaces_count` counts
  what is there;
* the path monitor reports the interfaces that carry an address and are up, so an interface that is up
  but not on any path has no object and is not reported.

## What is verified

`tests/backports/host/network-objects` compiles every file of `Network/` - these two included - with
every name it defines renamed, links it beside the host's own Network.framework and runs 203 checks of
the object families (`checks=203 failures=0`). The browser's own state machine is **not** in that
differential and has no host check: a browse result can only be made by a browser that found a service
on a live link, and this machine publishes none, so there is no oracle to compare it against. What the
differential does cover for these two files is that they compile and link against the host's
Network.framework with every name they define renamed, which is a real check of the declarations they
make.

What is measured about the host is what the differential's log records for the families it does compare;
nothing in these files' registry entries quotes a host answer, and each of them says where its behaviour
comes from instead.