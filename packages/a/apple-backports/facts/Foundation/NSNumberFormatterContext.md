# The formatting context and the minimum grouping digits, iOS 8.0 and 18.0

Source: the SDK 26.2 headers; the host's own `NSNumberFormatter` (a fresh one answers
`formattingContext` 0 = `NSFormattingContextUnknown` and `minimumGroupingDigits` **1**, measured).

## The grouping is applied

The minimum grouping digits decide which of the groups the release's own formatter wrote are long
enough to keep a separator. The port formats with the release, then walks the result from the back --
so a group of digits is known before the separator that follows it is written or taken off -- and keeps
a separator only for a group of at least the number asked for. With the host's own default of 1,
`1.234` keeps its separator; asking for 2 takes it off a three digit group.

The walk only ever **removes** a separator the release wrote; it never adds one, because a number the
release wrote without a separator has no group to decide about. A separator is recognised by the
whole groups of three after it, so the locale's own decimal separator (one digit after it) and a sign
(no digits before it) are copied as they are.

`tests/backports/host/foundationbatch` found three wrong rules here, one after another, and the
third is still open:

| what the walk did | what it wrote | the host writes |
| --- | --- | --- |
| a separator in front of every run | `1,,234` and `--1,-234.-5` at a minimum of 0 | `1,234` and `-1,234.5` |
| the run before the separator | `1,234` at a minimum of 2 | `1234` |
| UTF-16 units escaped instead of UTF-8 bytes (in the URL file, not this one) | — | — |

**Open: a seven digit number with a leading group of one digit.** The differential holds
`1234567` at five thresholds in three locales, and in nine of those the host keeps the whole of
`1,234,567` while the port takes the first separator off (`1234,567`), whatever the threshold. For
`1234` and `12345` the two agree at every threshold. So the host does not apply the minimum to the
leading group of a number that has more than one group after it, and no rule fitted to
`1234` and `1234567` at the same time was found before the round ended. Those nine checks are
**failing on purpose** rather than removed: the suite reads `checks=123 failures=9` and the shape of
every one of them is this.

## The context is kept and answered, and is not applied to the digits

The line direction contexts that move a negative sign arrived with iOS 26, and the release's own
number formatting has no such context: its enumerations are the capitalisation ones, which a number
does not use. A port that moved the sign would be writing something the release's formatter does not,
so the port keeps the value the application sets, answers it, and leaves the digits as the release
wrote them. That is the whole of what the property does on this release, and it is a divergence from
iOS 26 that is written down here rather than papered over.
