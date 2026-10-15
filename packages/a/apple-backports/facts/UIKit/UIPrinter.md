# UIPrinter, iOS 8

Introduced in iOS 8.0 as a printer named by its URL, with a description of it and a check that it can be reached. The
SDK 16.4 header is the contract: `+printerWithURL:`, `-contactPrinter:` and seven read-only properties (`URL`,
`displayName`, `displayLocation`, `makeAndModel`, `supportedJobTypes`, `supportsColor`, `supportsDuplex`), all 8.0.

The release (6.1.3) has no public printer object; its print panel is `UIPrintInteractionController`
(facts in `registry/UIKit/ios15-16.json`). So a `UIPrinter` here is a value: the URL it was made with, and the
descriptive properties the host gives a printer it cannot describe. Nothing about a printer is read from the printing
system.

## Answers, measured on the host

A probe on Mac Catalyst, and the differential in `tests/backports/host/uikit-printer/` for the matching lines:

- `+printerWithURL:` returns an object for every URL, including nil, and a new object on each call (not identical).
  The `URL` reads back the URL given, or nil for nil.
- `displayName` is the empty string, not nil, for every URL tried; `displayLocation`, `makeAndModel` are nil;
  `supportedJobTypes` is 0; `supportsColor` and `supportsDuplex` are NO.
- `-contactPrinter:` answers NO for every URL nothing answers: a connection refused on 127.0.0.1:9, a URL with no host
  (`ipp:///ipp/print`), a file URL, and a name that does not resolve (`nonexistent.invalid`). The handler runs once, on
  the main queue, after the call has returned.
- A nil URL: the handler runs at once, before `-contactPrinter:` returns, with NO. This is the one case that answers
  synchronously.
- A nil handler: the call returns and nothing is reached.
- A black-hole address (192.0.2.1:631, which nothing answers): the handler runs with NO after 30.5 s on the host. This
  was measured once; the differential does not run it, because it waits half a minute.

## What the port does

- The descriptive properties return the host's defaults above.
- `-contactPrinter:` opens a TCP connection to the URL's host and port (631 for ipp and ipps, 80 for http, 443 for
  https; an explicit port wins). It answers YES if the connection is made and NO otherwise, including a URL with no
  host, another scheme, a name that does not resolve, or a refused or timed-out connection. The connection is
  non-blocking, with a 30 s bound from the call, matching the host's black-hole time. The name lookup itself is not
  bounded by that bound.
- The answer is delivered on the main queue, after the call returns, except for a nil URL, which answers at once.

## Open

- A reachable printer is not measured: no printer exists to reach from the host. The port answers YES on any TCP
  connection to the URL's port, which says the URL is reachable, not that a printer answers IPP there. A real printer
  might answer NO where the port answers YES, or the reverse.
- The port's 30 s bound is not run by the differential. The host's 30.5 s is measured; the port's timeout is not.
- Object identity is not kept: each `printerWithURL:` call returns a new object, as on the host.

## Device

Not run on a device. The 6.1.3 device has no printer to contact and no print system to query for one.
