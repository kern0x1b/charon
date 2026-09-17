# NSArray and NSDictionary, the URL API of iOS 11.0

Introduced in iOS 11.0: reading and writing a property list through a URL with
an error instead of a plain `nil`.

Source: Foundation of the arm64 shared cache of iOS 11.0 (iPod7,1 15A372); the
current behaviour from the differential test against the host's Foundation
(`tests/backports/host/foundation11`). `NSDictionary` carries the same three
methods with the same shape, so both classes share this file.

| method | address in 11.0 |
|---|---|
| `-[NSArray writeToURL:error:]` | `0x181506f70` |
| `+[NSArray arrayWithContentsOfURL:error:]` | `0x1815069e4` |
| `-[NSArray initWithContentsOfURL:error:]` | `0x181506ac8` |
| `-[NSDictionary writeToURL:error:]` | `0x181521348` |
| `+[NSDictionary dictionaryWithContentsOfURL:error:]` | `0x1815214fc` |
| `-[NSDictionary initWithContentsOfURL:error:]` | `0x1815215e0` |

## Writing

1. The receiver is checked for being a property list.
2. The format is **XML** (`NSPropertyListXMLFormat_v1_0`, the constant `100`),
   unless the `NSWriteOldStylePropertyLists` default is set, which 11.0 reads
   from `NSUserDefaults` once and caches. The port always writes XML: the old
   style is a defaults switch of the desktop and nothing on iOS 6 sets it.
3. `+[NSPropertyListSerialization dataWithPropertyList:format:options:error:]`
   with no options.
4. `-[NSData writeToURL:options:error:]` with `NSDataWritingAtomic`.

Failures come out of those two calls unchanged: `3851`
(`NSPropertyListWriteInvalidError`) for a value that is not a property list,
`518` for a URL whose scheme cannot be written to, `4` for a path whose folder
does not exist.

## Reading

1. A `nil` URL answers `nil` and leaves the error alone.
2. The data is read with `-[NSData initWithContentsOfURL:options:error:]` and no
   options — 11.0 takes a string argument through
   `-initWithContentsOfFile:options:error:` instead, which the SDK's type does
   not allow the port to receive.
3. `+[NSPropertyListSerialization propertyListWithData:options:format:error:]`
   with no options.
4. The value is checked for being of the wanted kind.

`+…WithContentsOfURL:error:` is `allocWithZone:nil` and `-initWithContentsOfURL:error:`.

Errors: `260` for a file that is not there, `256` for a scheme that cannot be
read, and whatever the property list serializer raises for damaged data.

## Two departures from 11.0

- **A value of the wrong kind.** 11.0 answers `nil` and leaves the error as the
  serializer left it — often untouched, so the caller sees a `nil` with no
  reason. The current implementation answers `nil` with `NSCocoaErrorDomain`
  `259` (`NSFileReadCorruptFileError`) and
  `<url> did not contain a top-level array value` (or `dictionary`) in
  `NSDebugDescription`. An empty file reads the same way. The port implements
  the current behaviour: a caller that checks the error deserves one.
- **Mutability.** 11.0 returns the property list object itself, so
  `[[NSMutableArray alloc] initWithContentsOfURL:error:]` answers an immutable
  array. The current implementation answers a mutable one. The port builds the
  result with `-initWithArray:` (`-initWithDictionary:`), which gives the
  receiver's own kind and matches the current behaviour.
