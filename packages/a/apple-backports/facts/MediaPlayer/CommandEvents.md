# The command events iOS 6.1.3 has no name for, and the chain a caller walks

`facts/MediaPlayer/MPMediaItem.md` records what this port carries of `MPMediaItem`. This file records the
seven command-event rows of the MediaPlayer queue that were filed `absent` on the ground that "the class
arrived in iOS 7.1 / iOS 8.0", and what they answer instead.

## What the release has, measured

Read with `tools/mach32_methods.py` from the armv7 shared cache of 6.1.3
(`~/.charon/dyld/6.1.3/dyld_shared_cache_armv7`, the MediaPlayer image at `0x31fe3000`), the same read
whose controls are `tools/mach32_methods_test.py`:

- **236 classes** in `__objc_classlist` and **41** in `__objc_catlist`.
- **No class whose name holds `CommandEvent`** is among the 236, and none of the 41 categories adds one.
  `MPRemoteCommandCenter`, `MPRemoteCommand`, `MPRemoteCommandEvent` and every `*Command` are absent too -
  which is why `MPRemoteCommandCenter71.m` bridges them onto iOS 6's `UIEventTypeRemoteControl` by hand.
- **None of the 236 declares `isNegative`, `repeatType`, `shuffleType`, `preservesRepeatMode`,
  `preservesShuffleMode` or `negative`** - every class in the image was read and each of those six names
  is absent from every own instance list and every own class list.
- `-aSelectorNoFrameworkHas` is absent, so the reader answers NO to a name that is not there.

The whole-cache selector universe of the same release (`~/.charon/dyld/6.1.3/selectors_armv7.txt`,
113981 lines) is a list of **distinct names**, not a count per class: `dealloc` is on one line, not 433,
and `valueForProperty:` is on one line, not 26. Read that way it says something this family needs said and
nothing more: `isNegative`, `repeatType` and `shuffleType` are each on **one** line, so those three names
**do** occur somewhere in the 6.1.3 cache - on some other framework's class - while
`preservesRepeatMode` and `preservesShuffleMode` are on **none**. `prepareToPlay` is on one line and
`aSelectorNoFrameworkHas` on none, which are the controls that say the list is read and not guessed at.

That is exactly the trap `facts/MediaPlayer/MPMediaItem.md:105` records: a name in the per-cache list is
necessary and not sufficient, `albumTrackNumber` is declared by `MPAVItem` and `MPMediaQueryNowPlayingItem`
in the same image and is not an `MPMediaItem` accessor. The **per-class** read is what decides a member,
and it is the one above: within the MediaPlayer image all six names are absent, so every one of these
members is the port's to carry.

So every one of these classes is new code that cannot shadow anything. `absent` is for a member whose
answer needs hardware the device lacks; none of these needs any. They are carried.

## The gap that made this more than a formality

The port already carried four public events whose **public** ancestor chain names this class:
`MPRatingCommandEvent`, `MPSkipIntervalCommandEvent`, `MPChangePlaybackRateCommandEvent` and
`MPChangePlaybackPositionCommandEvent` (`registry/MediaPlayer/ios71remotecommand.json`,
`mpchangeplaybackposition.json`, `mpchangeplaybackrate.json`, `mpratingcommandevent.json`). A caller who
writes

```objc
[event isKindOfClass:[MPFeedbackCommandEvent class]]
```

got **NO** for every event this port builds. On the release that class exists and every feedback event is
one of its instances. Nothing in the port's header said otherwise - the classes were declared as
`MPRemoteCommandEvent`, which is the port's own base and a real class - so no compiler and no reviewer of
the earlier series could see it. Carrying `MPFeedbackCommandEvent` closes the link.

The 8.0 pair is the same defect one step along: the port carries `MPChangeRepeatModeCommand` and
`MPChangeShuffleModeCommand` (8.0, `ios71remotecommand.json`), and `MPRemoteCommandCenter71.m` builds
every command event lazily by class, so both commands had an event class that did not exist. iOS 6's
`UIEventTypeRemoteControl` has no repeat-mode and no shuffle-mode subtype, so the port's bridge never
sends one - an addressable command with no answer is what the corpus filed as `absent`.

## What each answers

`MPRemoteCommandEvent.h` at SDK 26.2, quoted, is the whole contract:

```
@property (nonatomic, readonly, getter = isNegative) BOOL negative;                 // 7.1
@property (nonatomic, readonly) MPRepeatType repeatType;                            // 8.0
@property (nonatomic, readonly) BOOL preservesRepeatMode;                           // 8.0
@property (nonatomic, readonly) MPShuffleType shuffleType;                          // 8.0
@property (nonatomic, readonly) BOOL preservesShuffleMode;                          // 8.0
```

- **`-isNegative` is the selector, and `negative` is not one.** The header writes `getter = isNegative`,
  so the property name is not a selector on any platform. The port declares `-isNegative` and nothing
  named `negative`, and the registry row is `MPFeedbackCommandEvent.isNegative` - the same spelling
  `MPMediaItem.isCompilation` and `MPMediaItem.hasProtectedAsset` already use
  (`facts/MediaPlayer/MPMediaItem.md:61,79`). A probe that asked for `negative` would have learned
  nothing about this family.
- **`NO` is what an event that set nothing answers**, and it is the declared zero of `BOOL`.
- **`MPRepeatType` has no "unknown" case** - `MPRemoteControlTypes.h:17` gives `MPRepeatTypeOff`,
  `MPRepeatTypeOne`, `MPRepeatTypeAll` - and `MPShuffleType` has none either
  (`MPRemoteControlTypes.h:11`: `MPShuffleTypeOff`, `MPShuffleTypeItems`, `MPShuffleTypeCollections`).
  An event that set nothing therefore answers `MPRepeatTypeOff` / `MPShuffleTypeOff`, which is the value
  for "no repeat" and "do not shuffle". A stand-in that added an `Unknown` case would have let the port
  compile against a type the SDK does not declare; `MPMediaItemStandin.h` spells the three cases out for
  that reason.
- **Readwrite in the port, readonly in the header.** Every event the port builds has to be able to carry
  the value it is an event *about*, and a new class shadows nothing. The accessors the header declares are
  what a caller reads, and they read what the port set. The accessors are written out rather than left to
  the synthesiser, so removing `@synthesize` is not a change of behaviour - ARC would synthesise exactly
  the same accessor - and a caller reads the port's own code.

One object per release, per `band()`'s own rule: `MPFeedbackCommandEvent.m` holds the 7.1 class and
nothing else, `MPChangeRepeatModeCommandEvent80.m` the 8.0 repeat event and not the 8.0 shuffle one, and
`MPChangeShuffleModeCommandEvent80.m` the 8.0 shuffle event. Three releases of one family, three objects.