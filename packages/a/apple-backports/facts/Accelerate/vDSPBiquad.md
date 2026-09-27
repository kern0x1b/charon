# The multiple-biquad filter of vDSP, from iOS 7.0 to 16.0

Twenty entry points in five files, and every answer on this page is the host's own vDSP measured case by case by
`tests/backports/host/vdspbiquad` and recorded here: the port's five files and the host's `libvDSP` over the same inputs, comparing every
element either of them wrote. The release ladder is measured from the release's own armv7 caches, so each file holds the API of
exactly one release:

| file | rows | first release that exports them |
| --- | --- | --- |
| `Accelerate/vDSPBiquadm7.m` | 5 | iOS 7.0 (`_CreateSetup`, `_DestroySetup`, `vDSP_biquadm`, `_ResetState`, `_CopyState`) |
| `Accelerate/vDSPBiquadm8.m` | 5 | iOS 8.0 (the five in double) |
| `Accelerate/vDSPBiquadm9.m` | 5 | 10.3.4 (`_SetActiveFilters`, `_SetCoefficientsSingle`, `_SetCoefficientsDouble`, `_SetTargetsSingle`, `_SetTargetsDouble`) |
| `Accelerate/vDSPBiquadm16.m` | 5 | 16.0 (the same five in their 16.0 form) |
| `Accelerate/vDSPDFT7.m` | 4 | iOS 7.0 (`vDSP_DFT_zop_CreateSetupD`, `_zrop_CreateSetupD`, `_ExecuteD`, `_DestroySetupD`) |

vDSP.h publishes no layout for `struct vDSP_biquadm_SetupStruct` or its double twin, saying only that the contents may change from
release to release and that a caller should go through the setup and setter routines, so `Accelerate/CharonBiquad.h` defines both
and every caller only ever passes the pointer around.

## What the filter is

M sections over N channels, and the five numbers of a section are in the order **b0, b1, b2, a1, a2** - the order
`vDSP.h`'s own pseudocode uses - with the section the difference equation that pseudocode prints:
`y[n] = b0 x[n] + b1 x[n-1] + b2 x[n-2] - a1 y[n-1] - a2 y[n-2]`. Measured: the coefficients `{0.1, 0.2, 0.3, 0.4, 0.5}` over an
impulse answer 0.1, 0.16, 0.186, -0.1544, and `{1, 0, 0, 0.5, 0}` answer 1, -0.5, 0.25, -0.125 (the sign on a1 is the minus).

**The caller's coefficients are section-major and channel-minor**: the block for section `s` and channel `c` begins at
`(s * N + c) * 5`. Measured with one section and two channels over the coefficients 1..10: channel 0 has a b0 of 1 and channel 1 a
b0 of 6.

**The order of a cascade does not matter, and saying so is the measurement.** A cascade of linear time-invariant sections
commutes, and the release's own API gives nothing to tell the order apart with: putting the `a1` on section 0 or on section 1
gives `1 -0.5 0.25 -0.125 0.0625` both times, and walking this port's cascade in reverse leaves the whole differential at 74 checks
and 0 failures. The port walks section 0 first, which is one of the two orders that answer the same.

**The delay is two doubles per section and channel**, which is the section in transposed direct form II - the two-value form that
carries the last two samples' input and output history, and which a direct-form reading of the header's pseudocode would need four
values for. An impulse on channel 0 of a one-section two-channel setup leaves channel 1 silent, and silent on the next call too, so
the delay is per section *and* channel and not shared.

**IX and IY are element strides.** Measured: an impulse at index 1 of an input read with a stride of two comes out at index 1, and a
length of 0 leaves the output alone.

## The setters

**`SetActiveFilters` takes one bool per section**, not per section and channel: two sections of one channel answer 2 with both active
and 1 with the second inactive, from an array of two. An inactive section is skipped whole - its input passes through and its delay
is left as it was (measured: a two-section setup with the second inactive answers a constant input as the input itself, and answers
the fresh response of that section when it is made active again). **The two precisions differ on one case**: with *every* section of
a two-section setup inactive and the input 1, 2, 3, 4, `vDSP_biquadm` answers 1, 2, 3, 4 and `vDSP_biquadmD` answers 0, 0, 0, 0.

**`SetCoefficients` takes a window of its own**, packed `nsec` by `nchn` - the five values of its (section, channel) begin at
`(section * nchn + channel) * 5` - and places it in the setup at `(start_sec, start_chn)`. A window of one section and one channel
cannot decide that, because with `nsec = nchn = 1` the two candidate strides are the same expression; what decides it is a window
with `nsec >= 2` and a setup whose own `N` differs from the window's `nchn`. Measured on the host over a 2-section 4-channel setup
of pure gains, where a channel's answer is the product of its two b0s:

| window | the host's per-channel products | what it fixes |
| --- | --- | --- |
| `(nsec=2, nchn=4)` at `(0,0)` | 12 21 32 45 | blocks 0..7, the window's own `nchn` as the stride |
| `(1, 4)` at `(0,0)` | 2 3 4 5 | section 1 alone, four blocks |
| `(2, 1)` at `(0,0)` | 6 1 1 1 | blocks 0 and 1, the channels after it untouched |
| `(2, 3)` at `(0,0)` | 10 18 28 1 | six blocks, section 1 using 3, 4, 5 |
| `(2, 2)` at `(0,1)` | 1 8 15 1 | placed at `start_chn + c` |

All five and a sixth at `(1, 2)` go through both sides on the reviewer instrument and the port matches the host element for
element, so the code is right. **They are not in `tests/backports/host/vdspbiquad` yet**: the host's own
`vDSP_biquadm_DestroySetup` stops the process on the buffer shapes those cases need, so putting them in the suite needs a
setup whose destruction the host survives. Until then a change to the stride would not be caught by the suite, which is the
one thing about this pair the record should not leave open. The elements are read in the element type the
declaration names, in both the 9.0 pair and the 16.0 pair (measured: each of `SetCoefficientsSingleD` and `SetCoefficientsDoubleD` was
handed a float array of 9 and a double array of 9, and each of them read its own).

**`SetTargets` is where the two precisions part company, and the difference is in the record rather than in the code.**

- On a **single-precision** setup the coefficients approach their targets **one sample at a time**: the sample is filtered with the
  coefficient as it stands, and the coefficient then moves by `(target - coefficient) * (1 - interp_rate)` - the rate is the fraction
  of the distance *left*, not the fraction travelled - and lands exactly on the target when what is left is at most
  `interp_threshold`. Measured with a pure gain (a1 = 0) and a constant input, where the output at each sample *is* the coefficient
  that sample was filtered with, a b0 going from 1 to 9 with a threshold of 0.25 and

  | rate | the samples of one call of eight answer |
  | --- | --- |
  | 0.5 | 1, 5, 7, 8, 8.5, 9, 9, 9 |
  | 0.1 | 1, 8.2, 9, 9, 9, 9, 9, 9 |
  | 0.9 | 1, 1.8, 2.52, 3.168, 3.751, 4.276, ... |

  and the target is in place before the first sample - 9 in front of every sample - when the rate is 0, when the threshold is 0, or
  when the threshold is at or above the distance (measured: a rate of 0.5 with thresholds of 0 and of 100 over that same b0).
- On a **double-precision** setup the target is in place before the first sample **whatever** the rate and the threshold are: the
  same four parameter sets answer 9, 9, 9, 9 where the single-precision setup of the first two answers 1, 5, 7 and 1, 8.2, 9. So the
  `interp_rate` and `interp_threshold` of `vDSP_biquadm_SetTargetsSingleD` and `vDSP_biquadm_SetTargetsDoubleD` are recorded with the
  target and change no answer. That is a difference from the header's wording and the registry entries for those two functions say so.

**What is not right yet, and it is the one thing on this page a caller can hear: the walk above is the
*isolated* one, and a cascade of two or more sections walks differently.** Measured on this machine, over a
two-section setup whose sections go 2 -> 4 and 5 -> 10 with a rate of 0.5 and a threshold of 0.25, the host answers

```
10  22.5  30.625  35.1562  37.5391  40  40  40
```

where this port answers 10, 22.5, 30.625, **37.5**, **38.75**, 40, 40, 40. The first two sections' products fix what the host's
implied per-section b0 is: at the third sample 3.75 x 9.375 and at the fourth 3.875 x 9.6875, so the host's first section runs the
geometric walk 2, 3, 3.5, 3.75, 3.875, 4 where in isolation it runs 2, 3, 3.5, **4**, 4 - **inside a cascade the snap lands one
step later**, and it does the same for every threshold from 0.1 to 0.5 and every rate from 0.25 to 0.75. A two-section setup
whose two walks are identical (both 1 -> 9) agrees with this port, which is why the single-section cases here never saw it.

**The port therefore answers the isolated rule for every M, and for M >= 2 that is measurably not what the release answers** - 7%
high at the peak of the transition, which is an audible level bump in the middle of a filter change. This is stated rather than
papered over: the rule that governs the cascade is measured to *exist* and is not yet read off, and a guess at it would be a
second wrong answer on top of a known one. What is needed to read it off is a probe that leaves one section inactive with the
other present and reads that section's own b0 out of the answer; the two numbers above already pin it to "the isolated walk with the
snap deferred", and the sweep over thresholds in the review's probe would confirm or correct that.

`tests/backports/host/vdspbiquad` poses the two-section case beside the single-section ones and prints the
divergence as a documented deviation, so it is re-measured on every run rather than assumed.

A coefficient's target moves with it: `SetCoefficients` sets the target to the new coefficient, because a target is only elsewhere
once a `SetTargets` says so, and a single-precision setup walks its coefficients toward their targets at every sample.

## What the setup calls answer

`CreateSetup` answers NULL for no coefficients at all and for a count that would overflow, and a setup for everything else -
**no sections and no channels are not refusals**: the host answers a setup for both, and a call over `M = 0` passes the input
through unchanged (measured, 1, 2, 3, 4) while a call over `N = 0` writes nothing at all (measured, the output left as it was).

**Two cases the host cannot be asked about, and the port's own answers are what they are.** A NULL coefficient array reaches a
`memmove` inside the host's own `CreateSetup` and stops the process, so the port's NULL there is a refusal the differential cannot
compare. The same is true of `DestroySetup(NULL)`: the header does not declare that argument nullable and the host reads through it,
so the port takes it and does nothing - a difference in care rather than of behaviour, and one the differential records as the port's
answer alone.

## What has not been run

The device test for this group is `tests/backports/device/vdspbiquad.m`, and it has not been run: no device or emulator
call test has happened for Accelerate in this port at all. Every answer on this page is a host measurement and a device-unverified
one, which the port's own contract accepts as a floor and not as the bar.
