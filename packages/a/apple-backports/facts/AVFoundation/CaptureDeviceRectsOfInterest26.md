# The rectangles of interest of iOS 26: 8 rows, one object, real geometry

`AVFoundation/AVCaptureDeviceRectsOfInterest26.m` carries all eight - six properties on `AVCaptureDevice` and
the two `-defaultRectFor...PointOfInterest:` methods. Registry: `registry/AVFoundation/rectsofinterest26.json`,
eight rows, one per row the `coordination/corpus/ledger-2026-10-03/AVFoundation.tsv` snapshot reads `missing`
for them at 26.0 (`$4=="26.0" && $6=="missing"`). Header: `CharonAVCaptureDeviceRectsOfInterest26.h`,
transcribed from the SDK 26.2 (`AVCaptureDevice.h:1159-1187` and `:1403-1429`) because SDK 16.4 declares none
of it - and, unlike the two slices below it in the same folder, **no type at all**, because CGPoint, CGSize,
CGRect and BOOL are CoreGraphics' own and Foundation's.

## Why it is geometry and not four answers

26.0's header says exactly what a rectangle of interest does: "Setting `focusRectOfInterest` updates the
device's `focusPointOfInterest` to the center of your provided rectangle of interest" (`:1171`, and `:1415`
for the exposure). **The release this port runs on has that point of interest and nothing else.** Measured with
`tools/corpus/objc-inventory.lua` over `~/.charon/dyld/6.1.3/dyld_shared_cache_armv7`, `AVCaptureDevice` owns:

```
focusPointOfInterest                instance      isFocusPointOfInterestSupported        instance
setFocusPointOfInterest:            instance      exposurePointOfInterest                instance
setExposurePointOfInterest:         instance      isExposurePointOfInterestSupported     instance
lockForConfiguration:               instance      unlockForConfiguration                 instance
```

and it owns **none** of the eight members here - and none at 16.0 arm64e or 18.0 arm64e either, the same three
caches read for the 18.0 slice. So:

- **the two support flags are the release's own point-of-interest answers.** Not a constant: a device whose
  focus cannot be pointed at cannot be given a rectangle, because the rectangle's whole effect is the point.
- **the two rectangles are the release's own point plus an extent**, kept per device, and the getter
  reconciles them (below).
- **the two setters refuse in the order Apple's own refuses** and then apply the centre through the release's
  own `-setFocusPointOfInterest:`.
- **the two minimum sizes are `{ 0, 0 }`**, derived - see "The one value with no source on this release" below.
- **the two default-rectangle methods** answer the degenerate rectangle at the point asked for, or CGRectNull
  where the device does not support the rectangle, which is what the header says this method returns in that
  case (`:1184`, `:1429`) and what the host answers (measured: `CGRectIsNull` 1 for every point asked).

### The reset, and how a category can see it

The header's rule: "If you later set the device's `focusPointOfInterest`, the `focusRectOfInterest` resets to
the default sized rectangle of interest for the new focus point of interest. If you change your
`AVCaptureDevice/activeFormat`, the point of interest and rectangle of interest both revert to their default
values." (`:1171`)

The release's own point setter cannot be wrapped from a category, and it must not be replaced: it is Apple's
method on Apple's class, in every band from 18.0 up. So the **getter reconciles instead** - a stored rectangle
whose centre is no longer the release's own point of interest is one that setter has moved past, and the
answer is then the default rectangle for the point that is current. The second half of the rule needs nothing:
the release reverts its own point, and the reconciliation follows it. `tests/backports/host/avf-capabilities`
asks this as a step of its own - set a rectangle, set the point directly, read the rectangle again - and the
plant `rectreset` removes the reconciliation and is noticed.

## The oracle is this Mac's own AVFoundation, and it is on the unsupported side

`tests/backports/host/avf-capabilities` asks both sides in one process. This Mac's camera supports **neither**
a point of interest nor a rectangle, so its column is the header's own documented answer for a device that
does not: measured, `isFocusRectOfInterestSupported` 0, `isExposureRectOfInterestSupported` 0,
`isFocusPointOfInterestSupported` 0, `isExposurePointOfInterestSupported` 0, both minimum sizes `{ 0, 0 }`,
every rectangle and every default rectangle `CGRectNull`.

That is a real column and not a weak one, because it fixes the two refusal strings and **the order of the three
refusals**, which the port could not otherwise know:

| case | the host answers |
| --- | --- |
| `setFocusRectOfInterest:` unlocked, on a device that does not support the rectangle | `NSGenericException: *** -[AVCaptureDevice_Tundra setFocusRectOfInterest:] May not be called without first successfully gaining exclusive ownership of the device using -lockForConfiguration:` |
| `setFocusRectOfInterest:` locked, unsupported | `NSInvalidArgumentException: *** -[AVCaptureDevice_Tundra setFocusRectOfInterest:] Not supported - use -isFocusRectOfInterestSupported` |
| `setExposureRectOfInterest:` locked, unsupported | the same, naming `-setExposureRectOfInterest:` and `-isExposureRectOfInterestSupported` |

**The lock is checked first**, which is measurable only because the host's device is unsupported: an unlocked
write raises `NSGenericException` even though the support flag is 0, so Apple's order is lock, then support,
then size, and the port implements that order. The class in Apple's string is `AVCaptureDALDevice_Tundra`, a
private class of Apple's device-access layer; the port names `AVCaptureDevice`, the class it has and the one the
header declares the member on, and says so on every row that raises.

The port's column is the geometry over the release's own substrate, which the harness models: the stand-in
device carries the members 6.1.3 owns, with the two refusals the SDK 16.4 header states for them
(`AVCaptureDevice.h:1083` and `:1269`) and nothing else. The support flag is what the harness sets, so **both
branches of the port's rule are asked**: supported (the whole phase) and unsupported (the last two steps, where
the port answers `CGRectNull` and refuses, exactly as the host does).

| row or step | host | port |
| --- | --- | --- |
| `focusRectOfInterestSupported`, `exposureRectOfInterestSupported` | 0 | 1 (the stand-in's substrate supports a point) |
| `minFocusRectOfInterestSize`, `minExposureRectOfInterestSize` | `0 0` | `0 0` |
| `focusRectOfInterest`, `exposureRectOfInterest`, unset | CGRectNull | `0.5 0.5 0 0` (the release's own point, the header's default) |
| `defaultRectFor{Focus,Exposure}PointOfInterest:` (0.5, 0.5) | CGRectNull | `0.5 0.5 0 0` |
| `defaultRectFor{Focus,Exposure}PointOfInterest:` (0.75, 0.75) | CGRectNull | `0.75 0.75 0 0` |
| `setFocusRectOfInterest:` a quarter by a quarter, unlocked | NSGenericException | NSGenericException, the port's own text |
| `setFocusRectOfInterest:` a quarter by a quarter, locked | NSInvalidArgumentException (unsupported) | accepted; the point answers `[0.125 0.125]` |
| `setFocusRectOfInterest:` a negative extent, locked | NSInvalidArgumentException (unsupported) | NSInvalidArgumentException (the size check) |
| `setExposureRectOfInterest:` half by half, locked | NSInvalidArgumentException (unsupported) | accepted; the point answers `[0.5 0.5]` |
| `setFocusPointOfInterest:` after a rectangle | NSInvalidArgumentException (unsupported) | accepted; the rectangle answers `0.1 0.9 0 0` |
| `focusRectOfInterest`, points unsupported | CGRectNull | CGRectNull |
| `setFocusRectOfInterest:` the whole field of view, unsupported | NSInvalidArgumentException | NSInvalidArgumentException |

Two centres worth naming: the centre of `(0, 0, 0.25, 0.25)` is `(0.125, 0.125)`, and the centre of
`(0.25, 0.25, 0.5, 0.5)` is `(0.5, 0.5)`. Neither is written into the port; both are `CGRectGetMidX` and
`CGRectGetMidY` of what the caller passed.

## The one value with no source on this release

**Both minimum sizes are `{ 0, 0 }`, and that is a derivation rather than a number taken from anywhere.**
"the size returned is in normalized coordinates, and depends on the current `AVCaptureDevice/activeFormat`. If
`focusRectOfInterestSupported` returns `false`, this property returns `{ 0, 0 }`" (`:1166`). Apple's number is
the smallest area the sensor's focus machinery can weigh, which it measures in the active format's **sensor
pixels** and normalizes. The release has no such quantity anywhere: its camera device carries a point of
interest, a format description and a configuration lock, and no focus area, no metering area and no sensor
size. So the smallest rectangle that still names a point is the degenerate rectangle, which is `{ 0, 0 }` - and
which is also what the header documents for a device that does not support the rectangle at all.

Two consequences, both stated rather than left for a reader:

1. **The extent of a rectangle of interest carries nothing on this port.** The rectangle is honoured through its
   centre, exactly as the header describes, and its size is bookkeeping the port keeps and hands back. An
   application that sets a small rectangle and expects the hardware to weigh only that area gets the whole
   field of view weighted at the rectangle's centre, which is the only thing the release can do.
2. **The size check in the setter can refuse a rectangle with a negative extent and nothing else.** The check
   is the header's own rule and it is live - the harness asks a negative extent and the port refuses - but it
   refuses nothing else, and the plant `rects` (a minimum of a quarter by a quarter, a number no measurement on
   this release gives) turns that accepted case into a refusal and is noticed.

## The host was measured before the port was written, and what that risks

For the two slices above it in the same family the port's answers were derived from the header and the
release's substrate first and the host was asked afterwards. **For this family the host was measured first**,
because its two refusal strings and the order of its three refusals cannot be derived from anything else and
are worth more than the order of the questions. What that risks is a port answer fitted to a host answer, and
the two places it could have happened are both closed: the support flags and the geometry come from the
release's own members and from `CGRectGetMidX`/`CGRectGetMidY` of the caller's own rectangle, and the port's
column differs from the host's in every row where the two differ.

## Checks

```
sh tests/backports/host/avf-capabilities/run.sh        exit 0
  ok  31 members are answered by both sides
  ok  55 answers are the ones expectations.tsv names, the host's and the port's columns both
  ok  8 preferred-camera steps are the ones the header's four rules give, computed here from the fixture each step used
AVFCAPSMUTANT=rects      ok  the mutation was noticed: 1 of 55 table answers
AVFCAPSMUTANT=rectreset  ok  the mutation was noticed: 1 of 55 table answers
CONTROL=1 with each of the six plants  ok  the control is clean
```

Six plants now, and all six are noticed: `reactions` (1 of 55), `prefcam` (6 of the 8 preferred-camera steps),
`capabilities` (3 of 55), `multichannel` (4 of 55), `rects` (1 of 55), `rectreset` (1 of 55).

### What the extension cost in probe bugs, and one that is worth naming

Two of the three were the kind that a run does not notice:

- **`printf` has no `%@`.** The first version of the rectangle phase printed its two row names through one
  format with a `%@` in it, so `printf` took the **next** argument as the object - the double `0.5` - and
  `strlen` walked its bit pattern: the probe died at `0x3fe0000000000000`, which is `0.5`. The names are now
  two literal formats.
- **A `CGPoint` is not a `CGRect`.** The reset step reused the rectangle writer with a point as its argument.
  It has its own case now, with the reason in the code beside it.
- `-[AVCaptureDALDevice lockForConfiguration]` does not exist: the release's lock takes an `NSError **`, and the
  stand-in's own lock does not. The two are now sent as the two different calls they are.

## Not carried, and one measurement nobody has taken here

- **`AVCaptureDevice.centerStageRectOfInterest`** is a 16.4 row the ledger reads `decided`, so it is not this
  family's.
- **What the release's own `isFocusPointOfInterestSupported` answers on an iPhone 4S or an iPad 2 running
  6.1.3 is not measured.** The port asks the release's member, so the row is right on whatever it answers, and
  the harness asks both branches of the rule with a stand-in - but which branch a real device of this port takes
  is a device measurement (`tests/backports/device/avcapture.m` is where it would go) that this session did not
  run. A device without that answer: an emulator slot, and the coordinator's call.