# NSUnitConverterReciprocal

Introduced in iOS 10.0. Private: it is in no SDK header. Converts by `y = r / x`
in both directions.

Source: the armv7s shared cache of iOS 10.0.1, confirmed on the host, where the
class still carries this name and `-[NSUnitFuelEfficiency milesPerGallon]` still
uses it.

It is carried under Apple's own name rather than a Charon one because
`NSDimension` archives its converter as an object, so the class name is written
into the archive. Under any other name an archive written here would not open in
the real Foundation, and one written there would not open here — and archive
compatibility is observable behaviour, which is what this package exists to
carry. On a release that already has the class, the whole object file is
dropped, so no release ever holds two classes of this name.

## Behaviour

| member | behaviour |
|---|---|
| `-initWithReciprocalValue:` | stores the value. |
| `-baseUnitValueFromValue:` | `reciprocalValue / value`. |
| `-valueFromBaseUnitValue:` | `reciprocalValue / value`. The conversion is its own inverse. |
| `-copyWithZone:` | returns the receiver. |
| `-isEqual:` | the reciprocal values are compared. |
| `-description` | `[super description]` with `" reciprocalValue = %f"` appended. |
| `+supportsSecureCoding` | `YES`. |

Only `NSUnitFuelEfficiency` uses it: miles per gallon is not proportional to
litres per 100 km but inverse to it.

## Archiving

| key | encoded with | decoded with |
|---|---|---|
| `NS.reciprocalValue` | `-encodeDouble:forKey:` | `-decodeDoubleForKey:` |

Non-keyed coders raise `NSInvalidArgumentException`:

- encoding: `NSUnitConverterReciprocal encoder does not allow non-keyed coding!`
- decoding: `NSUnitConverterReciprocal cannot be decoded by non-keyed archivers`
