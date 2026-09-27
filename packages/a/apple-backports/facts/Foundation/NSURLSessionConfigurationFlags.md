# The eight configuration settings of iOS 9 to 26

`shouldUseExtendedBackgroundIdleMode`, the two TLS versions, `requiresDNSSECValidation`,
`allowsUltraConstrainedNetworkAccess`, `usesClassicLoadingMode`, `enablesEarlyData` and
`multipathServiceType`. Each is kept beside the configuration, which is what the header promises: a
configuration carries them and a session built from it reads them back.

Which of them the port can *act on* differs each way, and that is written down rather than left to a
reader:

- **`shouldUseExtendedBackgroundIdleMode`** is read by the port's own session, which is the only thing
  here that could idle a background session at all: 6.1.3 has no such mode, and the port's session is
  the code that would enter it.
- **The two TLS versions** are read by the port's **stream** task, which negotiates its own TLS over
  the release's `CFStream` pair, and by nothing else. The port's data path runs over the release's own
  `NSURLConnection`, which is the system's TLS and takes no version from a port.
- **`requiresDNSSECValidation`** is kept and answered. The release's resolver validates what it
  validates, and 6.1.3 has no such validation to ask for, so the value the application sets is the
  value it reads back.
- **`allowsUltraConstrainedNetworkAccess` and `usesClassicLoadingMode`** are kept and answered for the
  same reason: the release's connection is not a port's to change. The first joins
  `allowsExpensiveAccess` and `allowsConstrainedAccess`, which
  `NSURLRequest+NetworkAccess13.m` already keeps.
- **`enablesEarlyData` and `multipathServiceType`** are kept and answered, and for a second reason as
  well: 6.1.3 has neither early data nor multipath, so there is nothing here to switch on, and the
  header's own answer on a system without them is the default.

Measured by `tests/backports/device/foundation15batch.m` on the device, and the defaults by a fresh
configuration: every flag false, every version nil, and `multipathServiceType` at its own `None`.
