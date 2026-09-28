# PHASEEngine

Carried in `libAVFAudioBackports.dylib` (the `avfaudio` config), in `PHASEEngine15.m`. The largest
cluster in the PHASE corpus, and the class the rest of the framework hangs off.

PHASE arrived in iOS 15 and the port's releases are 6.1.3 and 4.3, so there is **no PHASE.framework on
either** and none of this is a translation of an engine that exists. What there is to carry is the
engine's state, and every value in it is either a documented default or the truth about a fresh
engine.

## The values, each with the header line that states it

| property | a fresh engine holds | where |
| --- | --- | --- |
| `unitsPerSecond` | 1 | `PHASEEngine.h:123` — "clamped to the range (0, inf]. Default value is 1." |
| `unitsPerMeter` | 1 | `:134` — the same sentence |
| `defaultReverbPreset` | `PHASEReverbPresetNone` | `:112` |
| `defaultMedium` | `PHASEMediumPresetAir` | `:104` |
| `renderingState` | `PHASERenderingStateStopped` | the enumeration's own zero (`PHASETypes.h`) |
| `outputSpatializationMode` | `PHASESpatializationModeAutomatic` | see below |
| `rootObject` | nil | a fresh engine has none |
| `activeGroupPreset` | nil | the header marks it nullable |
| `soundEvents` | `@[]` | a fresh engine has none |
| `groups` | `@{}` | a fresh engine has none |
| `duckers` | `@[]` | a fresh engine has none |
| `assetRegistry` | nil | see below |
| `lastRenderTime` | absent — see below | — |

`outputSpatializationMode` has **no documented numeric default**: the header says only that it
"overrides the default output spatializer and uses the specified one instead". The answer is the
enumeration's own zero, `PHASESpatializationModeAutomatic` — the mode whose name is "let the framework
choose", which is what a fresh engine that overrides nothing is doing. That is the enumeration's naming
rather than a number this port picked, and the facts file says so.

`unitsPerSecond` and `unitsPerMeter` are refused when set to a non-positive value, because the header
clamps to `(0, inf]` and the host's own clamp is what a caller has to live with; storing a value the
release would clamp would answer something the release does not.

## The three answers that are the empty set, and what they cost

`soundEvents`, `groups` and `duckers` answer empty, and `rootObject`, `activeGroupPreset` and
`assetRegistry` answer nil. That is the truth about a fresh engine, not a stub — an engine has none of
them until objects are added. But the **classes** they would hold are separate families of the corpus
this delivery does not carry: `PHASESoundEvent`, `PHASEGroup`, `PHASEDucker`, `PHASEObject`,
`PHASEMedium`, `PHASEAssetRegistry` and `PHASEGroupPreset`. So a caller that adds a sound event to
this engine cannot yet, and the properties are not lying about the emptiness — they are honest about
the engine and incomplete about the framework around it. `defaultMedium` is held as the preset rather
than as a `PHASEMedium` object, for the same reason: the value is right and the object is not there.

## `lastRenderTime` is `absent`

It is a render time, which is what the framework's **own render loop** reports. This port's engine is
not rendering — there is no PHASE.framework to render with, and no graph of the port's own is attached
— so there is no time to report. The row is `absent` with that reason, and its effect says the value
is zero, the value a stopped engine has. It is not `implemented`, because a hard-coded timestamp
would be the kind of invented value the brief is hardest about.

## The host differential

`tests/backports/host/phase/run.sh` holds the port's own renamed classes to the host's PHASE for the
**value** types. The engine is the next thing to add to it, and the properties that a host can settle
are the six documented defaults above; the six empty ones it confirms by reading them off a fresh
engine. The oracle is not yet extended to the engine, and this delivery does not claim it is.

## Reuse

**searched: none.** Nothing here is a filter bank, a convolution or a graph: the engine's state is six
documented doubles and enums, and the rendering is a unit's work. Resonance Audio and Steam Audio (both
Apache-2.0) are the two upstreams for the HRTF *spatialization*, which is the `PHASESpatialPipeline`
and `AVAudioEnvironmentNode` family and not this one. OpenAL Soft is LGPL and was not read.
