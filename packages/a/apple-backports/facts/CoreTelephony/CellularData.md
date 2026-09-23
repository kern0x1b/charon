# CTCellularData, iOS 9

The crash-exposure row that reopened CoreTelephony: the corpus's demand index had been silent on
the whole framework because this SDK carries no CoreTelephony umbrella header for it to read, and
fixing that surfaced `telegram` calling `CTCellularData` directly (rank 222) and two of its members
(`cellularDataRestrictionDidUpdateNotifier`, `restrictedState`). `CTCellularData` reports a
cellular-data *restriction* state, not a radio *technology* - unlike
`serviceCurrentRadioAccessTechnology`'s real single-radio wall
(`facts/CoreTelephony/CTRadioAccessTechnology.md`), there is no hardware boundary here: the
iPhone 4S has a real cellular radio, and the only real question is how 6.1.3 expresses a data
restriction.

## What the device has

iOS 6.1.3's own `CoreTelephony.framework` exports `_CTServerConnectionGetCellularDataIsDisallowed`,
`_CTServerConnectionSetCellularDataIsDisallowed` and `_CTServerConnectionCreate` - confirmed
present via `modules/apple/dyld.lua`'s `image_symbols` (not `strings` on an `extract()`ed copy,
which missed them; a second instance of the recurring `extract()`/`otool -oV` gap - the export
trie itself is fine, only the rebuilt file's own symtab confuses `otool`, so reading the trie
directly is what actually found these). Disassembling both with capstone against the raw cache
bytes gives their real signature, cross-checked against the real, public `CTError` struct
(`domain`/`error`, `CoreTelephonyDefines.h`) which the null-argument path in both functions writes
verbatim - `{kCTErrorDomainPOSIX(1), EINVAL(22)}` - confirming the reverse-engineered calling
convention rather than assuming it:

```c
typedef void *CTServerConnectionRef;
CTServerConnectionRef CTServerConnectionCreate(CFAllocatorRef allocator, CTServerConnectionCallback callback, CTServerConnectionContext *context);
CTError CTServerConnectionGetCellularDataIsDisallowed(CTServerConnectionRef connection, Boolean *disallowed);
```

`CTServerConnectionCreate` internally opens a Mach IPC connection to the CoreTelephony daemon
(disassembly shows a bootstrap-style port lookup before constructing the connection object); this
port calls it once, lazily, with a `NULL` callback and context, since it only needs synchronous
reads, not the daemon's own async delivery.

The release also exports a single Darwin notification, `"com.apple.coretelephony"` - confirmed
present as a literal string in the shared cache - which this release's own CoreTelephony code
posts on any state change it tracks (radio access, cellular data restriction, and others
undifferentiated at the notification level).

## What the port does

`-restrictedState` calls `CTServerConnectionGetCellularDataIsDisallowed` fresh every time (never
cached) and answers `kCTCellularDataRestricted`/`kCTCellularDataNotRestricted` only when the call
answers `kCTErrorDomainNoError`. Any failure - `dlsym` finding nothing, connection creation
failing, or the call itself returning an error - answers `kCTCellularDataRestrictedStateUnknown`,
never `kCTCellularDataNotRestricted`: an application that cannot have its real restriction state
measured is told exactly that, not told it is unrestricted.

`-setCellularDataRestrictionDidUpdateNotifier:` registers for the Darwin notification
`"com.apple.coretelephony"` on `CFNotificationCenterGetDarwinNotifyCenter()`. Every time it fires,
`restrictedState` is re-read and the stored notifier is only called if the answer changed from the
last known one - so a radio-access change or any other CoreTelephony event this single umbrella
notification also carries does not spuriously fire a cellular-data notifier for no reason. The
notifier is also called once immediately with the current state when set, matching real
`CTCellularData`'s own documented behaviour of an immediate first call.

## What is measured and what is not

The function signatures, the `CTError` convention and the Darwin notification name are measured
from the release's own binary, not guessed. What is not yet measured, because it needs the device
and the 4S was busy this pass with the canon build: whether `CTServerConnectionCreate` tolerates a
`NULL` callback/context the way this port assumes, whether `"com.apple.coretelephony"` actually
fires on a real cellular-data-restriction change on this hardware (rather than only on radio-access
events), and end-to-end confirmation that `CTServerConnectionGetCellularDataIsDisallowed` returns a
real, sensible value rather than a permission or entitlement error this app's own process lacks.
Queued for the next 4S window.
