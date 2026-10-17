# UTTypeCopyAllTagsWithClass, iOS 8.0

The release's MobileCoreServices has no `UTTypeCopyAllTagsWithClass` (6.1.3 exports `UTTypeCopyDeclaration`,
`UTTypeConformsTo` and `UTTypeCreatePreferredIdentifierForTag`, and not this one). The SDK's CoreServices header
declares it `API_DEPRECATED("Use the UTType class instead.", ios(8.0, 15.0), ...)`, which is re-read on the day
the function was built. The port builds it in `UIKit/UTTypeAllTags8.m` over the release's own declarations and
a decoder for the identifiers the release makes for tags it has no type for.

The host's answers are the oracle: `tests/backports/host/uttypetags` holds the port to the host's own function
(`differential.m`), and `tests/backports/emulate/uttypetags` runs the same probe on the 6.1.3 guest.

## Declared identifiers

A declared identifier answers its declaration's `UTTypeTagSpecification` for the class. A string value is answered
as a one-element array, an array as itself. The class is absent from the declaration: NULL.

Measured on the host: `public.jpeg` gives `public.filename-extension` `[jpeg, jpg, jpe]` and `com.apple.ostype`
`[JPEG]`; `public.folder` gives `com.apple.ostype` `[fold, fldr, adcL, sbFd]`.

Tags are not inherited. `public.zip-archive` conforms to `public.data` (`UTTypeConformsTo` answers 1), and
`public.data` declares `com.apple.ostype` `[sbFl]`, yet `public.zip-archive` answers `com.apple.ostype` NULL. A type
that does not declare a class answers NULL for it: `public.item` for `com.apple.ostype`. An undeclared identifier
answers NULL for every class.

## Dynamic identifiers

A dynamic identifier is `dyn.a` followed by a base-32 tail. The tail's digits are five bits each, in the alphabet
`abcdefghkmnpqrstuvwxyz0123456789` (the letters `i`, `j`, `l` and `o` are absent), read most significant bit first
and regrouped into eight-bit bytes; a final group of fewer than eight bits is padding. The bytes are the identifier's
records. Two 2012 write-ups describe the format from outside Apple (alastairs-place.net, "UTIs are better than you think,
and here's why", and a MacScripter thread on dynamic UTIs); both say it is undocumented. Their description of the
alphabet, the bit grouping and the record form was checked against the host, case by case, and no code was copied
from either.

The decoded text of `dyn.age80q6xtqk` is `1=frob`, and that of the write-up's `dyn.ah62d4r34gq81k3p2su1zuppgsm10esvvhzxhe55c`
is `?0=7:3=text/X-frob:1=frob`.

The records, measured case by case:

- A record is a key, up to the next `=`, then a value, up to the next `:`. A `:` in a key belongs to the key.
- A key is a class name (`com.apple.ostype=ABCD` answers `[ABCD]`; the match is case-sensitive, so
  `COM.APPLE.OSTYPE=ABCD` answers NULL), or a code for a class. The codes measured: `1` public.filename-extension,
  `2` com.apple.ostype, `3` public.mime-type, `4` com.apple.nspboard-type. `public.pathname` has no code and is written
  by name.
- A code is read from the key's first one or two hex digits, with leading zeros allowed, and the key must be those
  digits alone or one hex digit followed by one more byte that is not a hex digit. So `1`, `03`, `1x`, `1-`, `1 ` and
  `1\xA9` name a class, while `10` (16), `1A` (26), `03x` and `1xA` name none and are looked up as class names.
- A value is a list split by unescaped `,`. An empty value is skipped. `1=,` and `1=` answer NULL.
- A backslash escapes the byte after it; a trailing backslash is kept. `1=a\,b` answers `[a,b]`, `1=a\:b` answers `[a:b]`.
- A record with no `=` after it ends the records, so `x:1=a` answers NULL and `1=a:x:1=b` answers `[a]`. A key that
  is not a class answers nothing and the records go on, so `9=abc:1=q` answers `[q]`.
- Values are UTF-8. A value that is not valid UTF-8 is dropped, but a class with a non-empty value answers an array even
  when every value was dropped: `1=\xE9` answers `[]`, while `1=\xE9,a` answers `[a]`.
- NUL is a byte of the value: `1=a\0b` answers the three characters `a`, U+0000, `b`.
- A `dyn.` prefix is any case, but the format letter after it must be `a`: `Dyn.age80q6xtqk` answers `[frob]`,
  `dyn.bge80q6xtqk` and `DYN.AGE80Q6XTQK` answer NULL.
- The tail's letters are case-insensitive: `dyn.age80Q6XTQK` answers `[frob]`. A digit outside the alphabet, a hyphen,
  or an empty tail answers NULL.
- The conformance key `?0` is not a tag class and is not answered here: it belongs to `UTTypeConformsTo`.

The values are kept as the identifier has them: `dyn.` identifiers made from a MIME type are stored lower case by
`UTTypeCreatePreferredIdentifierForTag`, and the function answers the stored text.

## Host differential

`tests/backports/host/uttypetags/run.sh` builds the port's `UTTypeAllTags8.m` and `UTTypeDynamic8.m` with the host's
`UTTypeIsDynamic` renamed, and compares `UTTypeCopyAllTagsWithClass` on every case below for seven classes:
129 declared identifiers (the SDK constants, `tests/backports/host/uttypeconstants/expected-identifiers.tsv`), the
write-up's examples, the cases above, 200000 generated record texts over an alphabet of separators, escapes, codes,
digits and high bytes, and 4000 generated tails. The run: 1429542 comparisons, 0 mismatches.

Each rule above was first measured on the host with single-case probes, before the port was written, and the
differential then held the port to all of them. The single-case probes are not committed; the differential is.

## Release

Not measured on the 6.1.3 guest yet. `tests/backports/emulate/uttypetags` builds the same `probe.m` for the guest with
the port's two files, and the host with the host's function alone (`host.sh`), so the two outputs can be compared line
by line; the guest's result is recorded here when it has run.
