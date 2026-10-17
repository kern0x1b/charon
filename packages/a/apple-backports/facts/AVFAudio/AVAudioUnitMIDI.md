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

## The initializer

`-initWithAudioComponentDescription:` (`introduced` 8.0) is declared on both SDKs the same way:
nonnull, under `AVAUDIOUNIT_HAVE_AUDIOUNIT` (`AVAudioUnitMIDIInstrument.h:36` of iOS SDK 26.2 and of
macOS SDK 27.0). The header says the description is for an AUv2 unit of type
`kAudioUnitType_MusicDevice` or `kAudioUnitType_RemoteInstrument`, and that an AUv3 unit goes through
`instantiateWithComponentDescription:options:completionHandler:`. The header says nothing about a zero
type or manufacturer.

**Port choice, not Apple behaviour:** when `componentType` is 0 the port uses `kAudioUnitType_MusicDevice`,
and when `componentManufacturer` is 0 it uses `kAudioUnitManufacturer_Apple`. The override calls the
AVAudioUnit hook (see `CharonAVAudioUnit.h`), and never returns nil: `NSObject`'s `init` does not fail,
so the nonnull declaration holds for every description.

## The list form

`-[AVAudioUnitMIDIInstrument sendMIDIEventList:]` (iOS 16) is **implemented**, and it is not
`MusicDeviceMIDIEventList`, which this release does not export: the list is decoded in the port
(`AVFAudio/CharonMIDIEventList.h`) and each MIDI 1.0 channel message in it goes out as one
`MusicDeviceMIDIEvent`, in order.

- A Universal MIDI Packet word of **type 2** (the MIDI 1.0 channel voice) carries status in bits 23-16, data1 in
  15-8 and data2 in 7-0. Each such word is one call.
- A word of **any other type** is skipped. That is the difference from the list form: a system message, a MIDI 2.0
  channel voice, a SysEx or utility word is not sent, because the release has no call that could carry it. An
  application that sends only channel messages, the usual case, sees no difference.
- A `NULL` list, and a list with no type-2 word, send nothing.

`tests/backports/host/avfaudio/midilist.sh` checks seven type-2 words (note on, note off, controller, pitch bend,
program change, channel pressure, poly pressure), with one type-4 word between them, against the MIDI 1.0 bytes each
word encodes; a list with only a type-4 word sends nothing. The oracle is those bytes written out by hand, not the
host, because the host's three-byte `sendMIDIEvent:data1:data2:` does not reach `MusicDeviceMIDIEvent` on this host:
an interposer on that call records nothing from it, and AVFAudio's imports list no `MusicDevice*` symbol. So the test
shows what the port sends to the release's call, and the host agrees only on the bytes it accepts.

## What is still not carried

The note-control half of the sampler (`startNote:velocity:channel:` and its kin on `AVAudioUnitSampler`) is the
sampler's own instrument interface, and it is not in this file's scope; `AVAudioUnitSampler.md` says what the
sampler carries.
