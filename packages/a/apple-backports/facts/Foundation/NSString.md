# NSString, the validated format of iOS 11.0

Introduced in iOS 11.0: a format string checked against the specifiers it is
allowed to use, so a format that arrives from outside the application cannot ask
for arguments that were never passed.

Source: Foundation of the arm64 shared cache of iOS 11.0
(`+[NSString stringWithValidatedFormat:validFormatSpecifiers:error:]` at
`0x1815863e0`, `+localizedStringWithValidatedFormat:…` at `0x181586350`, and the
real work in `-[NSPlaceholderString initWithValidatedFormat:validFormatSpecifiers:locale:arguments:error:]`
at `0x1815891ac`, which checks both arguments for `nil` and then hands the work
to CoreFoundation at `0x180b578fc`). The rule below was read off the running
implementation rather than out of that CoreFoundation parser: three thousand
random pairs of format and allowed specifiers were put to the host's Foundation
and to the port, and the two agreed on every one, verdict and message alike, as
did twenty-eight pairs chosen to be awkward rather than random: a positional
past the end, positionals mixed with sequential ones, every kind at its
boundary, an empty format, an empty list of allowed specifiers, ten slots and
eleven, an unfinished `%`, and a width given as `*`.

## The rule

Each format is read as a sequence of specifiers, numbered by position: a
specifier written `%N$…` takes slot `N`, the rest take the next free slot in
order. `%%` is not a specifier. For every slot the format uses, the **kind** of
its specifier must equal the kind of the specifier the allowed string has in
that same slot, and the format may not use more slots than the allowed string
names.

Kinds, and what is ignored:

| kind | conversions |
|---|---|
| object | `@` |
| integer | `d D i o O u U x X c C` |
| floating | `f F e E g G a A` |
| C string | `s S` |
| pointer | `p` |

Flags, width, precision and length are ignored, so `%-10@` matches `%@` and
`%.2f` matches `%f`; `%d` matches `%ld`, since both are integers, while `%@`
does not match `%s`.

Edges the awkward pairs pin down: `%0$@` is not a specifier at all — both
implementations print it as the text `0$@`; a width written `*` is refused,
since the argument that carries it has no kind to match; `%` at the very end of
a format is refused; `%%` in the allowed string names no slot, so a format with
one specifier against `%%` is refused; and the count of slots is compared
against the allowed string's, so ten against ten passes while eleven does not.

Consequences worth naming: a format that uses fewer slots than allowed passes
(`%@` against `%@ %ld`), one that uses a later slot without the earlier one does
not (`%ld` against `%@ %ld` — slot one is an object), a repeated positional
passes (`%1$@ %1$@` against `%@`), and anything in the allowed string that is
not a specifier is ignored, so `%@, %ld` reads as two slots.

## Failure

A format that does not fit answers `nil` and fills in `NSCocoaErrorDomain`
`2048` (`NSFormattingError`) with

    Format '<format>' does not match expected '<allowed>'

in `NSDebugDescription`. A `nil` format or a `nil` list of allowed specifiers
raises `NSInvalidArgumentException` with `%@: nil argument`, before anything
else happens.

When the format fits, the string is built exactly as `-initWithFormat:locale:arguments:`
builds it, with the locale the method was given: the plain form passes none, and
`+localizedStringWithValidatedFormat:` passes the current locale.
