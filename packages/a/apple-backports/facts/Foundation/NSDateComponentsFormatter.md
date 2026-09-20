# NSDateComponentsFormatter, iOS 8

Introduced in iOS 8: a formatter that writes a span of time as text - "1h 2m 5s", "about 5 days remaining",
"one hour, two minutes" - in five styles (positional, abbreviated, short, full, spelled out).

Source: the host's own Foundation, asked for every answer and held against the port by two runs. The `datecomponentsformatter`
group of `tests/backports/host/uikit2/run.sh` compiles the port with its names changed and puts it beside the system's
class, and compares 3000 random configurations at twelve intervals each. `tests/backports/host/datecomponents` records
the system's answers for a fixed set of cases into `device/datecomponents-expectations.h`, and `device/datecomponents.m`
compares the port to them on the device. The shared caches of iOS 6.0 and 7.0 have no such class.

## What the port does as the system does

The units it may show are years, months, weeks of the month, days, hours, minutes and seconds; any other unit raises
`NSInternalInconsistencyException` with the system's reason, a time interval that is not a number raises
`NSInternalInconsistencyException`, and empty components answer `nil`. A negative span is written as its magnitude with the
sign on the first unit shown, and by the number formatter, so a spelled-out one reads "minus one hour". Positional
units must be contiguous or the system's `NSInvalidArgumentException` is raised. The zero-formatting bits drop leading,
middle and trailing zeros or pad, and the default drops all of them (leading ones only for a positional style).
The maximum unit count keeps the largest units and rounds the remainder into the last one kept, with the carry into the
next larger allowed unit; the largest unit collapses into the next one when that is below a tenth or above nine tenths
of it, for month to day, day to hour, hour to minute and minute to second. The approximation and time-remaining
phrases, fractional units and the calendar and reference date are honoured. Numbers go through the number formatter of
the current locale.

## What it cannot do

The words are English. The system has its own table of unit names for every language it ships; the port carries none,
so a device in another language reads the same English words with that language's digits. `formattingContext` is kept
and not acted on.

Rare combinations differ: with negative spans, with weeks together with years or months, and with a collapse that
meets a year or a week, the system's own answer follows from its calendar arithmetic and the port's is the nearest
whole reading. The random comparison measures 3.6% of 36000 answers differing.
