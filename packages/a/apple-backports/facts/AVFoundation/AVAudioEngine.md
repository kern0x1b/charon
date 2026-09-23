# AVAudioEngine, AVAudioPlayerNode, AVAudioUnitEQ, AVAudioConverter - the node graph

**`AVAudioEngine` and `AVAudioPlayerNode` are built and measured: a real signal passes through
the graph, sample-for-sample.** `AVAudioUnitEQ`/`AVAudioConverter` are next (their audio
components are already confirmed present, below).

None of the four classes exist on iOS 6.0/6.1.3 (confirmed via `objc.inventory` against the real
armv7 shared cache before any code was written - no name collision the way `AVAudioBuffer` was,
see `facts/AVFoundation/AVFAudio.md`). What they sit on is real and complete, measured on-device,
not assumed from a header:

- Every AUGraph/AudioUnit/AudioConverterServices C entry point this port needs -
  `NewAUGraph`, `AUGraph{Open,Initialize,Start,Stop,AddNode,NodeInfo,ConnectNodeInput,
  DisconnectNodeInput,RemoveNode,Update,Close}`, `AudioComponent{FindNext,InstanceNew}`,
  `AudioUnit{SetProperty,GetProperty,Initialize,Render,AddRenderNotify}`,
  `AudioConverter{New,ConvertComplexBuffer,FillComplexBuffer,Get/SetProperty}` - resolves via
  `dlsym` in a running armv7 process on the 6.1.3 guest. A symbol resolving is not the same claim
  as a component being registered, so this was checked separately.
- The specific Audio Components this port's four classes need are each confirmed registered
  through `AudioComponentFindNext`, not just linkable: `kAudioUnitSubType_GenericOutput`
  (`auou`/`genr`/`appl`), `kAudioUnitSubType_RemoteIO` (`auou`/`rioc`/`appl`),
  `kAudioUnitSubType_NBandEQ` (`aufx`/`nbeq`/`appl`), `kAudioUnitSubType_MultiChannelMixer`
  (`aumx`/`mcmx`/`appl`) - all four found, `AudioComponentGetDescription` reading back the exact
  type/subtype/manufacturer requested, `OSStatus 0` throughout.

## The verification scheme this unlocks

The coordinator's standing warning for this cluster: a graph that compiles, runs and produces
silence reports nothing - no exception, no error code, a green gate. The only real proof is
reading the graph's actual output and comparing samples, the way `tests/backports/device/avfaudio.m`
already does for a bare buffer.

`AVAudioSession` needs a live `mediaserverd`, which the Shade emulator does not run at all
(measured: every `AVAudioSession` call there fails identically with `kAudioSessionNotInitialized`,
`'!ini'`, both as a bare daemon and as a real `.app` bundle - see
`facts/AVFoundation/AVAudioSessionCategoryModeOptions.md`). `kAudioUnitSubType_GenericOutput` does
not: it is Apple's own offline-rendering terminal, pulled by hand through `AudioUnitRender`, never
touching real hardware I/O or the audio daemon. A test graph terminated in `GenericOutput` -
`AVAudioPlayerNode` scheduling a known buffer, through real `AVAudioEngine` node/connection/format
plumbing, pulled and compared sample-for-sample at the far end - proves the actual graph mechanics
on the emulator, no device queue required for this part.

What this does **not** close, named up front rather than found out later: an application's real
`outputNode`/`mainMixerNode` runs through `RemoteIO`, not `GenericOutput`, and `RemoteIO` imposes
its own stream format - the hardware's own sample rate and channel layout - at the connection,
which a test graph built with formats of its own choosing never exercises. That is exactly where a
real device's graph tends to go silent instead of erroring. So the offline `GenericOutput` proof
covers the graph's own logic; a second, narrower measurement against a real `RemoteIO` output,
checking that the samples fed in are the samples that come out through actual hardware, still
needs a device and comes after this.

## What is built: `AVAudioEngine` and `AVAudioPlayerNode`

`AVAudioEngine` owns one real `AUGraph`, created in `-init`: a `kAudioUnitType_Output` node
(`kAudioUnitSubType_GenericOutput` in offline/test mode, `kAudioUnitSubType_RemoteIO` for a real
application - the switch is `CharonAudioEngineTestSupport`'s only job, never set outside a
device-probe) and a `kAudioUnitType_Mixer`/`kAudioUnitSubType_MultiChannelMixer` node, connected
mixer -> output before any application code runs - matching the real class's own default wiring.
`attachNode:`/`detachNode:`/`connect:to:format:`/`disconnectNodeOutput:`/`prepare`/
`startAndReturnError:`/`mainMixerNode`/`inputNode`/`outputConnectionPointsForNode:outputBus:`/
`autoShutdownEnabled` are all real, all registered (`registry/AVFoundation/ios8avaudioengine.json`).

`AVAudioPlayerNode` carries no `AudioUnit` of its own - there is no stock Apple component that
takes arbitrary `AVAudioPCMBuffer`s as input the way `scheduleBuffer:` needs. It is a buffer
queue (`CharonScheduledBuffer`), read frame-by-frame by a C render callback
(`CharonPlayerRenderCallback`, `AVAudioPlayerNode.m`) that `-connect:to:format:` wires directly
onto the destination node's real input bus through `AUGraphSetNodeInputCallback` - the callback
*is* the connection on that side, exactly the way a generator unit would be if this device shipped
one for this job. A raw byte copy moves samples from the scheduled buffer into `ioData`, correct
because `-connect:to:format:` has already forced the destination's format to match the source's -
same bytes-per-frame, same channel count, same (non-)interleaving, by the same rule the real class
documents.

**Two real bugs found and fixed while proving this, neither visible to `nm`/the build gate:**

- `AVAudioEngine`'s `-startAndReturnError:` originally always called `AUGraphStart`. On a
  `GenericOutput`-terminated graph this is wrong: `AUGraphStart` hands control to a hardware I/O
  thread that offline rendering, by definition, does not have. Measured directly: every setup
  call (`AUGraphOpen`/`AddNode`/`ConnectNodeInput`/`SetProperty`/`AUGraphInitialize`) returned
  `noErr`, and the *first* manual `AudioUnitRender` pull still failed with `-50` (`paramErr`) every
  time, only after `AUGraphStart` had run. `-startAndReturnError:`/`-pause`/`-stop` now skip
  `AUGraphStart`/`AUGraphStop` when the engine was constructed for offline output, mirroring how
  Apple's own real `AVAudioEngine` manual rendering mode (iOS 11+) never calls the live-device
  start path either.
- The output unit's own **Output**-scope stream format was never set - only its Input scope was
  (the scope the mixer feeds into). `AudioUnitRender` reads a unit's Output-scope ASBD to know how
  to lay out what it writes into `ioData`; without it, every setup call still returns `noErr` and
  only the render call itself fails with `-50`. Found by a standalone raw-`AUGraph` probe outside
  this class (`.agent-work/scratch/avaudio-build/raw-graph-probe.m`, not part of this port) that
  isolated the exact same eleven-call setup sequence with full status checking at every step -
  adding the missing `AudioUnitSetProperty(..., kAudioUnitScope_Output, ...)` call turned `-50`
  into an exact sample match on the very next run, before the fix was ported into
  `AVAudioEngine.m`'s real `-connect:to:fromBus:toBus:format:`.

**Measured, not assumed - `checks=13 failures=0`, `tests/backports/device/avfaudioengine.m`-style
probe** (currently `.agent-work/scratch/avaudio-build/engine-probe.m`, not yet promoted): attaches
a real `AVAudioPlayerNode`, connects it to the real `mainMixerNode`, schedules a 512-frame known
sine waveform, starts the engine, pulls the graph's real output by hand
(`AudioUnitRender` against the real `GenericOutput` unit, one call for the whole buffer - a
chunked pull with the `AudioTimeStamp` reset to sample time 0 on every call was tried first and
only matched for the first chunk, since the mixer tracks its own internal sample-time continuity
across calls), and compares every one of 512 samples against what was scheduled. Exact match, not
just non-zero - first eight of both: `+0.0000 +0.0250 +0.0499 +0.0747 +0.0993 +0.1237 +0.1478
+0.1714`, identical. Run against the fresh build twice, from a completely clean private package
cache both times, to rule out any stale-binary artifact.

A third symbol-visibility trap, found and fixed along the way, is recorded in
`AVFoundation/CharonAVAudioEngine.h` itself rather than here: this project deliberately hides every
symbol whose bare name starts with `charon_`/`Charon` from a dylib's exported table
(`modules/apple/backports.lua`'s `internal_symbol()`), and a brand-new such class needs to be
reached by runtime lookup (`NSClassFromString`/`objc_msgSend`) from a separate test binary, not
static linking - `CharonAudioEngineTestSupport`/`engine-probe.m` is the worked example.

## Not yet closed

- The narrower `RemoteIO`/hardware-format measurement named above (needs a device).
- `AVAudioUnitEQ` and `AVAudioConverter` - real work, not started; their Audio Components
  (`NBandEQ`, and `AudioConverterServices`'s C functions) are already confirmed present, above.
- `AVAudioInputNode`'s real capture path (kept as a real object from construction, never exercised).
- Multi-input mixer topology (more than one `AVAudioPlayerNode` at once) and inserting an effect
  node between player and mixer - this pass only wires a single player straight to the mixer.
