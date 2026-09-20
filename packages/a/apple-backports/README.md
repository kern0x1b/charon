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
the release is a single switch, off. Categories, actions and threads are kept and change
nothing: `UNNotificationAction`, `UNTextInputNotificationAction`,
`UNNotificationCategory`, `UNTextInputNotificationResponse` and
`UNNotificationServiceExtension` are there and inert, and the category set the
application registers is stored and read back. A repeat iOS 6 cannot follow - every 90 seconds, the 31st of every
month - is refused with an error rather than scheduled to fire on other dates.
The settings report what the application asked for, since iOS 6 tells it
nothing of what the user set. Attachments, location
triggers and the delivered notifications are absent: the
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

### WKWebView, over the UIWebView of the release, in a library of its own

`WKWebView` and the classes around it - the configuration, the preferences, the user
content controller with its scripts and message handlers, the navigation actions and
the back-forward list - are carried in `libWebKitBackports.dylib`, built with the
`webkit` config. The view holds a `UIWebView` and turns what that reports into what a
`WKNavigationDelegate` is sent, in the order WebKit sends it: the decision, the start,
the commit, the finish, with `URL`, `title` and `loading` observable. `evaluateJavaScript`
answers numbers, strings, dates, arrays, dictionaries, `nil` and the two errors as
WebKit does, and `window.webkit.messageHandlers` reaches the handlers. What the
`UIWebView` cannot tell is absent or inert and listed: a script at document start runs at
the end of the document, the response of a navigation is never offered to the delegate,
and a redirect, an authentication challenge and the UI delegate's panels never reach the
application. `facts/WebKit/WKWebView.md` has the whole table.

### LocalAuthentication, answered as a device with no fingerprint sensor

`LAContext` is carried in `libLocalAuthenticationBackports.dylib`, built with the `localauthentication` config. The devices
iOS 6 runs on have no biometric sensor and give an application no way to ask for the passcode, so it answers as a device
without a sensor: biometry is not available (`LAErrorBiometryNotAvailable`), the passcode cannot be asked for
(`LAErrorNotInteractive`), and an evaluation is answered with that error and never succeeds. An application that asks
first and falls back to its own passcode works; one that cannot do without the sensor says so. See
`facts/LocalAuthentication/LAContext.md`.

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

### Finding the cameras and microphones, in a library of its own

`AVCaptureDeviceDiscoverySession`, the device types of iOS 10 and `+[AVCaptureDevice defaultDeviceWithDeviceType:mediaType:position:]`
are carried in `libAVFoundationBackports.dylib`, built with the `avfoundation` config, so that only a port that looks for
cameras loads AVFoundation. They answer from the devices iOS 6 has: a camera is the wide angle one, the microphone is the
built-in one, and a search for a telephoto or a dual camera finds nothing.

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

### SafariServices, a page in bars of the application's own

`SFSafariViewController`, its configuration, its activity button and the prewarming token are carried in
`libSafariServicesBackports.dylib`, built with the `safariservices` config. The page is drawn by the `UIWebView` of the
release in the process of the application, under a navigation bar with the dismiss button and the address, over a toolbar
with back, forward, the action sheet, the button that opens the page in the browser and reload. What is asked of the
delegate, what is refused and with which words follow the system's (and `SFAuthenticationSession`, the sign-in session of iOS 11, takes the callback address from the page's navigation), held by `host/uikit2` (`safariviewcontroller`) and
run on an iPad 2 by `device/safariviewcontroller.m`; the cookies and passwords of Safari, Reader and the content blockers
are not shared, as `facts/SafariServices/SFSafariViewController.md` sets out.

## iOS 13 and 14

### Relative dates, in English

`NSRelativeDateTimeFormatter` writes the distance between two dates as "in 2 hours", "3 days ago", "yesterday", "next week",
in the numeric and named styles and the four unit styles, over the calendar of the formatter. It is written from the host's
own formatter: the fuzz differential agrees on 56000 answers, and 1600 recorded cases are held against the port on the
device. The words are English whatever the language of the device; the numbers go through the locale's number formatter.
See `facts/Foundation/NSRelativeDateTimeFormatter.md`.

### Scenes, over the one window an application has

`UIScene`, `UIWindowScene`, `UISceneSession`, `UISceneConfiguration`, the connection options, the URL contexts and their
options, the activation conditions, the request options, `UIStatusBarManager`, the scene notifications and the roles are
carried as a facade over the application's single window stack: one implicit scene, taken from the scene manifest of the
Info.plist or from the application delegate, connected after launch, and moved through its activation states by the
application's own notifications. `connectedScenes` holds it, `supportsMultipleScenes` is NO, and a request for a second
scene is answered with the error of a release that has none. `UIWindow(windowScene:)` makes a window of it and the scene
delegate's `window` is filled in for a storyboard. Not carried: state restoration by activity, Handoff, shortcut items and
CloudKit shares in the connection options, and the disconnect of the scene. See `facts/UIKit/UIScene.md`.

### Menus, context menus and previews, present so that applications launch

`UIMenuElement`, `UIAction`, `UIMenu` and `UIDeferredMenuElement`, the 45 `UIMenu...` identifiers,
`UIContextMenuConfiguration`, `UIPreviewParameters`, `UIPreviewTarget` and `UITargetedPreview` are carried as the value
objects they are: defaults, copies, equality, `-description`, secure coding and the exceptions they raise are held to the host's
own UIKit through Mac Catalyst (`tests/backports/host/uikit2`, the `menus` group), and the identifier constants string for
string. `UIMenuController` gets `-showMenuFromView:rect:`, `-hideMenuFromView:` and `-hideMenu` over the calls iOS 6 has.

What iOS 6 cannot do is not faked. It has no menu view, no preview morph and no highlight of the source view, so
`UIContextMenuInteraction` puts a long press on its view and shows the menu **as an action sheet**: elements that are disabled
or hidden are left out, inline submenus are flattened, other submenus open a second sheet, the first destructive element is the
sheet's red button, and the chosen action's handler runs. The delegate hears of the menu through an animator that runs added
animations at once, and the three preview callbacks and the preview provider are never called. Its `menuAppearance` is
compact, since a rich menu is the one with a preview. `UIMenuSystem` is there and **inert** - iOS 6 has no menu bar and no
key command menus to rebuild - and says so once in the log; `UIMenuBuilder` is absent, and `-buildMenuWithBuilder:` is never
called. `facts/UIKit/UIContextMenuInteraction.md` has the whole table, and `facts/UIKit/UIPreviewParameters.md` the one place
a value differs from the host: lines of text that touch are not joined into one outline.

### Corner curves, kept and drawn circular

`kCACornerCurveCircular`, `kCACornerCurveContinuous` and `CALayer.cornerCurve` are carried as the host has them: a layer is
circular until given continuous, and a value that is neither makes it circular again. iOS 6 rounds a corner with a circular
arc only, so a continuous curve is kept and drawn circular, and the first layer set to it says so in the log. See
`facts/QuartzCore/CALayerCornerCurve.md`.

### Background tasks, accepted by no scheduler

`BGTaskScheduler`, the refresh and processing requests and the task classes are carried in a library of their own, for an
application that registers launch handlers and submits requests. iOS 6 launches an application in the background for none of
them, so a handler for a permitted identifier is kept and never called, and a submission answers NO with the error the header
gives for scheduling that is not available (code 1), or not permitted (code 3) when the identifier or the background mode is not
listed in the Info.plist. There is no host framework to compare with; the device test holds the port to the headers. See
`facts/BackgroundTasks/BGTaskScheduler.md`.

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

`SecTrustEvaluateWithError` is carried over the release's own `SecTrustEvaluate`: the verdict is the newest Security's, and the error it makes says what the newest Security says for an untrusted root, a name that does not match and an expired certificate, read from the four English strings the release gives for a failed evaluation. A language in which the release words them differently gets the not trusted error. `SecCertificateCopyKey` and `SecCertificateCopySerialNumberData` come with it, in `libSecurityBackports.dylib`, built with the `security` config, so that a process which never evaluates a trust does not load Security for them.

`CGColorSpaceGetName`, `CGPathApplyWithBlock`, `CGImageGetByteOrderInfo`, `CGImageGetPixelFormatInfo`, `CGPDFArrayApplyBlock` and `CGPDFDictionaryApplyBlock`, the six functions that turn the code points of a video colour description into names and back (`CVColorPrimaries`, `CVTransferFunction` and `CVYCbCrMatrix`, each way) and the constants iOS 11 and 12 added beside them come in `libGraphicsBackports.dylib`, built with the `graphics` config, so that a process which reads none of them loads neither CoreGraphics nor CoreVideo for them. The tables are the iOS 12 ones: a code point that release names nothing for gets the string it makes, `ColorPrimaries#7`, and reads back. iOS 6 names a generic RGB space as the device one, so that is the name `CGColorSpaceGetName` answers for it. The outline and access permission keys of a PDF, the colour conversion object, the info pointer of a data provider and the colour space constants of 12.3 and 12.6 are absent, each with its reason in the registry.

`UIDragItem`, `UIDropProposal`, `UIDragInteraction` and `UIDropInteraction`, with the drag and drop delegates and switches of `UITableView` and `UICollectionView` and the drag hooks of their cells, are carried as the surface an application configures: everything is held and nothing ever begins, so no drag starts, no drop enters a view and no delegate is asked. `+[UIDragInteraction isEnabledByDefault]` answers NO on every device, an iPad included, where iOS 12 answers YES there.

`ASWebAuthenticationSession` is carried in `libAuthenticationServicesBackports.dylib`, built with the `authenticationservices` config, which brings `libSafariServicesBackports.dylib`: it is a wrapper over the `SFAuthenticationSession` of that library, as it is in iOS 12, and gives the callback URL, or an error of `ASWebAuthenticationSessionErrorDomain` with code 1 for a cancel. The credential provider and the credential identity store are absent. `facts/AuthenticationServices/ASWebAuthenticationSession.md`.

`NSPersistentHistoryChangeRequest` and the objects around it (`NSPersistentHistoryToken`, `NSPersistentHistoryTransaction`, `NSPersistentHistoryChange`, `NSPersistentHistoryResult`) are carried in `libCoreDataBackports.dylib` as what an application names and asks with: the request holds its date or token and result type as iOS 12 does, the abstract classes raise the exception iOS 12 raises, and no store of this release keeps a history, so nothing answers a request, `currentPersistentHistoryTokenFromStores:` answers `nil` and the remote change notification is never posted. `NSManagedObjectContext.transactionAuthor` is kept and read by nothing. `facts/CoreData/PersistentHistory.md`.

`PHPhotoLibrary` is carried in `libPhotosBackports.dylib`, built with the `photos` config, for its authorization only: `+authorizationStatus` is the `ALAssetsLibrary` status, `+requestAuthorization:` shows the system prompt through a read of the saved-photos group and gives the handler the new status, and the two calls with an access level of iOS 14 answer the same, never limited. Changes, observers, cloud identifiers and the history of changes are absent, as the release has no Photos database. `facts/Photos/PHPhotoLibrary.md`.

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
