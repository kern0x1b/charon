# NSFileProviderManager: what answers, and where the answer comes from

The first family of the FileProvider port, and the one with 38 of the 217 missing rows in
`coordination/corpus/ledger/FileProvider.tsv`. The class arrived in iOS 11.0; the release this
port builds is 6.1.3, which has no FileProvider framework and no extension host at all, so the
whole family is the port's own work.

## Oracle: the documentation, because the host is forbidden or absent

**The host cannot answer these questions, and it is worth saying exactly which part of it is
why.** macOS has FileProvider, and the coordinator's expectation was that `+managerForDomain:`,
`+getDomainsWithCompletionHandler:`, `placeholderURLForURL:` and the error domain are measurable
there. Compiled against the Command Line Tools' macOS SDK, they are not:

```
manager-host.swift:20:37: error: 'defaultManager' is unavailable in macOS
manager-host.swift:23:61: error: 'providerIdentifier' is unavailable in macOS
error: 'placeholderURLForURL(for:)' is unavailable in macOS
error: type 'NSFileProviderManager' has no member 'manager'
```

`defaultManager` and `providerIdentifier` are **iOS-only**, and so is the placeholder URL; the
manager-for-a-domain class method is absent from the macOS SDK under any spelling tried. So the
manager a domain owner talks to exists only on the platform whose extension host the port also
lacks.

**And the rest is forbidden rather than absent**, on the host as on the device: `addDomain:`,
`removeDomain:`, `removeAllDomainsWithCompletionHandler:`, `signalEnumeratorFor…`,
`claimKnownFolders:…` and `registerURLSessionTask:` change the state of the machine, and the rule
is the same as NetworkExtension's. A differential that called them would be testing the Mac.

**What follows for the port.** Each member of the 11.0 core therefore answers from the header and
its documentation, and the facts say so rather than implying a measurement happened:

| member | answer on 6.1.3 | where the answer comes from |
| --- | --- | --- |
| `+defaultManager` | a manager with no domains | documentation: there is no extension host, so the default manager is empty, not absent |
| `+getDomainsWithCompletionHandler:` | an **empty array and no error** | documentation: no host means no domains, and an empty list is not a failure |
| `+managerForDomain:` | nil, and the completion with `NSFileProviderErrorDomainNotFound` | the header's documented error, whose value the header carries |
| `-placeholderURLForURL:` | the URL itself, unchanged | documentation: with no domains there is no placeholder mapping, so the file is where it is |
| `-stateDirectoryURLWithError:` | the container's own directory, no error | documentation: a manager with no domains still has state |
| `-addDomain:` / `-removeDomain:` | the completion with the documented error | documentation; **forbidden on the host**, so there is no oracle even if the host had the class |
| `+NSFileProviderError` values | the values in the header | the header; the `domain` string `NSFileProviderErrorDomain` is the framework's own and is the same on every platform that has it |

The error constants are the one part that is *almost* measurable — the host's own
`NSFileProviderError.Code` carries `rawValue` and `domain` — and the header carries the same
numbers, so the port exports the header's and quotes the host for the domain string. What the host
could not give is a manager to ask.

## The honest limit

There is **no differential for this family's behaviour**, because there is no second
implementation on this machine to compare against: the class is iOS-only, the calls that would
exercise it are forbidden, and the release the port targets has no such framework. The differential
that *can* exist is over the **constants and the shapes** — the error domain, the raw values, the
empty-domains contract — and that is what a mutant would be written against: change the value a
constant carries, and the differential goes red.
