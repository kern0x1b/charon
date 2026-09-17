# _UIViewCubicTimingFunction

Introduced in iOS 10.0. Private: it is in no SDK header. Two control points and
nothing else - not a `CAMediaTimingFunction` but a plain object that can make one.

Source: UIKit of the armv7s cache of iOS 10.3.4.

It is carried under Apple's own name for the same reason as
`NSUnitConverterReciprocal`: `UICubicTimingParameters` archives it as an object
under the `timingFunction` key, so the class name is written into the archive,
and an archive that cannot cross is not the same archive.

| member | behaviour |
|---|---|
| `-init` | raises `NSInvalidArgumentException`: `Don't call %@.` |
| `-initWithControlPoint1:controlPoint2:` | keeps the two points. |
| `-controlPoint1`, `-controlPoint2` | the points. |
| `-_mediaTimingFunction` | `+[CAMediaTimingFunction functionWithControlPoints::::]` of the four numbers. |
| `-copyWithZone:` | a new one with the same points. |
| `-description` | `<%@ point1 = %@ point2 = %@>` |

## Archiving

| key | encoded with | decoded with |
|---|---|---|
| `point1` | `-encodeCGPoint:forKey:` | `-decodeCGPointForKey:` |
| `point2` | `-encodeCGPoint:forKey:` | `-decodeCGPointForKey:` |

Non-keyed coders raise `NSInvalidUnarchiveOperationException`:
`%@ only supports keyed coding.`
