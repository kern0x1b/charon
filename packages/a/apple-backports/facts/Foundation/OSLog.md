# The unified log's os_log, iOS 9 and 10

Introduced in iOS 9.0: `_os_log_internal`, `_os_log_create`, `_os_log_default`, `os_log_is_enabled` and
`os_log_is_debug_enabled`. Introduced in iOS 10.0: `os_log_create`, `os_log_type_enabled` and `_os_log_impl`.

Source: libsystem_trace of the armv7s cache of iOS 10.3.4, read function by function, and the host's own os_log run beside
the port (`host/oslog`); the device test `oslog.m` holds iOS 6 to the host's answers.

## Which function a program calls

The macros of `<os/log.h>` choose by the deployment target the program is built for. From 10.0 they build the arguments
into a buffer with `__builtin_os_log_format` and call `_os_log_impl` (11.0 adds `_os_log_error_impl` and
`_os_log_fault_impl`, 13.0 `_os_log_debug_impl`), after asking `os_log_type_enabled`. Below 10.0, which is every
program that runs on iOS 6, `os_log`, `os_log_info`, `os_log_debug`, `os_log_error` and `os_log_fault` all call the
variadic `_os_log_internal(dso, log, type, format, ...)`, `os_log_create` is `_os_log_create(dso, subsystem, category)`
and `os_log_debug_enabled` is `os_log_is_debug_enabled`. So the functions a program for iOS 6 imports are the ones
of iOS 9. The port carries those, and `os_log_create` and `os_log_type_enabled` of iOS 10 for a program that names them,
and leaves the buffer functions out: a program that runs on iOS 6 is built for a deployment target below the one that
reaches them.

## The log

`os_log_create(subsystem, category)` answers a log object, the same one every time for the same pair: the release keeps
them in a tree keyed by both strings, and answers one that is retained, with the count of a global object, so a log is
never let go. `_os_log_default` is a statically made object of the same class, the value of `OS_LOG_DEFAULT`. The port's
class is `CharonOSLog`, whose `-retain`, `-release`, `-autorelease` and `-retainCount` make it immortal; its default object
takes its class when the library loads. The release's class, `OS_os_log`, is private and is not carried.

`os_log_type_enabled(log, type)` answers NO for no log. For default, error and fault it answers YES. For info and debug
it answers what the preferences and the log stream attached to the process say; with none of either, which is what iOS 6
has, that is NO. `os_log_is_enabled` answers YES for any log, and `os_log_is_debug_enabled` is the question for debug.

`_os_log_internal` asks `os_log_type_enabled` first and writes nothing where it says NO, so an info or a debug message
is not written unless the release would write it. The `errno` of the call is kept for `%m`.

## What is written

The release stores the format string and the packed arguments and leaves the formatting to whatever reads the log later,
which hides the private values and applies the decorators. iOS 6 has no such reader, so the port makes the text when the
call is made and writes it to the system log through ASL: at the notice level for a default message, the error level for
an error and the critical level for a fault, with the subsystem as the facility and, when the log has a category, `[category]
` in front. A default log has neither.

The text is what the release's own formatter makes of the same call. The host's os_log, asked for its developer output
(`OS_ACTIVITY_DT_MODE`), is what the test compares to, on 61 calls covering:

- every conversion of C with its flags, width, precision, `*` and length modifiers, `%%`, `%c`, `%p`, `%s` (`(null)` for a
  null pointer), `%m` and, for an unknown conversion, the character itself;
- `%@`: the object's `-description`, `(null)` for nil, the width and flags applied as to a string and a precision
  ignored;
- `%P` with a length as its precision: the bytes in upper-case hex between quotes;
- the decorators `public`, `private`, `sensitive` and `mask.*` that change nothing in developer output, `bool` (`true` or
  `false`), `BOOL` (`YES` or `NO`), `errno` and `darwin.errno` (`[2: No such file or directory]`, `[0: Success]`),
  `time_t` (local time as `2023-11-14 23:13:20+0100`), `darwin.mode` (`-rwxr-xr-x`), `darwin.signal` (`[sigkill: Killed]`)
  and `uuid_t` (upper-case with hyphens); any other name, or a name with spaces, is ignored and the value written plain,
  which is what the release does with a name it does not know;
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
