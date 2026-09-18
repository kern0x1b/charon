# Percent encoding and the six URL character sets, iOS 7

Source: the host's own Foundation, asked for each set's membership and for each method's answer, and the
differential run of `tests/backports/host/url/run.sh`, which compares the backport with the system over
every one of the 0x110000 scalars for each set and over the encoding and decoding of a large corpus -
7478336 checks, none of them different.

## What each set allows

Every one of the six allows the unreserved characters of RFC 3986 - the letters, the digits, `-`, `.`,
`_` and `~` - and nothing above ASCII at all. What each adds to them is the sub-delimiters its component
may carry:

| set | added to the unreserved characters |
|---|---|
| `URLUserAllowedCharacterSet`, `URLPasswordAllowedCharacterSet` | `!$&'()*+,;=` |
| `URLHostAllowedCharacterSet` | `!$&'()*+,;=` and `:[]` |
| `URLPathAllowedCharacterSet` | `!$&'()*+,=` and `:@/` |
| `URLQueryAllowedCharacterSet`, `URLFragmentAllowedCharacterSet` | `!$&'()*+,;=` and `:@/?` |

Each set is made once and answered again, so a caller may compare them by identity.

Two places where the newest implementation the host carries, macOS 27, is not what this says, and the
differential records them as observations rather than failures:

- its `URLPathAllowedCharacterSet` contains `;`, while the SDK header the applications are built against
  documents that `;` is percent-encoded in a path. iOS 7 cannot be asked - its Foundation builds these
  sets rather than storing them, so no literal of the delimiters is in its image - so the backport keeps
  what the header documents, and this line is here so the choice is not mistaken for a measurement.
- its `-stringByAddingPercentEncodingWithAllowedCharacters:` special-cases the host set and encodes `[`,
  `]` and `:` outside an IP literal although the set contains them. The backport encodes by the set it is
  given, which is what the method says it does.

## What the two methods do

`-stringByAddingPercentEncodingWithAllowedCharacters:` percent-encodes the UTF-8 of everything the set
does not allow, in upper case hexadecimal: a space becomes `%20`, `ä` becomes `%C3%A4`, an emoji becomes
its four bytes `%F0%9F%98%80`, and a percent sign is encoded like anything else, so `100%%` becomes
`100%25%25`. An empty set encodes everything, letters included. A string that is not valid Unicode - a
lone surrogate - answers nil rather than raising.

`-stringByRemovingPercentEncoding` reads the escapes back as UTF-8 and answers nil when what comes out is
not a string: `%2` at the end, `%zz`, and `%C3` on its own all give nil. Hexadecimal is read in either
case, so `%c3%a4` is `ä`. `%00` decodes to a NUL inside the string, and `+` is left alone - this is not
form encoding.
