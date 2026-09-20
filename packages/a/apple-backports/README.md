# What the backports carry, release by release

How the package is built, banded and checked is in the repository's README, and
the four answers an entry can give - `implemented`, `inert`, `absent`,
`ignored` - are in `registry/README.md`. The registry is the list: every API
considered has an entry there, and the build refuses a class or selector that
has none. This file is the reasoning behind the answers, a section per range of
releases, so that a port can see at a glance what it gets, what it gets with a
difference, and what it will never get here and why.

## iOS 10

### Feedback that is a vibration, not a haptic

The three feedback generators are implemented against the motor the iPhone 4S
has, and one of the four is not implemented at all. Both halves of that are
measurements rather than opinions, and `facts/UIKit/UIFeedbackGenerator.md`
carries the numbers.

iOS 10 tells `light`, `medium` and `heavy` apart by which Taptic waveform it
plays, not by how hard - the volumes of the three differ by a tenth. An
eccentric rotating mass has no waveforms, only amplitude and length, so this
port separates the three by strength and duration instead. It is the same API
and the same three steps of emphasis; it is not the same sensation, and nothing
here pretends otherwise. On hardware with no motor at all, such as the iPad 2,
every call plays nothing, which is what iOS 10 itself does on a device without a
Taptic Engine.

`UISelectionFeedbackGenerator` is there and **does nothing**. Measured on an
iPhone4,1, a pulse of 20 ms does not start the motor and 40 ms is the shortest
that moves it, while full amplitude needs upwards of 200 ms. A tick per detent of
a turning picker is faster than that floor, so the class cannot make the
sensation it stands for; what iOS 10 does on a device without a Taptic Engine,
where the class exists and `-selectionChanged` plays nothing, is what it does
here. A program that names the class then finds it, as it would on iOS 10.

The motor is reached through
`AudioServicesPlaySystemSoundWithVibration`, the path the system itself uses, so
mediaserverd keeps its own arbitration; the port does not write the IORegistry
node behind its back. `-prepare` has nothing to warm and does nothing, which is
also what iOS 10 does when there is no engine.

### Notifications through the scheduler iOS 6 already has

`UNUserNotificationCenter` is carried as a facade over the local notifications
of iOS 6: a request becomes a `UILocalNotification`, the pending requests are
read back from the ones scheduled, and the delegate hears of a notification
through the application delegate, whose `-application:didReceiveLocalNotification:`
the center takes over for its own notifications only. The triggers find their
dates as the newest release does, held on 5760 dates on the host and on iOS
6.1.3.

What the release cannot show is kept rather than faked. The title and subtitle
travel with the request everywhere and are never shown, since a local
notification of iOS 6 has no title; the one place that would hand the title to
the release is a single switch, off. Categories and threads are kept and change
nothing. A repeat iOS 6 cannot follow - every 90 seconds, the 31st of every
month - is refused with an error rather than scheduled to fire on other dates.
The settings report what the application asked for, since iOS 6 tells it
nothing of what the user set. Attachments, categories, actions, location
triggers, service extensions and the delivered notifications are absent: the
last live in BulletinBoard, which answers no application on this jailbreak.

### Core Data's container, in a library of its own

`NSPersistentContainer` and `NSPersistentStoreDescription` are carried in
`libCoreDataBackports.dylib`, built with the `coredata` config, so that only a
port that keeps its data with Core Data loads Core Data. With them come the
members iOS 10 gave the classes iOS 6 has: `-initWithContext:`, `+entity` and
`+fetchRequest` of a managed object, `-execute:` of a fetch request,
`automaticallyMergesChangesFromParent` of a context, the description-taking way
to add a store, and the merge policies as class properties. `-execute:` needs
to know the context whose block is running, which iOS 6 does not record, so
the library records it around `-performBlock:` and `-performBlockAndWait:`.
Query generations are absent: they read a snapshot of a store kept with
write-ahead logging, and the store of iOS 6 keeps a rollback journal.

### Blocks for timers, threads and run loops, and what stays out

`NSTimer` gets the block factories and `-initWithFireDate:interval:repeats:block:`,
`NSThread` gets `-initWithBlock:` and `+detachNewThreadWithBlock:`, `NSRunLoop`
gets `-performBlock:` and `-performInModes:block:`, `NSFileManager` gets
`temporaryDirectory`, `UIImage` gets `-imageWithHorizontallyFlippedOrientation`
and `UIScreen` gets `maximumFramesPerSecond`, each read from the release's own
code and answering the same, the text of the exceptions included; the flipped
image is rebuilt from public API, and its facts say where that differs.
Left out because iOS 6 cannot answer as iOS 10 does: the pasteboard's `hasStrings`,
`hasURLs`, `hasImages`, `hasColors` and `-setItems:options:`, which ask a
pasteboard service and a framework iOS 6 does not have and, with an expiration
date, promise to clear the pasteboard after the application has gone, and the
Display P3 colors, which need a color space iOS 6 cannot make.

### os_log, written to the system log

A program built for iOS 6 reaches `os_log` through the iOS 9 functions, `_os_log_internal` and `_os_log_create`,
which the macros choose below a deployment target of 10.0. The port carries those and the log object they need, and
writes each message, formatted as the release's own formatter writes it, to ASL. Nothing is redacted, and a few
decorators for a reader, such as `iec-bytes`, are written plain; the facts say which.

### Text content types, kept and never read

The 23 `UITextContentType` constants of iOS 10 have the release's own strings, and
`textContentType` of a text field, a text view and a search bar keeps a copy and
gives it back. Nothing reads it: it hints at an autofill iOS 6 does not have.

### Images drawn where sRGB cannot be made

`UIGraphicsImageRenderer` draws in sRGB, as iOS 10 does, so that its PNG and
JPEG match UIKit's byte for byte. On an iPhone4,1 running 6.1.3 CoreGraphics
makes no sRGB space - `CGColorSpaceCreateWithName(kCGColorSpaceSRGB)` answers
`NULL` - and there the renderer draws in device RGB, the space the release's own
UIKit draws every image context in. The pixels are the same; the files carry no
colour profile, like every image that release makes itself.

## iOS 11 and 12

These two releases are read differently from the ones before them. The last
firmware with a 32-bit slice is 10.3.4, so there is no armv7 implementation of
anything iOS 11 added; the behaviour is read from arm64 - from 11.0 and 12.0
themselves, where the calls still go through `objc_msgSend` and the selectors
can be read, and from 16.0 and 18.0 for the numbers a later release corrected -
and the code here is written anew for armv7 and armv7s. What a facts file under
`facts/` names is what was read; nothing in this range was carried over from an
older implementation.

### Carried

Foundation gets the secure coding surface of the archivers: an archiver created
requiring secure coding and asked for its `encodedData`, an unarchiver reading
from data with an error, and the two convenience class methods that stand for
the whole round trip. Beside them: the property list readers and writers that
take a URL and fill in an error, `NSURLComponents`'
`percentEncodedQueryItems`, `-decodeValueOfObjCType:at:size:`,
`NSSecureUnarchiveFromDataTransformer`, and the validated format constructors
of `NSString`, which are the ones a program uses when the format string comes
from outside it.

UIKit also gets the list of interactions a view holds - the list, the two
callbacks an interaction is told its move by, and the owner - which is
bookkeeping the release can do even though Apple's own interactions of that
release cannot be carried, and the attributed label, hint and value of
accessibility, whose text reaches this release's VoiceOver through the plain
property it has kept since iOS 3.

UIKit gets directional edge insets whole - the struct's zero, its two string
functions, its `NSValue` and `NSCoder` surface - and then the parts of the safe
area that are values rather than moments: `-safeAreaInsets` on a view,
`additionalSafeAreaInsets` on a controller, and on a scroll view
`adjustedContentInset` with the `contentInsetAdjustmentBehavior` that decides
it. With them come `directionalLayoutMargins`, the two comparison functions of
the content size categories, the large title text style, `UIFontMetrics`, the
system spacing anchors, the name of a gesture recognizer, and
`-performBatchUpdates:completion:`.

The renderer formats get `+preferredFormat` and
`+formatForTraitCollection:`. The preferred format is the default one: in 11.0,
12.0 and 18.0 alike, the image format answers its own `+defaultFormat`. A trait
collection sets the scale and whether the format prefers an extended range, and
nothing else.

A program built for a release that has these frameworks asks each of them one
question before it does anything else, and a program recompiled for this one
links the classes it asks it of. So the classes and the question are carried
where the answer is a plain one: `DCDevice`, with the one shared object and
`-isSupported` answering YES as the release's own constant does;
`ARConfiguration` and the five subclasses of iOS 11 and 12, whose
`+isSupported` answers NO, since ARKit asks for an A9 chip and these devices
have an A5; and `NFCReaderSession` with `NFCNDEFReaderSession`, whose
`+readingAvailable` answers NO on a device with no NFC. The error domains an
application compares an error against, `DCErrorDomain`, `ARErrorDomain` and
`NFCErrorDomain`, are carried with the release's strings. Everything behind the
question - a token, a session, a setting, an anchor, a tag - is absent, and
`respondsToSelector:` and `NSClassFromString` say so.

`NSProcessInfo.thermalState` answers nominal and its notification is never posted, and the export presets of the image picker are kept and not applied: the release publishes no thermal pressure level a process can read, and its picker hands over a JPEG and transcodes a movie by its quality. All three are `inert`, and each says so once in the log.

### Carried with a difference

Each of these is implemented, tested against the real implementation, and
departs from it in one named way; the facts file says so and the registry entry
repeats it.

`-[DCDevice generateTokenWithCompletionHandler:]` asks a daemon, `com.apple.devicecheckd`,
that iOS 6 does not run. The handler hears `DCErrorFeatureUnsupported` - the
header's word for DeviceCheck being unavailable on this device - from a
background queue, after the call has returned, where the release's own path
for a daemon it cannot reach answers `DCErrorUnknownSystemFailure`. That is the
one departure, chosen because an application that reads the documentation
handles the first as a settled answer and the second as a reason to retry.
`facts/DeviceCheck/DCDevice.md` has what was read from the release, what came from
the header and what the host answered.

The safe area insets and the adjusted content inset are computed on every read
rather than stored, because nothing here tells the port when they change. An
application that reads them gets the same numbers; one that expects a stored
value to go stale between layouts does not.

`+[NSArray arrayWithContentsOfURL:error:]` fills in an error where 11.0 answers
nil and leaves the error empty for a plist whose top level is of the wrong
kind, and `+[NSKeyedArchiver archivedDataWithRootObject:requiringSecureCoding:error:]`
returns the error that 11.0 and 12.0 let escape as an exception. Both are the
later releases' behaviour, which is the rule for this package.

`UIFontMetrics` scales by a ratio that is one on this release: iOS 6 has a
single content size category, so a metric has nothing to scale between. The
arithmetic, the maximum point size and the rounding are the real ones, and a
release with more categories would need only the table. The system spacing
anchors follow the current implementation, which rounds the spacing up to the
screen scale, not iOS 11's, which did not. `percentEncodedQueryItems` refuses
a query with characters that do not belong in one, and the refusal comes from
the `NSURLComponents` backport underneath rather than from this code.
`-performBatchUpdates:completion:` always reports `finished` as YES: Apple's
completion says whether the animation ran to its end, and the Core Animation
transaction the port groups the updates in does not hand that back.

### Not carried, and why

Nothing here is a quiet stub. Where the behaviour cannot be produced, the API
is `absent`: the class is not there, the method is not there, and
`respondsToSelector:` answers honestly, so an application that asks first keeps
working on its own fallback path.

Four callbacks report a moment rather than a value - `-safeAreaInsetsDidChange`,
`-viewSafeAreaInsetsDidChange`, `-adjustedContentInsetDidChange` and
`-scrollViewDidChangeAdjustedContentInset:`. A value can be carried wherever
the release's own behaviour produces it; the moment it changes is produced by
UIKit's layout, and reaching it means standing in for `-layoutSubviews` across
every view of the process. The same reasoning takes out the layout guides -
`safeAreaLayoutGuide`, `contentLayoutGuide`, `frameLayoutGuide`: a guide is
useful because the layout engine keeps its frame current, and a guide whose
frame nothing updates is worse for an application than no guide at all, because
constraints to it would resolve and be wrong.

The attributes inside an accessibility string are the mild case of the same
thing: the four keys of this range carry the strings UIKit gives them, so an
application can build such a string at all, but this release's VoiceOver speaks
the text and knows nothing of pronunciation, pitch, queued announcements or
heading levels.

Some API only means anything if the release's own code understands it. The
leading and trailing content alignments of a control are decided inside
`UIControl` while it lays its content out; mapping them to left and right would
be quietly wrong in a right-to-left language, which this release does have.
Smart quotes, smart dashes and smart insert-and-delete are substitutions the
keyboard makes, and this keyboard has no such rule. `largeContentSizeImage` is
drawn only where an accessibility content size category is in force, and there
is none here. `systemMinimumLayoutMargins` and
`viewRespectsSystemMinimumLayoutMargins` describe a minimum this release never
produces, so any number the port invented would be an invention.
`hasUncommittedUpdates` reports on bookkeeping the release's table does not
keep. The swipe actions - `UISwipeActionsConfiguration`, `UIContextualAction`
and the two delegate methods that hand them over - are absent as a whole,
classes included: carrying the value types so that they could merely be created
would leave an application believing it had configured a swipe that never
happens, while with them missing it falls back to the release's own swipe to
delete.

A navigation bar's large title and its search bar are laid out by the bar
itself, a home indicator and the system edge gestures that defer to it do not
exist on this hardware, a colour named in an asset catalogue is read by a
CoreUI that knows no such file, the exemption from inverted colours has to
reach the render server, the password rules of a text field are read by a
keyboard that generates none, and `UIScreen.captured` is answered by a service
that watches recording and mirroring. Dragging, dropping and spring loading are
the same story with a service of their own.

Whole families go out for one reason each, and the registry names every class
and protocol in them rather than the family: everything that hangs off a drag
session (the previews, the items, the sessions and the delegates, the drop
side, the row and item level of a table or a collection view, and text
dragging, dropping and pasting), spring loading, the focus engine, and the
document browser with the file provider world behind it. Four accessibility
protocols of that release go out too, because the VoiceOver here never asks the
questions they answer.

Two loose constants of iOS 11 are carried instead of refused, for a reason
worth naming: `UIImagePickerControllerImageURL` and `UIActivityTypeMarkupAsPDF`
are strings an application writes into a dictionary or an array, and a missing
one becomes a `nil` key that raises. They carry the values UIKit gives them -
the second is a reverse-domain identifier, not its own name, which is why both
were read rather than assumed - and they make nothing happen: the picker of
this release never fills that key in, and its share sheet never offers that
activity.

The rest needs something the device does not run. Multipath TCP
(`multipathServiceType`) needs it in the kernel. `getFileProviderServicesForItemAtURL:`
needs a File Provider daemon. `NSUserActivity`'s `eligibleForPrediction`,
`persistentIdentifier` and the deletion of saved activities need the daemon that
keeps that store; there is nothing here to predict from and nothing to delete.

Two entries are `ignored` rather than absent, because the call never passes
through this package at all: `NSJSONWritingSortedKeys` is a number the compiler
writes into `+dataWithJSONObject:options:error:`, which this release already
answers and which ignores the bit, so the keys come out unsorted; and
`NSLocalizedFailureErrorKey` is carried in an error's user info untouched, since
honouring it would mean changing `-localizedDescription`, a method every release
already has.

`preferredRange` of an image renderer format chooses between a standard and an
extended colour range, and CoreGraphics of iOS 6 has no extended colour space at
all. No context it builds is of extended range, so the property could only
store a promise.

### How it is proved

Every implemented entry has a differential test under `tests/backports/host/`
that compiles these sources with the classes and functions renamed and the
categories attached under their own selector prefix, so the system's
implementation and the port run side by side in one process and the two answers
are compared. The safe area, the scroll view's adjusted content inset, the
directional margins and the font metrics were also checked on an iPhone 4S
running 6.1.3, through a tweak loaded into an application the phone already
has: forty-seven checks in one run, no failures. That run is where the font cache
of this release showed up - a font scaled to the size it already has comes back
as the same object, which no host can show.
