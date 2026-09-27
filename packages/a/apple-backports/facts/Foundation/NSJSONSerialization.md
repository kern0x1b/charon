# NSJSONSerialization

The class arrived in iOS 5.0. Below that the class itself is missing, so
`Foundation/NSJSONSerialization.m` carries it whole: `+isValidJSONObject:`,
`+dataWithJSONObject:options:error:`, `+JSONObjectWithData:options:error:`,
`+writeJSONObject:toStream:options:error:` and `+JSONObjectWithStream:options:error:`.
From 5.0 on, `band()` (modules/apple/backports.lua) reexports the release's own class
instead of this one, the same way it does for NSUUID and NSProgress, and a caller on
5.0 and later gets the release's own answers, including the release's own gaps
(`registry/Foundation/ios11.json`, `NSJSONWritingSortedKeys` ignored below iOS 11).

Every rule below is **measured against the host's own Foundation** by
`tests/backports/host/json1` (3117 comparisons, none failing), not read from the JSON
RFC and not guessed. Where the host's own answer is a quirk of its implementation, the
quirk is reproduced and named.

## What a refusal carries

`NSCocoaErrorDomain`, code `NSPropertyListReadCorruptError` (3840), with
`NSDebugDescriptionErrorKey` and `NSJSONSerializationErrorIndex` in the userInfo.
Empty data is the one refusal with neither a position nor an index: its userInfo holds
`NSDebugDescription` alone and its text is `Unable to parse empty data.` — except under
`NSJSONReadingTopLevelDictionaryAssumed`, where empty data is an empty object.

The debug description is `<reason> around line <line>, column <column>.` with the
**column counted from 0 within its line** and the index a position in the text.

The reasons, as the host words them:

| reason | where the index points |
| --- | --- |
| `Unexpected end of file during JSON parse.` | the `{`, `[`, `:` or `,` that introduced the slot a value was wanted in |
| `Unexpected end of file` | the end of the text |
| `Garbage at end` | the first character after the value |
| `JSON text did not start with array or object and option to allow fragments not set.` | the first character |
| `JSON text did not have any content` | the end of the text |
| `Badly formed array`, `Badly formed object` | the character that is neither a comma nor the closer |
| `No value for key in object` | where the `:` was expected |
| `No string key for value in object` | the first character of the key |
| `Disallowed first character in JSON5 object key` | the first character of the key (JSON5 only) |
| `Invalid value` | the first character of the value |
| `Something looked like a 'true'/'false'/'null' but wasn't` | the first character of the literal |
| `Unterminated string` | the opening quote |
| `Unescaped control character` | the control character |
| `Invalid escape sequence` | the backslash |
| `Invalid hex digit in unicode escape sequence` | the digit that is not one |
| `Unable to convert hex escape sequence (no high character) to UTF8-encoded character.` | the backslash |
| `Unexpected end of file during string parse (expected low-surrogate code point but did not find one).` | the backslash |
| `Unsupported escaped null` | the backslash (JSON5 only) |
| `Number with leading zero` | the second zero |
| `Number with minus sign but no digits`, `Number with decimal point but no additional digits`, `Number with 'e' but no additional digits`, `Number with '+' or '-' but no additional digits`, `Hex number without next digit`, `Malformed number` | where the digits were expected |
| `Number wound up as NaN` | the first character of the number |
| `Too many nested arrays or dictionaries` | an internal offset of the host, not reproduced (see below) |
| `Unterminated block comment` | the end of the text |
| `Unable to convert data to string` | 1 |

A value slot whose text ends in whitespace is the end-of-text case, not the
during-parse case: `{`, `[`, `{"a":` and `\n\n{` are one, `  {  ` is the other.

A top-level fragment that is an unterminated literal is the during-parse case at the
literal's own start (`nul` and `tru` with `NSJSONReadingAllowFragments`), while the same
literal inside a container is the literal it looked like (`[tru]`).

## The encodings

The five the header documents, by a byte-order mark first and the zero-byte pattern of
the first four bytes otherwise. **The marks are read shortest first**, which is what
decides the one case where two of them share a prefix: `FF FE 00 00` is a UTF-16LE mark,
not a UTF-32LE one — the host parses the bytes after it as UTF-16LE and then refuses
the text, where a UTF-32LE reading would have parsed it. So there is no UTF-32LE mark
here at all, and all four wide encodings are still read without one.

## Trailing commas

Accepted in an array and in an object, **unconditionally** — not gated by any option,
measured. `{a:1,}` needs `NSJSONReadingJSON5Allowed` for its bare key, its trailing
comma needs nothing.

## The number a literal comes out as

An integer literal becomes a `long long` if it fits, else an `unsigned long long` if it
fits, else an `NSDecimalNumber`. A literal with a `.` or an exponent becomes a `double`
when it has **17 or fewer significant digits** — the digits of the int and fraction
parts, a lone leading `0` not counted — else an `NSDecimalNumber`. Measured at the exact
boundary: `1.2345678901234567` (17) is a double, `1.23456789012345678` (18) is an
`NSDecimalNumber`; `0.1` is a double and `0.0000000000000000000001` (22 fraction digits)
is an `NSDecimalNumber`.

Three rules about the magnitude are the host's own and not the RFC's:

- a leading `0` followed by a digit is refused (`Number with leading zero`),
- an exponent field of **more than three digits** is refused however small its value —
  `1e-999` is a `0`, `1e-0999` is refused, `1e0000` is a `1` and `1e-0001` is refused,
- a positive exponent that overflows a double is refused while a negative one is not:
  `1e309` is refused, `-1e400` is a `-inf`.

## `NSJSONReadingJSON5Allowed`

Adds: single-quoted strings and the `\'` escape, `\xHH`, `\` before a newline, bare
identifier keys (a letter, `_` or `$`, then letters, digits, `_` or `$` — not the fuller
ECMAScript `IdentifierName`, which nothing measured reaches), `//` and `/* */` comments,
a leading `+`, a leading `.`, a trailing `.`, `0x` integers, and `NaN`, `Infinity` and
`-Infinity`. `\0` is refused under it as `Unsupported escaped null` and is an invalid
escape without it.

Two of the host's own answers are quirks reproduced as they are, because a caller can
read them:

- an upper-case `N` starts `NaN`: `[N]` is `Partial NaN around character %lu (EoF).` and
  `[Na]`, `[None]`, `[Nonsense]` are `Invalid NaN around character %lu (EoF).`, both
  with the `%lu` unexpanded, which is how the host leaves them. A lower-case `nan` is
  read as the start of `null` instead (`Something looked like a 'null' but wasn't`).
- the body of a top-level dictionary reads an **unquoted** key with nothing after it as a
  string that never closed: `Unterminated string` at the key's first character, where a
  quoted key is the end of the text.

## `NSJSONReadingTopLevelDictionaryAssumed`

The text is the **body** of an object, not an object literal: there is no brace of our
own to read and the `}` is implied by the end of the text, and the positions the host
reports for such a text are the positions of that text (`a=1;b=2` reports column 0,
where a wrap of the text in braces would have moved every position by one). Combined
with `NSJSONReadingAllowFragments` it raises `NSInvalidArgumentException` with the
reason `NSJSONReadingAssumeTopLevelDictionary and NSJSONReadingAllowFragments cannot be
set at the same time` — the host's own wording, which names the option by its Swift-era
spelling.

## How deep a container may be

512 containers that hold something. A container closed again straight away is not
counted, which is why 513 levels of `[[...]]` ending in an empty `[]` are read and the
same 513 ending in a `[1]` are refused with `Too many nested arrays or dictionaries`.

## What a write does

- Without `NSJSONWritingSortedKeys` the keys come out in **the dictionary's own order**.
  An unsorted dictionary has no order of its own to reproduce; the Foundation this is
  measured against sorts anyway, which is a difference of a generation of CoreFoundation
  and not of the API. `tests/backports/host/json1` compares the text exactly where the
  order is the caller's to choose (sorted, pretty, or a single key) and by what it parses
  back to where it is not.
- With it, the order is `-localizedStandardCompare:`, as the section below describes.
- A double or a float is written with `%.17g`: `0.1` is `0.10000000000000001`, `(float)0.1`
  is `0.10000000149011612`, `1e30` is `1e+30`, `1e-7` is `9.9999999999999995e-08`.
- An `NSDecimalNumber` is written as its own description.
- `/` is escaped unless `NSJSONWritingWithoutEscapingSlashes`; `"`, `\`, `\n`, `\r`,
  `\t`, `\b`, `\f` always, and any other character below `0x20` as `\u00xx`. `0x7F` is
  not escaped.
- A **pretty-printed empty container is a bracket, a newline, the closing indent and the
  bracket** — `[\n\n]` at the top level, `[\n\n  ]` one level down — and not `[]`.
- The exceptions, with the host's own wording: `Invalid (non-string) key in JSON
  dictionary`, `Invalid number value (infinite) in JSON write`, `Invalid number value
  (NaN) in JSON write`, `Invalid type in JSON write (<class>)`, and for a top level that
  is neither an array nor a dictionary without `NSJSONWritingFragmentsAllowed`,
  `*** +[NSJSONSerialization dataWithJSONObject:options:error:]: Invalid top-level type
  in JSON write`. Under `NSJSONWritingFragmentsAllowed` an object of a class the writer
  does not know is refused by the writer's own reason, not as an invalid top level.

## The two stream methods (7.0)

They have no exported symbol of their own for `band()` to split on, so they live in this
file and are carried with the class.

- `+writeJSONObject:toStream:options:error:` answers the number of bytes written. A
  stream that will not take them answers **-1** and an `NSFileWriteUnknownError` of its
  own with an **empty** userInfo — not the stream's own error (measured: a stream opened
  on a directory that is not there gives `NSCocoaErrorDomain` 512 and -1).
- `+JSONObjectWithStream:options:error:` reads what came and parses it. A stream that
  will not read is **not** the stream's error to report: the host reads nothing and
  answers as it answers empty data (measured: a stream on a file that is not there is
  `Unable to parse empty data.`, not the stream's `NSPOSIXErrorDomain` 2).

## `NSJSONReadingMutableLeaves`

Accepted and, like the host, of no effect on this Foundation: a leaf comes back an
`NSString` whether or not it is asked for. Measured on the host, not assumed.

## What is not reproduced

Two measured answers of the host, named so they are not mistaken for agreement:

- The **position** a `Too many nested arrays or dictionaries` refusal carries. The host
  reports an internal offset of its scanner (513 where this file reports 512, 2565 where
  it reports 2560); the wording and whether the refusal happens at all are reproduced and
  compared.
- Two answers of the host's top-level-dictionary key scanner, read off inputs the
  differential does not assert: a body key followed by `=` (`a=1;b=2`, `a="x"`) is
  `Unterminated string` at the key's first character, and a normal object key followed by
  `=` under JSON5 (`{a=1}`) is `Unterminated string` at the `=`. This file reads the `=`
  as a missing colon instead (`No value for key in object`).

## The writing option of iOS 11.0

`NSJSONWritingSortedKeys`, the option that writes a dictionary's keys in order,
arrived in iOS 11.0 with the value `2`.

Source: the ordering read from the host's Foundation, which is the same
implementation the option has had since it arrived; `+dataWithJSONObject:options:error:`
of the arm64 cache of iOS 11.0 (`0x18161acf4`) for the argument checks around it.

### The order

The keys come out in the order of `-localizedStandardCompare:`, not in byte
order: `a`, `á`, `b`, `C` rather than `C`, `a`, `b`, `á`; `item2`, `item9`,
`item10` rather than `item10`, `item2`, `item9`; `ä` before `ae`. Checked
against `-localizedStandardCompare:` on four hundred random sets of keys drawn
from letters of both cases, digits, punctuation, accented Latin, Han and Greek:
no disagreement.

### Why the port does not carry it

The option is a number the compiler writes into the call, and the call goes to the
system's `+dataWithJSONObject:options:error:`, which iOS 6 already has.
There is no selector to add and no call to intercept: the attachment mechanism
adds only what a class does not answer, and replacing a system implementation is
not something the port does. So an application that passes the option on iOS 6
gets its keys in the dictionary's own order and is told nothing. The registry
records this as `ignored`.

Had we a place to stand, the whole implementation would be one comparator.
