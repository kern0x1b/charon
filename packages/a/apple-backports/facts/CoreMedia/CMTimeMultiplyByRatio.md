# `CMTimeMultiplyByRatio` on a release that has no `CMTimeMultiplyByRatio`

iOS 6 has 66 `CMTime` and `CMTimeRange` functions, and `CMTimeMultiplyByRatio` is not one of
them: it first appears at 7.1 (`coordination/corpus/caches/7.0.1.tsv`, 67 functions, against 66
at 6.0). What iOS 6 does carry is enough to hold the answer, because a `CMTime` is a
`(value, timescale, epoch, flags)` quadruple and the arithmetic is on those fields.

## What the port does

`(time * multiplier) / divisor`, as an exact rational, kept whenever a `CMTime` can hold it:

1. An invalid time, an indefinite time, and an infinity are answered as themselves. An infinity
   multiplied by zero is `kCMTimeInvalid`, and its sign follows the multiplier and the divisor
   together. Every answer carries `kCMTimeFlags_HasBeenRounded`, which is what the host does.
2. A zero multiplier, and a zero value at epoch 0, give zero at the *input* timescale, not at 1.
3. A zero divisor gives `kCMTimeInvalid` when the multiplier or the value (at epoch 0) is zero,
   and otherwise an infinity of the sign of `multiplier * divisor`, or - when the time carries a
   non-zero epoch, so it is not the zero the sign test sees - of the sign of the multiplier alone.
4. Otherwise the multiplier and the divisor are reduced by their greatest common divisor, the
   divisor is made positive, and the answer is `value * multiplier` at `timescale * divisor`. The
   fraction is **not** reduced any further: `CMTimeMultiplyByRatio(CMTimeMake(1, 3), 3, 1)` is
   `3/3`, and `CMTimeMultiplyByRatio(CMTimeMake(1, 2147483647), 2147483647, 1)` is
   `2147483647/2147483647`. This is measured, not inferred (see the grid below).
5. Where the value does not fit an `int64`, or the denominator is not a legal `CMTimeScale`, the
   answer is the exact value at the timescale chosen for it, rounded half away from zero, with
   `kCMTimeFlags_HasBeenRounded` set; and an infinity when even that does not fit.

The 96-bit helpers exist because armv7 has no `__int128`, and the exact rational needs the
product of a 64-bit value and a 32-bit multiplier.

## The claim, and what was measured against it

`tests/backports/host/coremedia7` runs the port's function and the host's own side by side over a
grid of 22 values (0, +-1, +-2, +-3, 5, 7, -7, 10, 100, 1000, 48000, -48000, 1000000007,
-1000000007, 2147483647, -2147483648, 4294967296, 600000000000, 123456789012345) x 27 timescales
(1, 2, 3, 4, 5, 6, 7, 10, 24, 25, 30, 48, 60, 100, 300, 441, 480, 600, 1000, 30000, 44100, 48000,
90000, 100000000, 1000000000, 1073741824, 2147483647) x 20 multipliers x 20 divisors, each also
with `kCMTimeFlags_HasBeenRounded` set, with a non-zero epoch, and for the five special times.

- **673 871 answers are the same**, including every degenerate rule above.
- **0 differ where a `CMTime` can hold the exact rational.** That is the claim the registry entry
  makes, and the test fails if one ever does.
- 40 929 fall outside the claim, where no `CMTime` holds the exact rational: the value overflows
  64 bits, or `timescale * divisor` is not a legal `CMTimeScale` (a reduced divisor of 2147483648,
  or a product above `INT32_MAX`). There the port answers the exact value at 1000000000 and the
  host answers its own; 29 214 of the 40 929 are within a microsecond of each other.

## Where the host leaves the documentation, and the port does not

In that corner Apple's implementation truncates the *value* against the input timescale before it
multiplies, so it loses the answer entirely for a value smaller than its own timescale. Measured
on the host:

| input | exact | host | port |
| --- | --- | --- | --- |
| `-1/2147483647 * 65536 / 3` | -1.0173e-5 s | `0/1000000000` | `-10173/1000000000` |
| `123456789012345/2147483647 * -44100 / 30000` | -84508.8996 s | `-84508899567956/1000000000` | `-338035598271817/1000000000` |
| `9223372036854775807/3 * 1 / 1` | 3074457345618258602.33 s | `3074457345618258602/1` | `9223372036854775807/3` |
| `4611686018427387903/1 * 3 / 2` | 6917529027641081854.5 s | `6917529027641081855/1` | `6917529027641081854/2` |

The last two are the documented rule read the other way round: the documentation says the exact
rational is preserved "if possible without overflow" and that otherwise "a new timescale will be
chosen so as to minimize the rounding error" - the exact rational is the representation with no
rounding error at all, so keeping it is the choice that minimises the error. The port keeps it.
The first two are the host losing the value; there is no representation of them that is both
exact and a `CMTime`, and the port answers the value the input describes.

A CMTime value of exactly `INT64_MIN` or `INT64_MAX` is never answered by the host: it reports the
infinity of the sign instead. The port reports the infinity too, for both bounds, which is why the
domain test in the implementation rejects a magnitude of `2^63 - 1` as well as `2^63`.

## The source

The host's own CoreMedia (`xcrun clang` against `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`,
macOS 27.0), which the port is held against case by case by the test above. iOS 6.0's exports were
read from `coordination/corpus/caches/6.0.tsv`, the symbol table of the iOS 6 armv7 shared cache.
