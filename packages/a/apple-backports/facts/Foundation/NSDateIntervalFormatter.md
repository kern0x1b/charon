# NSDateIntervalFormatter, iOS 8.0

The class arrived in iOS 8.0 and the port carries it from **5.0**, and the class is the release's own
`DateIntervalFormat` underneath: the port calls `udtitvfmt_open`, `udtitvfmt_format`,
`udtitvfmt_setAttribute` and `udtitvfmt_close`, the four entry points of ICU's date-interval formatter,
the way the release's own class calls them.

## Why 5.0 and not 6.0, and not 4.3

Measured on the armv7 caches, `_udtitvfmt_*` in `/usr/lib/libicucore.dylib`:

| release | libicucore exports | `_udtitvfmt_*` |
| --- | --- | --- |
| **4.3** | 4727 | **0** |
| 5.0 | 5187 | 4 |
| 6.0 | 5311 | 4 |
| 6.1.3 | 5311 | 4 |
| 7.0 | 5459 | 4 |
| 8.0 | 6195 | 4 |
| 9.0 | 6472 | 4 |
| 10.0.1 | 6710 | 4 |

The four are `udtitvfmt_open`, `udtitvfmt_format`, `udtitvfmt_setAttribute` and `udtitvfmt_close`.
6.1.3 links `icudt49_dat`, so its `udtitvfmt_open` is **ICU 49's** six-argument form, with a
`const char *locale` first, then the skeleton as `UChar` and its length, then the zone the same way,
then the status. That is the signature the port calls; the four symbols are imported weakly and the
gate places them at 5.0.

**4.3 does not carry the class**, and the reason is that table: its `libicucore` exports no
`udtitvfmt_*`. A 4.3 path would mean vendoring ICU into the package, which is a later item and not
this one.

## What comes from the release and what comes from the port

From the **release**, which is the point of the route: the join between a date and a time and
between the two ends of a range, the collapse of a shared day, the way each style pairs its fields,
and every locale's own choice of all of it. The header's own examples need nothing reproduced — the
release's `DateIntervalFormat` produces them, `MMMd` giving "Mar 4" in en_US and "4 Mar" in en_GB for a
range inside one day, and `jm` giving "7:56 AM - 7:56 PM" against "7:56 - 19:56".

From the **port**: the six properties, the two methods, the two styles and the template turned into
one **skeleton** for the release, and the two defaults the header states wrongly. The header says both
styles are `NSDateIntervalFormatterNoStyle` and the template is the empty string; the host reads **both
styles back as the short style** and the template as empty, and the port does the same, which is why
the golden file's NoStyle rows are empty and its first real row is the short one.

The skeleton of a style pair is the date skeleton and the time skeleton joined, the date's fields
first and each field letter once:

| style | date | time |
| --- | --- | --- |
| short | `yMd` | `jm` |
| medium | `yMMMd` | `jmms` |
| long | `yMMMMd` | `jmmsz` |
| full | `yMMMMdE` | `jmmszzzz` |

A `dateTemplate` names the skeleton instead, which is what the release's
`+[NSDateFormatter dateFormatFromTemplate:options:locale:]` would expand and what its interval
formatter expects. The four symbols are asked weakly: a release without them answers nil rather than
faulting, and 4.3 is below the floor anyway.

## device-unverified

**This path is not held by a macOS differential and none is claimed.** The host's own `libicucore`
refuses the call the port makes — `udtitvfmt_open` answers a handle and
`U_ILLEGAL_ARGUMENT_ERROR` (-128) for every skeleton, zone and locale tried, and the seven- and
three-argument forms segfault — so the host's `NSDateIntervalFormatter` and the port's call do not meet
anywhere on this machine. That is not a defect in the port: the release's ICU 49 is what the port runs
on, and the host's is a different build.

What holds it instead is a **golden file** and a device run:

- `tests/backports/device/dateinterval/make-expected.m` writes the host's own
  `NSDateIntervalFormatter` over **fifteen locales** x the **twenty-five pairs** of the five styles x
  **three zones** (UTC, America/New_York, Europe/Warsaw) x **three date pairs** (an hour inside one
  day, across midnight, into the next year) into
  `tests/backports/device/dateinterval/expected.txt` — **3375 cases**, one line each, tab-separated, in
  a fixed order so a diff means something;
- `tests/backports/device/dateinterval.m` runs the port on the device, asks each case, and compares
  line by line, printing the first twenty that differ and then the count. It also checks that
  `-stringFromDateInterval:` and `-stringFromDate:toDate:` agree, and says whether the class it got
  is the port's or the release's.

**That run has not happened.** Until it does, the registry's `source` for every row of this class
says `device-unverified`, and so does the commit that carries it.
