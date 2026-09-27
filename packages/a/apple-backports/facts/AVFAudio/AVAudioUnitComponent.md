# AVAudioUnitComponent and AVAudioUnitComponentManager

Carried in `libAVFAudioBackports.dylib` (the `avfaudio` config), over the AudioComponent discovery C
API that iOS 6.1.3 exports in full. Measured on the real armv7 shared cache with `dyld.load`
(`~580 libraries`): AudioToolbox exports exactly these ten of the family -
`AudioComponentCount`, `AudioComponentFindNext`, `AudioComponentGetDescription`,
`AudioComponentCopyName`, `AudioComponentGetVersion`, `AudioComponentInstanceNew`,
`AudioComponentInstanceDispose`, `AudioComponentInstanceCanDo`, `AudioComponentInstanceGetComponent`
and `AudioComponentRegister` - plus the whole `AudioUnit` and the whole `AUGraph` family. Every
answer below is one of those.

## What is a real measurement

- **`name`** is `AudioComponentCopyName`. **`version`** is `AudioComponentGetVersion`, and
  **`versionString`** is that number in the hexadecimal layout `0xMMMMmmDD` the header names, printed
  as `major.minor.dot-release`.
- **`audioComponentDescription`** is `AudioComponentGetDescription`, and **`typeName`** is that
  description's `componentType` mapped onto the eleven type names the release itself exports (read
  out of a real cache - see `AVFAudioStrings.md`).
- **`manufacturerName`** is the description's four-character manufacturer code: `appl` reads as the
  string the release exports for the Apple manufacturer, any other code as itself. Apple's own name
  comes out of a component bundle's `Info.plist`, which a component inside the shared cache has not
  got, so the code is what the release holds and that is what is answered.
- **`hasMIDIOutput`** is asked of the component: a real instance is made with
  `AudioComponentInstanceNew` and asked for `kAudioUnitProperty_MIDIOutputCallback`. A unit without
  that property answers an error, which is `NO`.
- **`supportsNumberInputChannels:outputChannels:`** is the header's own test, asked of a real
  instance: a 32-bit float PCM stream format of the requested channel count is offered to the unit's
  input and output scope with `AudioUnitSetProperty(kAudioUnitProperty_StreamFormat, ...)` and the
  unit's answer decides.
- **`sandboxSafe`** answers the header's own sentence for iOS: "On iOS, this is always YES."
- **`localizedTypeName`** is the type name: it already carries the words and spaces of the release's
  own type names, and this release has no component bundle to hold a localized string.
- The three searches are real: `componentsMatchingDescription:` walks
  `AudioComponentFindNext` with the description given (a zero field is the release's own wildcard),
  `componentsPassingTest:` runs the block over the same walk and honours its `stop` out-parameter,
  and `componentsMatchingPredicate:` evaluates the predicate against each component and then against
  the keys the header's own documentation names, so `"typeName CONTAINS 'Effect'"` and the older
  `tags` key both work. A predicate that names a key this release answers nothing for matches
  nothing rather than raising.

## What this release does not have, measured

- **Tags.** iOS 6.1.3 exports no `AudioComponentCopyTags` and no `AudioComponentGetParameter`, so
  there is nothing to ask and no component of this release carries a tag. `allTagNames`,
  `userTagNames` (and its setter), `AVAudioUnitComponentManager.tagNames` and
  `standardLocalizedTagNames` answer the **empty array** - the true answer over an empty set, not a
  stub - and the two tag notifications are declared and never posted. The port that owns this file
  has no `AudioComponentRegister` caller of its own, so it posts neither; a registration made by
  the host application itself through the release's own C API is found by the next search, because
  every search walks the release again.
- **`configurationDictionary`** (iOS 16) answers the **empty dictionary**: the release has no
  `AudioComponentCopyInformation` to describe a component with, so the information it holds is the
  empty set. Not filled with a plausible-looking key.
- **`passesAUVal`** (iOS 16) answers `NO`: Apple's AU validation suite is not on the device and no C
  API of this release reports a result, so nothing here has passed it. `NO` describes the state of
  this release rather than standing in for an answer.
- **`icon`** and **`iconURL`** answer `nil`, and **`hasCustomView`** answers `NO`: a component of
  this release is inside the shared cache, which has no bundle and no resource to draw an icon from.
  The header allows `nil` for both.
- **`componentURL`** answers `nil` for the same reason: the cache has no path in the file system.
- **`availableArchitectures`** answers the one Mach-O architecture constant of the slice this
  library is built for. A component of the shared cache carries no other slice.

## The two strings this file defines

`AVAudioUnitComponentTagsDidChangeNotification` (iOS 9) and, in
`AVFAudioSessionNotification13.m`, `AVAudioUnitComponentManagerRegistrationsChangedNotification`
(iOS 13) - the notification a manager posts when a registration adds a component its list did not
hold. Values read out of a real release; see `AVFAudioStrings.md`.

## A parsing trap worth knowing

`if ([testHandler(component, &finished)])` does not compile: clang parses the message send's
receiver as a **declarator** - `testHandler(component, &finished)` looks like a parameter list - and
reports `expected identifier` on the ampersand. Writing the call as
`if ((testHandler(component, &finished)))` makes the receiver the expression it is. Any block
invocation with an address-of argument inside `[...]` needs the parentheses.
