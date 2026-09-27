# AVAudioUnitMIDIInstrument, and a correction

Carried in `libAVFAudioBackports.dylib` (the `avfaudio` config), over the release's own MusicDevice
send API. Thirteen methods, 15 registry entries.

## The correction

An earlier report of this band said the release "exports no function that sends a MIDI event to an
audio unit" and refused the class. **That was wrong**, and the way it was wrong is the useful part: the
check that produced it grepped the `AudioUnit*` prefix and read the head of a truncated `_AU*` listing.
The coordinator's challenge — "on iOS the AudioUnit functions live in AudioToolbox's exports, not under
an `AudioUnit*` prefix; grep for `_MusicDevice`" — is what found it.

The measurement, over the **whole** of AudioToolbox in the 6.1.3 armv7 cache and then over all 580
libraries of it:

```
$ python3 -c "
import json
d = json.load(open('/tmp/all6.json'))
at = [v for k, v in d.items() if k.endswith('AudioToolbox.framework/AudioToolbox')][0]
print('AudioToolbox exports:', len(at))
print([e for e in at if e.startswith('_MusicDevice')])"

AudioToolbox exports: 337
['_MusicDeviceMIDIEvent', '_MusicDeviceStartNote', '_MusicDeviceStopNote', '_MusicDeviceSysEx']
```

and the same file shows the whole of the 37 `_AU*` exports is `AUGraph*` (29) and `AUPB*` (8) — no
`AUEventDispatcher*`, which is a separate thing and is not needed here.

`MusicDevice.h` of SDK 16.4 documents them as send functions, all `API_AVAILABLE(ios(5.0))`:

- `MusicDeviceMIDIEvent(inUnit, inStatus, inData1, inData2, inOffsetSampleFrame)` — "Used to sent
  MIDI channel messages to an audio unit", `inUnit` "The audio unit", the data bytes "exactly as
  described by the MIDI specification, including the combination of channel and command in the status
  byte".
- `MusicDeviceSysEx(inUnit, inData, inLength)` — "used to send any non-channel MIDI event to an audio
  unit… the complete MIDI SysEx message including the F0 and F7 start and termination bytes".
- `MusicDeviceStartNote(inUnit, inInstrument, inGroupID, outNoteInstanceID, inOffsetSampleFrame, inParams)`
  and `MusicDeviceStopNote(inUnit, inGroupID, inNoteInstanceID, inOffsetSampleFrame)` — the extended
  note API. The header's own rule: "To stop a note it must be stopped with the same API group as was
  used to start it."

## What each method calls

- `startNote:withVelocity:onChannel:` calls `MusicDeviceStartNote` and **keeps the note instance it
  returns**, so `stopNote:onChannel:` calls `MusicDeviceStopNote` with the same instance, as the
  header requires. A release that answers the extended call gets the extended pair; one that does not
  falls back to the MIDI note-on and note-off events, which the same header documents as the other
  legal way ("(1) the MIDI Note on event (MusicDeviceMIDIEvent) — notes must be stopped with the MIDI
  note off event").
- The four channel messages, both `sendMIDIEvent:` forms, and the two program-change forms are
  `MusicDeviceMIDIEvent` with the status byte the MIDI specification gives each message, channel in
  the low nibble. A 14-bit pitch bend is the low seven bits in `inData1` and the high seven in
  `inData2`. A banked program change is the two bank-select controller events and then the program
  change.
- `sendMIDISysExEvent:` is `MusicDeviceSysEx` with the whole block, F0 and F7 included.
- `inOffsetSampleFrame` is `0` throughout, which is what the header says to pass when not scheduling
  from the unit's render thread: these methods are called from the host's thread, not from a render
  callback.

## What is still not carried

`-[AVAudioUnitMIDIInstrument sendMIDIEventList:]` (iOS 16) is **`absent`**, and the reason is in its
registry entry: the list form is `MusicDeviceMIDIEventList`, which is not among the four exports above.
An application that calls it gets an unrecognised selector, which is what `absent` means; the
single-event and system-exclusive forms are carried and work.

**`AVAudioUnitSampler` is still unmeasured, and this report does not claim anything about it.** The
absence of a `Sampler` symbol in the cache is not evidence about the sampler *component*, because a
component is a registration and not an exported symbol — so the grep I ran proves nothing either way,
and I am not going to write it up as if it did. The measurement that settles it is
`AudioComponentFindNext` for `{kAudioUnitType_MusicDevice, kAudioUnitSubType_Sampler, 'appl'}` on the
emulator at 6.1.3, which is queued next; whatever it answers is what goes in
`facts/AVFAudio/AVAudioUnitSampler.md`, with the command and its output pasted in.
