# The formatting context and the minimum grouping digits, iOS 8.0 and 18.0

Source: the SDK 26.2 headers; the host's own `NSNumberFormatter` (a fresh one answers
`formattingContext` 0 = `NSFormattingContextUnknown` and `minimumGroupingDigits` **1**, measured).

## The grouping is applied

The minimum grouping digits decide which of the groups the release's own formatter wrote are long
enough to keep a separator. The port formats with the release, then walks the result from the back --
so a group of digits is known before the separator that follows it is written or taken off -- and keeps
a separator only for a group of at least the number asked for. With the host's own default of 1,
`1.234` keeps its separator; asking for 2 takes it off a three digit group.

The first version of the walk wrote a separator in front of every run, which for a minimum of 0 turned
`1,234` into `1,,234` and `-1,234.5` into `--1,-234.-5`; the differential over three locales, five
thresholds and five numbers found it, and the condition is now "at least the minimum **and** a group
of digits". A sign is a group like any other and is held to the same rule.

## The context is kept and answered, and is not applied to the digits

The line direction contexts that move a negative sign arrived with iOS 26, and the release's own
number formatting has no such context: its enumerations are the capitalisation ones, which a number
does not use. A port that moved the sign would be writing something the release's formatter does not,
so the port keeps the value the application sets, answers it, and leaves the digits as the release
wrote them. That is the whole of what the property does on this release, and it is a divergence from
iOS 26 that is written down here rather than papered over.
