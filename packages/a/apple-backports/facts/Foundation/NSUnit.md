# NSUnit

Introduced in iOS 10.0. A symbol and nothing else; the root of the unit classes.

Source: the host's Foundation, the newest implementation available, and the
armv7s shared cache of iOS 10.0.1 for the archive keys and the exception texts.
The two agree.

## Behaviour

| member | behaviour |
|---|---|
| `-initWithSymbol:` | designated; copies the symbol. |
| `-copyWithZone:` | returns the receiver. A unit is immutable. |
| `-isEqual:` | `[object isKindOfClass:[self class]]`, then the symbols are compared. The receiver's class decides, so a length is never equal to a mass. |
| `-description` | `[super description]` with `" %@"` of the symbol appended. |
| `+supportsSecureCoding` | `YES`. |

## Archiving

| key | encoded with | decoded with |
|---|---|---|
| `NS.symbol` | `-encodeObject:forKey:` | `-decodeObjectOfClass:[NSString class] forKey:` |

A coder that does not allow keyed coding raises `NSInvalidArgumentException`.
The two texts differ between the directions and are reproduced exactly:

- encoding: `NSUnit encoder does not allow non-keyed coding!`
- decoding: `NSUnit cannot be decoded by non-keyed archivers`

The ivar `_symbol` is declared `@private` by the SDK header, so Charon does not
declare it again.
