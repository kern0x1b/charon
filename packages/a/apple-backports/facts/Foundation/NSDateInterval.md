# NSDateInterval

Introduced in iOS 10.0. A closed interval `[startDate, endDate]`.

Source: the host's Foundation and the armv7s shared cache of iOS 10.0.1.

## Behaviour

| member | behaviour |
|---|---|
| `-init` | the current date, duration 0. |
| `-initWithStartDate:duration:` | designated; the start date is copied. |
| `-initWithStartDate:endDate:` | the duration is `[endDate timeIntervalSinceDate:startDate]`. |
| `-endDate` | derived, never stored: the start date plus the duration. |
| `-copyWithZone:` | returns the receiver. |
| `-compare:` | the start dates first; equal start dates are ordered by duration. |
| `-isEqualToDateInterval:` | the start dates with `-isEqualToDate:` and the durations with `==`. |
| `-containsDate:` | closed on both ends: a date equal to the start or the end is contained. An interval of duration 0 contains its own instant. |
| `-intersectsDateInterval:` | either interval contains an end of the other. |
| `-intersectionWithDateInterval:` | `nil` when they do not intersect; otherwise the later start to the earlier end. Intervals that only touch at an instant intersect in an interval of duration 0, not in `nil`. |
| `-hash` | the start and end dates. |
| `-description` | `%@ (Start Date) %@ + (Duration) %f seconds = (End Date) %@`, opened by `[super description]`. |
| `+supportsSecureCoding` | `YES`. |

## Archiving

| key | encoded with | decoded with |
|---|---|---|
| `NS.startDate` | `-encodeObject:forKey:` | `-decodeObjectOfClass:[NSDate class] forKey:` |
| `NS.endDate` | `-encodeObject:forKey:` | `-decodeObjectOfClass:[NSDate class] forKey:` |

The end date is archived although it is derived, and decoding goes back through
`-initWithStartDate:endDate:`.

Non-keyed coders raise `NSInvalidArgumentException`. The encoding text is
Apple's own, and it says the opposite of what it means; it is reproduced as it
is because the text is observable:

- encoding: `Encoder does not allow keyed coding!`
- decoding: `NSDateInterval cannot be decoded by non-keyed archivers`

## What Charon does not carry

Foundation makes `NSDateInterval` a class cluster: `+allocWithZone:` hands back
a private `_NSConcreteDateInterval` when the class asked is exactly
`NSDateInterval`. Charon implements the class directly, so `-class` answers
`NSDateInterval` where Foundation answers `_NSConcreteDateInterval`. Everything
reachable through the declared API is the same; only the private class name a
program has no business reading differs.
