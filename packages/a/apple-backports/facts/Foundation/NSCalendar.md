# NSCalendar, the units of iOS 8

Source: the host's own Foundation, through the differential run of
`tests/backports/host/foundation2/run.sh`, which holds the backport and the system to the same 12702
answers; the identifiers were read from the system's own constants.

## The quarter

`NSCalendarIdentifierGregorian` is the string `gregorian` and `NSCalendarIdentifierISO8601` is
`iso8601`; the deprecated `NSGregorianCalendar` carries the same `gregorian`. The backport compares the
calendar's identifier with those strings rather than with the constants, which a release older than
iOS 4.0 does not export at all: a comparison against a null constant answers no for every calendar, and
the quarter would be silently zero everywhere.

A quarter is computed only for those two calendars, as `(month - 1) / 3 + 1`. For any other calendar the
answer is zero, which is what Foundation itself answers - the differential run holds the two side by side
on the Hebrew calendar and both say zero. Zero is not the undefined value of a date component, and that
difference is Apple's, not ours.

## The nanosecond

A date carries its time as a double of seconds, so the nanosecond is read back from the fraction and
rounded, and it is capped at 999999999 so that a rounded fraction never reads as a whole second. Around
2026 a double holds about 240 nanoseconds of resolution, so the low digits of the answer are not the ones
a release with a nanosecond field of its own would give.
