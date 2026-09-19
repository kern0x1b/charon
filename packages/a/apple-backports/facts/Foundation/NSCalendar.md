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

## Setting a time the clock skips

Europe/Berlin moves its clocks forward on 29 March 2026, so 02:30 does not happen that day. The system
answers `-dateBySettingHour:minute:second:ofDate:options:` for 02:30 of that day with **03:00**, the instant
the clock jumps to, and the same for `NSCalendarMatchNextTime`; with `NSCalendarMatchStrictly` it answers
**02:30 of the next day**, the first day the time exists again. The start of that day is 00:00 as on any
other day.

The backport used to set the components and hand back whatever the calendar made of them, which is 03:30 -
the requested minutes carried into the shifted hour - for all three options. It now checks that the time it
reached is the time it asked for, and, when it is not, answers the daylight saving transition of that day,
or, for a strict match, walks the following days until the time exists.

Checked against the host across five zones with real daylight saving rules - New York, Moscow, Lord Howe
Island, São Paulo, Apia - every hour from January 2020 to October 2024, setting every third hour of the day
(00:30, 03:30, 06:30, ..., 21:30) on each: 1666680 answers, none of them different from the host's. The
device test holds iOS 6 to five of them, the half hours from 00:30 to 04:30 the day before New York's
spring transition of 2023, which answer the instants themselves, including the jump at 02:30 to 03:00.

## Granularity

`-isDate:equalToDate:toUnitGranularity:` and `-compareDate:toDate:toUnitGranularity:` were measured against
the system for noon and eight in the evening of one day: equal to the day, not equal to the hour, and **not
equal to a mask of both**, which behaves as the finer of the two. A unit that names no field of a date -
`NSCalendarUnitCalendar`, `NSCalendarUnitTimeZone` - answers equal and orders the same, since there is
nothing to tell the two dates apart by. The backport answers each of those as the system does.

## A calendar whose months repeat

`NSCalendarIdentifierChinese`, `Dangi`, `Gujarati`, `Kannada`, `Marathi`, `Telugu`, `Vietnamese` and
`Vikram` number a leap month the same as the month it follows, so two dates can carry the same era, year
and month and still fall in different months - one in the ordinary one, one in its leap repeat. Read from
swift-foundation's own `Calendar.compare(_:to:toGranularity:)`: when the numeric fields it has already
compared are equal and the granularity has reached the month, a date whose month is not the leap one orders
before one whose month is; the Hebrew calendar's own leap month, Adar I, is a month of its own number and
is not in this list, and needs no such tie-break. Checked against the host's own Foundation on Chinese: of
every pair of dates within 900000000 - 600000000 seconds of the reference date that share an era, year and
month and differ only in the leap flag - 9880 comparisons at 13 granularities - the backport orders none of
them differently. The device test holds iOS 6 to one such pair, a date in an ordinary seventh month and one
29 days later in that month's leap repeat, at seven granularities from the quarter to the week of the
month: the ordinary one compares before the leap one, and the two are not equal.

## Weekends

`-nextWeekendStartDate:interval:options:afterDate:` follows the locale, not the calendar: from that Sunday
an `en_US_POSIX` calendar answers the following Saturday at 00:00 with an interval of 48 hours, and a
`he_IL` one answers the Friday before it, also 48 hours. The weekend of a locale comes from ICU, which the
release carries as `libicucore`; where that library does not answer, `-isDateInWeekend:` says no and the
library says so once in the log.
