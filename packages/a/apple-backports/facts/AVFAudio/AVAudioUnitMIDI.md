# AVAudioUnitMIDIInstrument and AVAudioUnitSampler are not carried

Neither class is in `libAVFAudioBackports.dylib`, and the reason is a measurement of the release, not
a difficulty.

**iOS 6.1.3 exports no function that sends a MIDI event to an audio unit.** Its AudioToolbox
`AudioUnit` family is exactly these twenty-seven: `AudioComponentInstanceNew`,
`AudioComponentInstanceDispose`, `AudioComponentInstanceCanDo`, `AudioComponentInstanceGetComponent`,
`AudioComponentCount`, `AudioComponentFindNext`, `AudioComponentGetDescription`,
`AudioComponentCopyName`, `AudioComponentGetVersion`, `AudioComponentRegister`,
`AudioUnitGetProperty`, `AudioUnitSetProperty`, `AudioUnitGetPropertyInfo`, `AudioUnitGetParameter`,
`AudioUnitSetParameter`, `AudioUnitInitialize`, `AudioUnitUninitialize`, `AudioUnitReset`,
`AudioUnitProcess`, `AudioUnitProcessMultiple`, `AudioUnitRender`, `AudioUnitComplexRender`,
`AudioUnitAddPropertyListener`, `AudioUnitRemovePropertyListenerWithUserData`, `AudioUnitAddRenderNotify`,
`AudioUnitRemoveRenderNotify`, `AudioUnitScheduleParameters` (plus the AUGraph family). There is no
`AudioUnitSendMIDIEvent` and no `AUGraphSendMIDIEvent` among them.

What the release *does* export in full is `MusicSequence` and `MusicPlayer`:
`MusicSequenceNewTrack`, `MusicSequenceDisposeTrack`, `MusicSequenceSetUserCallback`,
`MusicSequenceGetInfoDictionary`, `MusicSequenceSetAUGraph`, `MusicSequenceGetAUGraph`,
`MusicSequenceFileCreate`, `MusicSequenceFileCreateData`, `MusicSequenceFileLoad`,
`MusicSequenceFileLoadData`, `MusicSequenceSetMIDIEndpoint`, `MusicSequenceGetSequenceType`,
`MusicSequenceSetSequenceType`, `MusicSequenceNewTrack` through `MusicSequenceGetIndTrack`,
`MusicSequenceGetTrackIndex` and `MusicSequenceGetTrackCount`, and `MusicPlayerStart`, `MusicPlayerStop`,
`MusicPlayerPreroll`, `MusicPlayerSetPlayRateScalar`, `MusicPlayerGetPlayRateScalar`,
`MusicPlayerSetSequence`, `MusicPlayerGetSequence`, `MusicPlayerSetTime`, `MusicPlayerGetTime`,
`MusicPlayerIsPlaying`, `MusicPlayerGetBeatsForHostTime`, `MusicPlayerGetHostTimeForBeats`. That is
how MIDI reaches a unit on this release, and it is what the sequencer family is built over — the
`AVAudioSequencer`, `AVMusicTrack` and `AVMusicEvent` rows of the same ledger.

**iOS 6.1.3 carries no sampler component.** The Apple sampler is a system dynamic library the release
loads on demand when an application asks for it, not a unit in the shared cache, so
`kAudioUnitSubType_Sampler` names no component in the cache and
`loadSoundBankInstrumentAtURL:program:bankMSB:bankLSB:error:` has no unit to load into.

So the note and controller methods are not written as a queue that nothing drains, and a sound-bank
load is not answered as having succeeded. Both would be the silent fake `COORDINATION` §2 forbids. They
are carried with the sequencer, which has the real path.
