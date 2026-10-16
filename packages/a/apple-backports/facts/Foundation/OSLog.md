# The unified log's os_log, iOS 9 and 10

Introduced in iOS 9.0: `_os_log_internal`, `_os_log_create`, `_os_log_default`, `os_log_is_enabled` and
`os_log_is_debug_enabled`. Introduced in iOS 10.0: `os_log_create`, `os_log_type_enabled` and `_os_log_impl`.

Source: libsystem_trace of the armv7s cache of iOS 10.3.4, read function by function, and the host's own os_log run beside
the port (`host/oslog`); the device test `oslog.m` holds iOS 6 to the host's answers.

## Which function a program calls

The macros of `<os/log.h>` choose by the deployment target the program is built for. From 10.12 they build the arguments
into a buffer with `__builtin_os_log_format` and call `_os_log_impl` (11.0 adds `_os_log_error_impl` and
`_os_log_fault_impl`, and the `_os_log_disabled` object that `OS_LOG_DISABLED` is, 13.0 `_os_log_debug_impl`), after
asking `os_log_type_enabled`. Measured: at 10.11 the same macros still call `_os_log_internal`, so the buffer path
starts at 10.12 (`OS_LOG_TARGET_HAS_10_12_FEATURES`). Below it, which is every program that runs on iOS 6,
`os_log`, `os_log_info`, `os_log_debug`, `os_log_error` and `os_log_fault` all call the
variadic `_os_log_internal(dso, log, type, format, ...)`, `os_log_create` is `_os_log_create(dso, subsystem, category)`
and `os_log_debug_enabled` is `os_log_is_debug_enabled`. So the functions a program for iOS 6 imports are the ones
of iOS 9. The port carries those, the iOS 10 `os_log_create` and `os_log_type_enabled`, and the buffer functions, which
a program built for 10.12 or later calls. The buffer functions decode the packed buffer with the decoder
`_os_log_internal` uses; no iOS 6 program reaches them, so they are carried for a program built against a later SDK.

## The log

`os_log_create(subsystem, category)` answers a log object, the same one every time for the same pair: the release keeps
them in a tree keyed by both strings, and answers one that is retained, with the count of a global object, so a log is
never let go. `_os_log_default` is a statically made object of the same class, the value of `OS_LOG_DEFAULT`. The port's
class is `CharonOSLog`; its default object takes its class when the library loads. The release's class, `OS_os_log`, is private and is not carried. `charon_os_log_named` keeps every log in one static table and
never removes one, so each log lives as long as the process. The port does not replace the class's `-retain`,
`-release` or `-retainCount`: replacing them recursed through `objc_storeStrong` (measured with lldb), and the table
already keeps the logs alive.

`os_log_type_enabled(log, type)` answers NO for no log. For default, error and fault it answers YES. For info and debug
it answers what the preferences and the log stream attached to the process say; with none of either, which is what iOS 6
has, that is NO. `os_log_is_enabled` answers YES for any log, and `os_log_is_debug_enabled` is the question for debug.

`_os_log_internal` asks `os_log_type_enabled` first and writes nothing where it says NO, so an info or a debug message
is not written unless the release would write it. The buffer functions make the same check before they decode. The
`errno` of the call is kept for `%m`.

## The packed buffer

Measured on the host with a 10.12 target, the buffer is a summary byte, the item count, then per item a descriptor byte
(type in the high nibble, privacy in the low one), a length byte and that many bytes:

- a string (`%s`, `%ls`, `%S`) and an object (`%@`) are the pointer's value, 8 bytes on arm64; a NULL string is 0;
- `%P` is the pointer to its bytes;
- scalars are their own bytes, `%p` and a floating value too;
- a literal precision on `%s`, `%ls`, `%S` or `%P` (`%.2s`, `%.0s`) is a count item of its own, ahead of the value; a
  precision on an integer, a float, `%c`, `%p` or `%@` is not packed at all; `%.*s` packs the precision as a count item
  too, and `%*s` packs the width as a scalar;
- a `mask.hash` decorator packs the hash of the value as an item of its own, ahead of everything else for that argument,
  and the value follows it;
- `%m` packs an item of zero length (type 6), which the decoder skips; the decorators `bool`, `BOOL`, `errno`, `time_t`,
  `darwin.mode`, `darwin.signal` and `uuid_t` pack nothing extra, and the decoder takes them from the format.

The compiler packs exactly the items its format asks for, so a buffer that runs out early is not one a macro makes. The
host answers such a buffer when `_os_log_impl` is called with one directly (a scratch probe): a buffer with no items for
`%d` prints `<decode: missing data>`, and a `%s` given a scalar item prints `<decode: mismatch for [%s] got [SCALAR
sz:4]>`. The port does not write those markers yet: where the buffer runs out it reads a missing value as zero and a
missing string as `(null)`. That is an open crutch, see `coordination/crutches.md`.

## What is written

The release stores the format string and the packed arguments and leaves the formatting to whatever reads the log later,
which hides the private values and applies the decorators. iOS 6 has no such reader, so the port makes the text when the
call is made and writes it to the system log through ASL: at the notice level for a default message, the error level for
an error and the critical level for a fault, with the subsystem as the facility and, when the log has a category, `[category]
` in front. A default log has neither.

The text is what the release's own formatter makes of the same call. The host's os_log, asked for its developer output
(`OS_ACTIVITY_DT_MODE`), is what the test compares to, on 62 calls, each run twice: through the varargs call that
`_os_log_internal` receives (`host/oslog`), and through the packed buffer that `_os_log_impl` receives at a 10.12 target
(`host/oslog-buffer`). Both cover:

- every conversion of C with its flags, width, precision, `*` and length modifiers, `%%`, `%c`, `%p`, `%s` (`(null)` for a
  null pointer), `%m` and, for an unknown conversion, the character itself;
- `%@`: the object's `-description`, `(null)` for nil, the width and flags applied as to a string and a precision
  ignored;
- `%P` with a length as its precision: the bytes in upper-case hex between quotes;
- the decorators `public`, `private`, `sensitive` and `mask.*` that change nothing in developer output, `bool` (`true` or
  `false`), `BOOL` (`YES` or `NO`), `errno` and `darwin.errno` (`[2: No such file or directory]`, `[0: Success]`),
  `time_t` (local time as `2023-11-14 23:13:20+0100`), `darwin.mode` (`-rwxr-xr-x`), `darwin.signal` (`[sigkill: Killed]`),
  `uuid_t` (upper-case with hyphens) and `mask.hash` (the value, not its hash); blanks after a comma are skipped, as the
  host skips them (`{private, bool}` is `true`, measured outside the battery); any other name is ignored and the value
  written plain, which is what the release does with a name it does not know;
- the text as a whole: a byte that is not part of valid UTF-8, or is a control character other than tab and newline, is
  written as `vis(3)` writes it (`\^A`, `\M-C`), and the trailing spaces, tabs and newlines are cut.

Where it differs:

- The decorators `iec-bytes`, `bitrate`, `timeval` and `timespec`, and the address and directory-service ones, are
  written plain: the release formats them for a reader, the port does not.
- Nothing is redacted. The release stores private values and hides them when the log is read on a device that is not in
  development; the developer output the port follows shows them.
- A precision that cuts a multi-byte character in a string is cut at the byte, where the release writes a marker.
- The `%@` of a date is the object's own `-description`, as iOS 10 asks it; the host today writes it differently.
- Preferences, log streams, the `log` tool, persistence and the other types' fields (`os_log_type_t` levels beyond the
  five levels of ASL) are not there.
