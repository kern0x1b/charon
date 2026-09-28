# PHASE's spatial-audio value types

Carried in `libAVFAudioBackports.dylib` (the `avfaudio` config), in `PHASEValueTypes15.m`:
`PHASENumericPair`, `PHASEDistanceModelParameters`, `PHASEDistanceModelFadeOutParameters`,
`PHASEGeometricSpreadingDistanceModelParameters`, `PHASECardioidDirectivityModelSubbandParameters`,
`PHASEConeDirectivityModelSubbandParameters`, `PHASECardioidDirectivityModelParameters` and
`PHASEConeDirectivityModelParameters`.

PHASE arrived in iOS 15 and the port's releases are 6.1.3 and 4.3, so there is no PHASE.framework
on any of them and none of this is a translation of a unit that exists. What there is to implement is
the value types: a set of doubles with documented defaults, one initializer with a stated precondition,
and one gain law.

## The values are the header's

- `PHASENumericPair.first` and `.second` — *"The default value is 0.0"*, for both, which is what
  `-initWithFirstValue:secondValue:` and the accessors hold.
- `PHASEDistanceModelFadeOutParameters.cullDistance` — one double, given to the initializer, read
  back.
- `PHASEGeometricSpreadingDistanceModelParameters.rolloffFactor` — **the header names no default**,
  so none is invented: the ivar's own zero stands until a caller sets it, and the gain law below says
  what a zero exponent means rather than leaving it ambiguous.
- `PHASEConeDirectivityModelSubbandParameters.innerAngle` and `.outerAngle` — *"The default value for
  each angle is 360.0"*, both of them, which is what `-init` leaves behind.
- `setInnerAngle:outerAngle:` — the header's one precondition, *"outerAngle must be >= innerAngle"*,
  is enforced: a call that breaks it leaves the pair unchanged, because an inner angle outside the
  outer one describes no cone.
- `PHASECardioidDirectivityModelSubbandParameters` — `frequency`, `pattern`, `sharpness`, each
  defaulting to the header's 0.0.

## The one gain law

`-charon_gainAtDistance:` on the geometric spreading model is `1 / distance^rolloffFactor`, and that
is the whole of what a geometric spreading model computes. A rolloff of zero — the state a never-set
parameter is in — gives a gain of one, which is what that exponent means and not a special case
written to paper over the missing default.

## Two things the header forced, and neither is a shortcut

`PHASEDirectivityModelParameters` marks `-init` and `+new` `NS_UNAVAILABLE`
(`PHASEDirectivityModel.h:121`) and its two subclasses declare `-initWithSubbandParameters:`, so
`[super init]` is a hard error in those initializers. The subclasses therefore allocate with
`[<their own class> alloc]` and set their own state, which is all `-init` would have done and all
there is to do: they inherit no state from the superclass.

`PHASEGeometricSpreadingDistanceModelParameters` inherits that same unavailable `-init`, so no
initialiser is written for it either — the property's own zero is its state, which is what the header's
silence on the default means.

## The host differential

`tests/backports/host/phase/run.sh` asks the host's own PHASE.framework the same questions: a
`PHASENumericPair` at (2.5, −3.25) and its first value settable to 7.0, a
`PHASEDistanceModelFadeOutParameters` at a cull distance of 42.5, a
`PHASEGeometricSpreadingDistanceModelParameters` at a rolloff factor of 1.0, and the geometric
spreading law at 4 m. It reports `checks=6 failures=0` and the host does carry both subband classes.

The port side of the same comparison is not yet written; the oracle is, so the differential is possible
rather than claimed. Each class is reached by name and read by key, so a class the host does not carry
is reported and skipped rather than failing the build, and the run fails outright if the host has no
PHASE at all — nothing there passes vacuously.

## Reuse

**searched: none, and here is what was looked for.** The brief names Resonance Audio and Steam Audio,
both Apache-2.0, for HRTF and attenuation. This family needs neither: everything it computes is a set
of doubles with documented defaults, one initializer with a stated precondition, and
`1 / distance^rolloff`. There is no filter bank, no convolution and no graph to vendor, and taking a
DSP library to produce a value the header states would be the wrong size of answer. The queries were
`PHASEEnvelope`, `PHASEDirectivityModel`, `geometric spreading rolloff` and `cardioid directivity
subband` on GitHub repository search. OpenAL Soft is LGPL and was not read.

When the HRTF work proper comes — a `PHASESpatialPipeline` and an `AVAudioEnvironmentNode` with a
head-related transfer function — the search is repeated, and Resonance Audio's HRTF filter bank and
Steam Audio's are the two upstreams to measure. That is a different family from this one.
