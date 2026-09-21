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
Query generations are carried without a snapshot to read: a context can be pinned to the
current generation and reads the latest rows, as an in-memory store does in the newest
Core Data, because the store of iOS 6 keeps a rollback journal and no write-ahead log
(`facts/CoreData/QueryGeneration.md`).

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

### Pointers, hover, keys, search tokens and color wells, present so that applications launch

`UIPointerInteraction`, `UIPointerRegion`, `UIPointerRegionRequest`, `UIPointerStyle`, `UIPointerShape` and the four pointer effects,
`UIHoverGestureRecognizer`, `UIKey` with the `UIKeyInputHome`, `UIKeyInputEnd` and `UIKeyInputF1` to `UIKeyInputF12` strings,
the button, modifier and event members of `UIEvent`, `UIGestureRecognizer` and `UITapGestureRecognizer`, and
`UIButton.pointerInteractionEnabled` and `.pointerStyleProvider` are carried so that applications that link them launch. iOS 6 has no
pointing device, so what a pointer would do is **inert**: an interaction or a hover recogniser can be added to a view and never fires,
the delegate is never asked for a region or a style, no event has modifiers or buttons, and the first interaction and the first hover
recogniser say so once in the log. The values are the host's own to the last thing that can be asked - descriptions, equality, copies, the
hashes that follow from the values, the exceptions - held by the `pointer` and `pointercategories` groups of `tests/backports/host/uikit2`.
`UIPress.key` is absent, since `UIPress` is not on this release. See `facts/UIKit/UIPointerInteraction.md`, `UIPointerRegion.md`,
`UIPointerStyle.md`, `UIHoverGestureRecognizer.md`, `UIKey.md` and `UIPointerEvents.md`.

`UISearchTextField` and `UISearchToken` keep their tokens apart from the text, raise for a bad index with the system's own words and draw each token
as a plain rounded chip before the text; a backspace at the start deletes the last one. Positions count the text only, since a token is not a
character here, and tokens are not selected, copied or dragged. `UISearchBar.searchTextField` answers the search bar's own text field, extended at
run time with the token members, which are kept there and not drawn. `UISearchController.automaticallyShowsScopeBar` is kept and **inert**.
See `facts/UIKit/UISearchTextField.md`.

`UIColorWell` and `UIColorPickerViewController` are real, if small: the well draws a swatch and, when tapped, presents a picker of a 12 by 10 grid
of colors, an alpha slider and Done, which sets the well's color and sends value changed and tells the picker's delegate as the
system's does, continuously while a finger moves. There is no spectrum, eyedropper, saved color or hex entry. See `facts/UIKit/UIColorWell.md`.

### Compositional layouts, laid out by the release's own collection view

`UICollectionViewCompositionalLayout` and everything it is described with - `NSCollectionLayoutSection`, `Group`, `Item`,
the supplementary, boundary and decoration items, the dimensions, sizes, spacings and anchors, the layout's configuration and
the environments a section provider is given - are carried in full. iOS 6 has `UICollectionViewLayout` since 6.0, so the layout
is one more subclass of it: it solves the description into frames and answers the calls the collection view already makes. The
rules were **measured**, not read: the same description is laid out by the host's own layout under Mac Catalyst and by the
port's, in a collection view in a real window, and 182 fixed layouts (fractional, absolute and estimated sizes, every kind of
group, spacing, insets, edge spacing, supplementary, boundary and decoration items, pinned headers, several sections, scrolling
both ways) agree frame for frame with no tolerance; their answers are the expectations of `tests/backports/device/compositional.m`.
The value classes agree with the host on 139 statements - defaults, copies, equality, `-description`, exceptions.
`contentInsetsReference` of 14.0 is carried in an object of its own.

What iOS 6 cannot do is not faked. It has no nested scroll views, so a section with an `orthogonalScrollingBehavior` other than
none is **laid out as an ordinary section**, its behavior and its `visibleItemsInvalidationHandler` kept and the handler never
called, and the first one says so in the log; those two are `inert`. It asks a cell nothing about its size, so an estimated dimension is
laid out at its estimate, and says so once. `-[NSCollectionLayoutGroup visualDescription]` is absent, and so is anything of a later
release. `facts/UIKit/UICollectionViewCompositionalLayout.md` has every rule and the few places where a very odd description is
not held to the host's answer.

### Corner curves, drawn as a mask

`kCACornerCurveCircular`, `kCACornerCurveContinuous` and `CALayer.cornerCurve` are carried as the host has them: a layer is
circular until given continuous, and a value that is neither makes it circular again. iOS 6 rounds a corner with a circular arc
only, so a clipping layer set to continuous gets a mask of the continuous corner shape over its circular clip, within 1.5% of the
area the system covers. See `facts/QuartzCore/CALayerCornerCurve.md`.

### The spring and the display link of Core Animation

`CASpringAnimation` is the release's own class - the armv7 caches of iOS 6.0 and 6.1.3 already carry it, privately, with its mass,
stiffness, damping and velocity - so `initialVelocity` and `setInitialVelocity:` are carried as iOS 9 carries them, one call to
`velocity` and `setVelocity:`, and `settlingDuration` as `durationForEpsilon:` with 0.001: the closed form below critical damping
and, at or above it, the system's own walk in steps of 0.1 second over a critically damped spring, held to the host's answers
over 32 named springs and 4000 random ones. A spring that cannot settle answers `MAXFLOAT`. See
`facts/QuartzCore/CASpringAnimation.md`.

`CADisplayLink.targetTimestamp` is the timestamp plus the duration of a display frame times the frame interval, the expression
iOS 12 ends in one instruction. `CADisplayLink.preferredFramesPerSecond` is kept beside the link and sets the release's own frame
interval to `max(1, round(1 / (frame duration * rate)))`, as the newer release does; it starts at zero, the documented default,
and reads back as 60 divided by the frame interval where an application moves the interval itself. The port leaves
`setFrameInterval:` alone, so an interval that is not a divisor of 60 stays where the application put it. See
`facts/QuartzCore/CADisplayLink.md`.

### Background tasks, accepted by no scheduler

`BGTaskScheduler`, the refresh and processing requests and the task classes are carried in a library of their own, for an
application that registers launch handlers and submits requests. iOS 6 launches an application in the background for none of
them, so a handler for a permitted identifier is kept and never called, and a submission answers NO with the error the header
gives for scheduling that is not available (code 1), or not permitted (code 3) when the identifier or the background mode is not
listed in the Info.plist. There is no host framework to compare with; the device test holds the port to the headers. See
`facts/BackgroundTasks/BGTaskScheduler.md`.

### Bar appearances, values on their own and applied where iOS 6 can draw them

`UIBarAppearance`, `UINavigationBarAppearance`, `UIToolbarAppearance`, `UITabBarAppearance`, `UIBarButtonItemAppearance`
and `UITabBarItemAppearance`, with their state objects, are carried as the value objects they are, against the host's own
UIKit: the defaults, which of them are set and which are only defaults, how a button or a tab item state falls back to the
normal one, the copies, the equality, the description and a secure archive are held to the host's answers over thousands of
random sequences of changes. What differs is written in `facts/UIKit/UIBarAppearanceValues.md`: the system colours are
plain light colours, a back indicator has no default image to answer, and the archive is the backport's own.

The bars apply them. `standardAppearance` of a `UINavigationBar`, a `UIToolbar` and a `UITabBar`, and `compactAppearance` of
the first two, become what iOS 6 has: a solid or an image background through `setBackgroundImage:forBarMetrics:`, a
hairline shadow, the title attributes turned into the keys of iOS 6, the button and tab item attributes and images on the
appearance proxies, the compact one on the landscape metrics. What iOS 6 cannot draw is kept in the object and
recorded in the facts: the blur, the large title, the badge, the layout of the tab items. The scroll edge appearances and the
appearances of a navigation item or a tab item are applied too: the bar watches the content scroll view of its view
controller by key-value observing and takes the scroll edge appearance at the top (the bottom, for a tab bar and a toolbar)
and the standard one elsewhere, and takes the appearance of its top item, or of the selected tab item, while that item
is shown, as the SDK's comment orders them. The subtitle attributes of iOS 26 and the override
interface style of iOS 27 are absent. The buttons reach every bar of the class in the application, not one bar, and
`facts/UIKit/BarAppearanceApplication.md` says why and what a device still has to prove.
### Symbol configurations, and symbols the port draws

`UIImageConfiguration` and `UIImageSymbolConfiguration` are carried as the immutable value objects they are - the factories, `configurationByApplyingConfiguration:`, the
four `without...` methods, traits, `isEqualToConfiguration:`, hash, description and secure coding - and `UIImageSymbolWeightForFontWeight()` with its inverse, all held to the host's own
UIKit through Mac Catalyst (`tests/backports/host/uikit2`, the `symbols` group). `UIImage` gets `symbolConfiguration`, `isSymbolImage`, `imageByApplyingSymbolConfiguration:` and the baseline,
`UIImageView` a `preferredSymbolConfiguration` that re-draws a symbol image with it.

iOS 6 has no SF Symbols, so `+[UIImage systemImageNamed:...]` **draws its own**: a small language of paths of the port's, with the system's naming grammar (`.fill`, `.circle`, `.slash`, `.badge.plus`, ...),
answers a template image for 549 names - the 251 that ten corpus applications name and 298 common ones - at the size, alignment insets and baseline the host gives (within a point, all names, eight configurations),
with the stroke following the weight, the size the scale, point size or text style. The drawings are held to the host's by the overlap of the two bitmaps (median 0.70, minimum 0.10; fine line
drawings are the low end); any other name is nil, as an unknown name is on the host, and `facts/UIKit/UIImageSymbols.md` lists the names the host knows that are not drawn yet.
Where the port differs from the host, `facts/UIKit/UIImageSymbolConfiguration.md` and `facts/UIKit/UIImageSymbols.md` say so: a font from `+preferredFontForTextStyle:` has no text style to give,
a symbol weight below zero is Regular where the host reads the memory beside its table, and a symbol image is `AlwaysTemplate` where the host's is `Automatic`.
### The difference of two collections, and diffable data sources

`NSOrderedCollectionDifference` and `NSOrderedCollectionChange`, with `-differenceFromArray:`, `-arrayByApplyingDifference:`, their ordered set
counterparts and `-applyDifference:`, are carried as the system's are: 320000 random differences of arrays and ordered sets, with every
option, an equivalence test and the calls it received, and the exceptions of the ones built from changes and index sets, none differing from the
host's (`tests/backports/host/uikit2`, the `orderedcollections` group). The shortest edit script is the Myers algorithm walked forward, so the
indexes match, and the difference of two ordered sets is not the same algorithm but a walk of both with a cursor each, which keeps fewer elements and is
the system's. `facts/Foundation/NSOrderedCollectionDifference.md`.

`NSDiffableDataSourceSnapshot`, `UICollectionViewDiffableDataSource` and `UITableViewDiffableDataSource` build on it. The snapshot, with its
exceptions and their reasons, is held to the system's over 50000 operations per run; the data sources are the view's data source and give a
collection or table view one batch of inserts, deletes, moves and reloads per snapshot applied, the reloads in a second batch, and are run
beside the system's in a window (the `diffabledatasource` group). They answer the same counts, index paths and identifiers after every apply,
and a batch the port cannot prove consistent for iOS 6 - items moving between sections, section changes mixed with item changes - is a `reloadData`, losing the animation. The apply is synchronous on the main queue.
`NSDiffableDataSourceSectionSnapshot`, `-applySnapshot:toSection:animatingDifferences:` and `-snapshotForSection:` come with iOS 14; the handlers
for reordering and for expanding are **inert** and say so once in the log, and the transaction classes are absent, since iOS 6 has no interactive
reordering and no outline cell. The members of iOS 15 are not answered. `facts/UIKit/NSDiffableDataSourceSnapshot.md`,
`NSDiffableDataSourceSectionSnapshot.md`, `UICollectionViewDiffableDataSource.md`, `UITableViewDiffableDataSource.md`.

### Lists and cell configurations, laid out from what the host measured

`UIListContentConfiguration`, `UIBackgroundConfiguration`, the configuration states, `UIListContentView`, the `UICellAccessory` family,
`UICollectionViewListCell`, `UICollectionLayoutListConfiguration` with the list section and layout, the cell registrations and the
configuration of collection view cells, table cells and table headers are carried in full. The values come from the host's UIKit under Mac
Catalyst, so the margins and sizes are those of the Mac idiom: the port follows them, except the row estimate of a list layout, which is 44
and not the host's 40.04. This release has no self sizing cells, so a row stays that high. The swipe actions of the providers of a list slide the row and run their handlers, the outline disclosure expands and collapses the items of a section
snapshot and calls the handlers of the data source, and the reorder grip drags a row, with an interactive movement of the collection view built on the
release that has none (`UICollectionViewInteractiveMovement.md`); the data source is told of each step of a drag as it happens, and not once at the end. Not carried:
the background decoration item, the blur and shadow of a reordering row, `selectionFollowsFocus` and the system colour transformers (`absent`). Members of iOS 15 and later
(`configurationUpdateHandler`, `isPinned`, `separatorConfiguration`) are not answered. Facts: `facts/UIKit/UIListContentConfiguration.md`
and its neighbours; the entries are in `registry/UIKit/ios14lists.json`.

### Commands, actions and menus on controls, appearance traits, dynamic colours and the rest of what UIKit added

`UICommand`, `UICommandAlternate` and a `UIKeyCommand` that is one are carried as the host has them (defaults, equality, copies, exceptions, archive: the `commands` group), and
`UIActivityItemsConfiguration` with an `UIActivityViewController` made of it. What a control does with an action is real, not present: `addAction:forControlEvents:`,
`removeAction:...`, `enumerateEventHandlers:`, `sendAction:` and every initialiser with a primary action work on any `UIControl` through proxy targets, the primary action
is registered for the event that triggers it on this release (touch up inside, value changed, editing did end on exit), and a button, a bar button item and a segmented control
made of actions and menus run them; a menu of a button or a bar button item is shown as the action sheet of the context menu interaction, and so is the menu a table row or
collection view item asks for by its delegate. Tables and collection views get their interaction when the delegate is set, so `contextMenuInteraction` is never nil. The
answers are held to the host's in processes that do not share the port's code (`controlactions`, `controlmenus`, `listmenus`); what differs is in
`facts/UIKit/UIControlActions.md` and `UIControlMenus.md`: the pairs and the actions of `enumerateEventHandlers:` do not interleave, a menu as a primary action shows on touch up
inside and not on touch down, and a bar button item's `target` and `action` are the port's.

The four appearance traits and `+currentTraitCollection` are carried with the trait collection, held to the host over 2434 checks: the screen is light, normal, base and active,
and `performAsCurrentTraitCollection:` nests. Dynamic colours and the 25 semantic colours are real too, with a limit that is not a difference the tests can see: a dynamic colour
is a colour of the release with its provider beside it, so what reads it - a view, a label, `CGColor` - reads the light value, and only `resolvedColorWithTraitCollection:` reads
another. The host's palette is the Mac's, so only the colours it shares with iOS 13 (the link, the fills, the grays) are held to it; the rest is Apple's published iOS 13 table
(`facts/UIKit/UIColorDynamic.md`).

`viewIsAppearing:`, `textFieldDidChangeSelection:`, the unwind segue question of iOS 13, the orientation message of a window scene delegate, `UITextInteraction` (tap, double tap, triple
tap and long press on a text input, with no handles or loupe), `-replaceRange:withAttributedText:`, `showCGGlyphs:...`, `imageWithTintColor:` (drawn byte for byte as the host does),
baselines, `+imageNamed:inBundle:withConfiguration:`, five system images the port draws itself, `UIBarButtonItem`'s space items and the monospaced system font are real. Kept
and read back with nothing reading them - `inert`, each said once in the log - are what belongs to a device or a service iOS 6 has none of: the large content viewer, the Apple
Pencil's scribble, the screenshot service, the font panel, the pointer lock, the override of the interface style, the modal that resists dismissal, the page control's images, the
date picker's compact and inline styles (it draws wheels, and says so in `datePickerStyle`), the font picker (it cannot hand back a descriptor that iOS 6 does not have and offers
Cancel), the pattern detection of the pasteboard (no pattern found), and a handful of properties that belong to the Mac idiom. `NSToolbar`, the columns of a split view
controller, the storyboard creators, the document picker of content types and the accessibility name of a colour are absent; the delegate methods of things that do not fire are
declared and never sent. `facts/UIKit/UIRestAbsent.md` gives the reason for each.

## iOS 11 and 12

These two releases are read differently from the ones before them. The last
firmware with a 32-bit slice is 10.3.4, so there is no armv7 implementation of
anything iOS 11 added; the behaviour is read from arm64 - from 11.0 and 12.0
themselves, where the calls still go through `objc_msgSend` and the selectors
can be read, and from 16.0 and 18.0 for the numbers a later release corrected -
and the code here is written anew for armv7 and armv7s. What a facts file under
`facts/` names is what was read; nothing in this range was carried over from an
older implementation.

### Foundation of iOS 13 and 14, carried and held against the host

145 names of Foundation are decided in `registry/Foundation/ios13found.json`: 119 carried, 2 inert and 24 absent.
Carried: the error-returning `NSFileHandle` methods, `NSData` compression (ZLIB, LZ4 and LZMA in both directions;
LZFSE as stored blocks only, since compressed LZFSE has no public specification), `NSListFormatter`,
`NSUnitInformationStorage`, the `NSByteCountFormatter` measurement forms, `-[NSHTTPURLResponse valueForHTTPHeaderField:]`,
the secure collection decoders of `NSCoder` and `NSKeyedUnarchiver`, `NSOperationQueue` barriers and progress,
`NSURLSessionWebSocketTask` (an RFC 6455 client), expensive and constrained network access, `NSHTTPCookie` SameSite,
`NSURLCache` with a directory URL, the new URL resource keys, and the small members (`NSDate.now`, the post-order
enumerator flag, `macCatalystApp`, `iOSAppOnMac`, `targetContentIdentifier`). Inert: `NSURLContentTypeKey` and
`NSURLFileContentIdentifierKey` answer no value. Absent: the `NSXPC` members, which cannot work without a service an
iOS 6 application can ship, the TLS version bounds and the transaction metrics properties. The facts are in
`facts/Foundation/`; the proof is the `foundation14*` groups of `tests/backports/host/uikit2/run.sh` and
`tests/backports/device/foundation14.m`.

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

The five key functions of iOS 10 - `SecKeyCreateRandomKey`, `SecKeyCopyPublicKey`, `SecKeyCreateEncryptedData`, `SecKeyCreateDecryptedData` and `SecKeyCopyExternalRepresentation` - are carried in `libSecurityBackports.dylib` over what iOS 6 already has. The release generates the pair itself with `SecKeyGeneratePair` and reads its own `kSecAttrIsPermanent`; the public key of a private one is the release's private `SecKeyCopyPublicBytes` followed by `SecKeyCreateFromPublicData`, which divides RSA from elliptic curve by the key's own algorithm identifier, so the port names no encoding of its own; and the algorithm of iOS 10 becomes the padding of `SecKeyEncrypt` and `SecKeyDecrypt` for the three the release can do - raw, PKCS1 and OAEP with SHA-1. Every other algorithm is refused with NULL and a CFError of `errSecParam` that names it, because iOS 6's OAEP carries no choice of digest and answering an OAEP-SHA256 call with SHA-1 padding would be a different cipher text under the name of the one that was asked for. `SecKeyCopyExternalRepresentation` answers a private key's PKCS#1 representation only where the release really keeps one, which the port parses before it trusts it, and the public one only where the key is proven to be public; where the release keeps neither the answer is a CFError, never the public half in place of a private key. Every error is domain `NSOSStatusErrorDomain` with the release's own OSStatus. `facts/Security/SecKey.md`.

`SecTrustEvaluateWithError` is carried over the release's own `SecTrustEvaluate`: the verdict is the newest Security's, and the error it makes says what the newest Security says for an untrusted root, a name that does not match and an expired certificate, read from the four English strings the release gives for a failed evaluation. A language in which the release words them differently gets the not trusted error. `SecCertificateCopyKey` and `SecCertificateCopySerialNumberData` come with it, in `libSecurityBackports.dylib`, built with the `security` config, so that a process which never evaluates a trust does not load Security for them.

`CGColorSpaceGetName`, `CGPathApplyWithBlock`, `CGImageGetByteOrderInfo`, `CGImageGetPixelFormatInfo`, `CGPDFArrayApplyBlock` and `CGPDFDictionaryApplyBlock`, the six functions that turn the code points of a video colour description into names and back (`CVColorPrimaries`, `CVTransferFunction` and `CVYCbCrMatrix`, each way) and the constants iOS 11 and 12 added beside them come in `libGraphicsBackports.dylib`, built with the `graphics` config, so that a process which reads none of them loads neither CoreGraphics nor CoreVideo for them. The tables are the iOS 12 ones: a code point that release names nothing for gets the string it makes, `ColorPrimaries#7`, and reads back. iOS 6 names a generic RGB space as the device one, so that is the name `CGColorSpaceGetName` answers for it. The outline and access permission keys of a PDF, the colour conversion object, the info pointer of a data provider and the colour space constants of 12.3 and 12.6 are absent, each with its reason in the registry.

`UIDragItem`, `UIDropProposal`, `UIDragInteraction` and `UIDropInteraction`, with the drag and drop delegates and switches of `UITableView` and `UICollectionView` and the drag hooks of their cells, are carried as the surface an application configures: everything is held and nothing ever begins, so no drag starts, no drop enters a view and no delegate is asked. `+[UIDragInteraction isEnabledByDefault]` answers NO on every device, an iPad included, where iOS 12 answers YES there.

`ASWebAuthenticationSession` is carried in `libAuthenticationServicesBackports.dylib`, built with the `authenticationservices` config, which brings `libSafariServicesBackports.dylib`: it is a wrapper over the `SFAuthenticationSession` of that library, as it is in iOS 12, and gives the callback URL, or an error of `ASWebAuthenticationSessionErrorDomain` with code 1 for a cancel. The credential provider and the credential identity store are absent. `facts/AuthenticationServices/ASWebAuthenticationSession.md`.

`NSPersistentHistoryChangeRequest` and the objects around it (`NSPersistentHistoryToken`, `NSPersistentHistoryTransaction`, `NSPersistentHistoryChange`, `NSPersistentHistoryResult`) are carried in `libCoreDataBackports.dylib` as what an application names and asks with: the request holds its date or token and result type as iOS 12 does, the abstract classes raise the exception iOS 12 raises, and no store of this release keeps a history, so nothing answers a request, `currentPersistentHistoryTokenFromStores:` answers `nil` and the remote change notification is never posted. `NSManagedObjectContext.transactionAuthor` is kept and read by nothing. `facts/CoreData/PersistentHistory.md`.

`PHPhotoLibrary` is carried in `libPhotosBackports.dylib`, built with the `photos` config, with the classes it reads and changes the library through, all over the `ALAssetsLibrary` of the release: `PHAsset`, `PHAssetCollection`, `PHCollectionList`, `PHFetchOptions`, `PHFetchResult`, `PHImageManager` and `PHCachingImageManager` with their option classes and keys, `PHAssetChangeRequest` and `PHObjectPlaceholder`. `+authorizationStatus` is the `ALAssetsLibrary` status, `+requestAuthorization:` shows the system prompt through a read of the saved-photos group, and the calls with an access level of iOS 14 answer the same, never limited. A fetch is empty until the application is authorized; then it returns the assets and albums of the release in order of date, with the predicate, sort descriptors and limit applied, an image comes from the thumbnail, the full-screen image or the full-resolution image of the asset, drawn to the size and content mode asked for, and a video is an `AVURLAsset` on its address. `-performChanges:completionHandler:` and `-performChangesAndWait:error:` add an image or a video to the saved photos, with its date and location written as image metadata; deleting, editing an asset, a favorite and a hidden asset fail the whole change with `PHPhotosErrorChangeNotSupported` before anything is written. What the release cannot tell is not made up: no favorites, hidden assets, bursts, media subtypes or modification dates, and the smart albums other than the camera roll, the videos and the empty favorites, hidden and bursts are not made. Observers, cloud identifiers, the history of changes, live photos, content editing and the asset resources are absent. `facts/Photos/Assets.md`, `facts/Photos/ImageManager.md`, `facts/Photos/Changes.md`, `facts/Photos/PHPhotoLibrary.md`.

The rest of Photos and of PhotosUI is absent, each row in `registry/Photos/absent_Photos.json` and `registry/PhotosUI/absent_PhotosUI.json`: the resource managers, live photos, content editing, the change requests for collections and the persistent changes need the Photos database, and nothing in iOS 6 does their work. `PHPhotoLibrary`, `PHAdjustmentData`, `PHContentEditingInput` and `PHContentEditingOutput` are declared by the headers of both frameworks, and are decided once, in the file of Photos, so the difference of PhotosUI alone shows those four classes as undecided.

`GCController`, `GCMouse` and `GCKeyboard` are carried in `libGameControllerBackports.dylib`, built with the `gamecontroller` config, for what an application asks before there is a device: `+[GCController controllers]` and `+[GCMouse mice]` are empty, `+current` and `+coalescedKeyboard` are nil, the discovery ends at once and calls its handler on the main queue, and the notification names exist and are never posted. No device is ever attached, so no object of these three classes exists, and their mouse and keyboard members are absent. The names of the inputs, keys and haptics of iOS 14 are carried as strings and key codes, with the values of the host's GameController. What software can make is carried whole: `+controllerWithExtendedGamepad` and `+controllerWithMicroGamepad` make a controller that is a snapshot, with the extended or micro gamepad, its buttons, axes and direction pads, the motion, `-capture` and the state copies, and the handlers of the elements are called on the handler queue as the host calls them; the port is held to the host's GameController over a random sequence of 4000 values (8576 lines, none differs). `GCColor` and `GCEventViewController` are carried whole, and the classes of the Xbox, DualShock and DualSense profiles, the touchpad, the light, the battery, the haptics and the keyboard and mouse inputs are carried for what names them, with no object of them ever made. The snapshots and their data functions, the virtual controller and the physical input protocols of iOS 16 stay absent. `facts/GameController/GameController.md`, `facts/GameController/ControllerModel.md`.

`NSBatchDeleteRequest` and `NSBatchDeleteResult`, with the `-[NSManagedObjectContext executeRequest:error:]` that runs them, are carried in `libCoreDataBackports.dylib`. The removal is done in a private context on the same coordinator, which leaves the calling context as iOS 12 does but runs delete rules and validation and posts a did save notification, which iOS 12 does not; a fetch request or a save request given to `executeRequest:error:` is executed by the release's own coordinator. `facts/CoreData/BatchDelete.md`.

`kSecAttrSynchronizable` and `kSecAttrSynchronizableAny` are carried in `libSecurityBackports.dylib`, as the strings `sync` and `syna`; the keychain of iOS 6 ignores the attribute, so an item marked synchronizable stays on the device and a query for either finds the items of the device. `kSecUseAuthenticationUI` and `kSecAttrTokenID` are not carried, as the release refuses them with -50. `facts/Security/kSecAttrSynchronizable.md`.

`NSFetchIndexDescription`, `NSFetchIndexElementDescription` and `NSEntityDescription.indexes` are carried and checked the way iOS 12 checks them, and not applied: the store of this release builds no index from them, which the documentation of `indexes` allows. `NSCoreDataCoreSpotlightDelegate` is absent, since there is no Core Spotlight. `facts/CoreData/FetchIndex.md`.

`MTLCreateSystemDefaultDevice` is carried in `libMetalBackports.dylib`, built with the `metal` config, and answers nil, as Metal does where the hardware has no driver: iOS 6 runs on the A4 and A5, so an application that falls back to OpenGL ES when it is given no device does so. The rest of Metal and MetalKit is absent. `facts/Metal/MTLCreateSystemDefaultDevice.md`.

`NSQueryGenerationToken`, `-[NSManagedObjectContext queryGenerationToken]` and `-setQueryGenerationFromToken:error:` are carried without a snapshot to read (see the container above), and `NSConstraintConflict` is carried as a value that nothing here makes, since the store of iOS 6 enforces no uniqueness constraint; `uniquenessConstraints` and the merge policy that resolves the conflicts are absent. `facts/CoreData/QueryGeneration.md`, `facts/CoreData/ConstraintConflict.md`.

`+[AVCaptureDevice authorizationStatusForMediaType:]` and `+requestAccessForMediaType:completionHandler:` are carried in `libAVFoundationBackports.dylib`: iOS 6 asks nobody for the camera or the microphone, so the microphone is authorized and the camera is authorized unless ManagedConfiguration says the camera is restricted, the request never shows a prompt, and a media type other than audio or video raises as iOS 12 does. The rest of AVFoundation and AVKit that iOS 6 lacks is absent, each row in `registry/AVFoundation/absent_AVFoundation.json` and `registry/AVKit/absent_AVKit.json`. `facts/AVFoundation/AVCaptureDeviceAuthorization.md`.

CoreGraphics of iOS 6 already exports `CGPathAddRoundedRect`, the `CGColorCreateGeneric...` functions, `CGColorGetConstantColor` and seven `kCGColorSpace...` names, and the registry records them as the release's own, held to the host's CoreGraphics by `tests/backports/device/coregraphics7.m`. `CGColorSpaceCreateWithName` makes a space for `kCGColorSpaceGenericRGB`, `...Gray` and `...CMYK` only, and answers NULL for `kCGColorSpaceSRGB` and the other names it exports, so a bitmap context made with an sRGB space by name is NULL. `libGraphicsBackports.dylib` carries `CGColorSpaceCopyICCData` (the release's `CGColorSpaceCopyICCProfile`) and `CGColorSpaceUsesExtendedRange`, `CGColorSpaceIsHDR`, `CGColorSpaceUsesITUR_2100TF`, `CGColorSpaceIsHLGBased` and `CGColorSpaceIsPQBased`, which answer NO for every space, as the release makes none of those. The names of the spaces it does not export are absent. `facts/CoreGraphics/CGColorSpace.md`.

The rest of ImageIO and CoreVideo that arrived after iOS 6 is absent, each row in `registry/ImageIO/absent_ImageIO.json` and `registry/CoreVideo/absent_CoreVideo.json`; iOS 6 exports `CGImageSourceCopyMetadataAtIndex`, the eight `kCGImageMetadataNamespace...` names, `kCGImagePropertyPNGCompressionFilter` and `kCGImageSourceSubsampleFactor` itself, which the registry records as the release's own. `facts/ImageIO/ImageIOExports.md`.

The rest of MetalPerformanceShaders, CoreML, Vision, CallKit, MediaPlayer, JavaScriptCore, LocalAuthentication, SafariServices, QuartzCore and Security that arrived after iOS 6 is absent, each row in `registry/<Framework>/absent_<Framework>.json`, decided once in the framework that owns it where two headers declare it. The C names that iOS 6 already exports itself are recorded as the release's own: thirteen of the JavaScriptCore C API (`facts/JavaScriptCore/JavaScriptCoreExports.md`) and five of Security (`facts/Security/SecurityExports.md`).

The eleven `CTRadioAccessTechnology...` names and `CTRadioAccessTechnologyDidChangeNotification` are carried in `libCoreTelephonyBackports.dylib`, built with the `coretelephony` config, with `CTTelephonyNetworkInfo.currentRadioAccessTechnology`: iOS 6.0 has none of them, and iOS 6.1.3 exports all the names but WCDMA and keeps the technology in a private class, whose string is spelled `CTRadioAccessTechnologyWCMDA` for WCDMA, so the property answers the string with the value iOS 7 gives, and nil on iOS 6.0. The per-service dictionaries of iOS 12, the delegate of iOS 13, `CTCellularData` and the two 5G names are absent. `facts/CoreTelephony/CTRadioAccessTechnology.md`.

`libSecurityBackports.dylib` carries what iOS 8 and 9 added to the keychain as names and answers of a release that has none of it: the constants `kSecAttrAccessControl`, `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`, `kSecUseOperationPrompt`, `kSecUseNoAuthenticationUI`, `kSecSharedPassword`, `kSecUseAuthenticationContext` and `kSecUseAuthenticationUI` with its three values, which the keychain of iOS 6.1.3 refuses with -50 (`errSecParam`) as it refuses any key it does not know; `SecAccessControlCreateWithFlags`, which answers NULL with `errSecUnimplemented`; `SecAddSharedWebCredential`, whose block gets that error; `SecRequestSharedWebCredential`, whose block gets an empty array and no error; and `SecCreateSharedWebCredentialPassword`, which makes `xxx-xxx-xxx-xxx` as the host's Security does. `kSecAttrTokenID` and the Secure Enclave value stay absent. `facts/Security/KeychainAccessControl.md`.

`libAccelerateBackports.dylib`, built with the `accelerate` config, carries `vImageBuffer_Init`, `vImageBuffer_InitWithCGImage` and `vImageCreateCGImageFromBuffer` of iOS 7 over the release's CoreGraphics, for the 8-bit RGB formats (32 bits with alpha first or last, premultiplied or not or skipped, in the three byte orders; 24 bits), held to the host's vImage by `tests/backports/host/accelerate7` and `tests/backports/device/accelerate7.m`, with the differences that `facts/Accelerate/vImageBuffer.md` lists: a NULL colour space is the device RGB space, other formats answer `kvImageInvalidImageFormat`, and the rows are padded to 16 bytes. It also carries the 420 Y'CbCr conversions of iOS 8 that the corpus asks for - the four `kvImage_*Matrix_ITU_R_*` constants with the coefficients the newer release holds, the two `_GenerateConversion` functions over an opaque structure of the port's own, the four conversions between `ARGB8888` and `420Yp8_CbCr8`/`420Yp8_Cb8_Cr8`, and `vImageExtractChannel_ARGB8888`. The arithmetic is the one the header writes out, in `float` where the system works in fixed point: 4262 of 457920 bytes differ from the system's by exactly one and none by more, over four pixel ranges, both matrices, four sizes and four permutations, and the port's byte is the correctly rounded one. A Y'CbCr type outside the two 420 8-bit ones is refused with `kvImageUnsupportedConversion`, which the system carries and the port does not. `facts/Accelerate/vImageYpCbCr.md`. `vImageConvert_RGB565toBGRA8888`, `vImageConvert_BGRA8888toRGB565`, `vImageConvert_ARGB16UtoRGB16U` and `vImageConvert_ARGBFFFFtoRGBFFF` of iOS 7 come with them, byte for byte the system's answers - the arithmetic of the five and six bit channels is the integer one the header writes out, and the other two drop the first channel of each pixel. A destination larger than the source is `kvImageRoiLargerThanInputBuffer` in all four, which is what the release answers although the header's comment above the 565 expansion names another code. `facts/Accelerate/vImagePixels.md`. `libGraphicsBackports.dylib` carries `kCIInputAngleKey`, `kCIInputRadiusKey` and `kUTTypeScalableVectorGraphics` as their strings. `facts/CoreImage/InputKeysAndSVG.md`.

`CAMetalLayer` is carried in `libMetalBackports.dylib`, as a layer that keeps its device, pixel format, drawable size and the rest of what it is given, and has no drawable: `nextDrawable` is nil and `preferredDevice` is nil, since iOS 6 has no Metal, so an application that asks for a drawable falls back to OpenGL ES; a maximum of drawables outside 2 to 3 raises the exception of iOS 12. The properties of iOS 16 are kept and used for nothing, and `CAEDRMetadata` is absent. `facts/QuartzCore/CAMetalLayer.md`.

`PHPickerViewController`, `PHPickerConfiguration`, `PHPickerFilter` and `PHPickerResult` are carried in `libPhotosBackports.dylib` over the release's `UIImagePickerController`, which the controller holds as a child for the media types of the filter: one item at most (a `selectionLimit` of more is kept and not honoured), an image offered as JPEG or, by the address the release gives it, PNG, GIF or TIFF, made from the image the picker returns, a video offered as the file the picker made, and `assetIdentifier` nil; the filters of iOS 15 and 16 and the selection of iOS 15 are absent. `UIImage` reads and writes itself through `NSItemProvider` as in iOS 11, in `libUIKitBackports.dylib`. `facts/Photos/PHPicker.md`, `facts/UIKit/UIImageItemProvider.md`.

`UIVisualEffectView` with a `UIBlurEffect` blurs what lies behind it, for real and not live: the view draws the layers of its window into a bitmap a quarter of the size, blurs it with a box filter, raises its saturation and mixes the tint of its style in, and shows the picture behind its content view, again about ten times a second while what is behind changes; the picture cannot hold what the window draws with OpenGL ES, and vibrancy is not carried. `facts/UIKit/UIVisualEffect.md`.

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

`NSLinguisticTagger` gets its units: word, sentence, paragraph and document
across `tokenRangeAtIndex:unit:`, the enumeration, the tags, the class
conveniences and `dominantLanguage`. Words are tagged by iOS 6's own tagger;
above the word only the Language and Script schemes answer, from the words of
the unit, where iOS 12 also gives lexical classes and lemmas. See
`facts/Foundation/NSLinguisticTagger.md`. `+[NSOrthography
defaultOrthographyForLanguage:]` stays absent: it is a table of about 250
languages inside iOS 12.

`SecCopyErrorMessageString` answers the sentence for a status from a table of
534 English texts carried in the Security library; a status the table lacks reads
`OSStatus` and its number, as it does in iOS 12. The language of the device is not
honoured. See `facts/Security/SecCopyErrorMessageString.md`.

Core Data's batch update and asynchronous fetch are carried, both executed with
`-executeRequest:error:`: a batch update sets the values of what its predicate finds, with
the keys and values checked as iOS 12 checks them; an asynchronous fetch answers its result at
once, fetches in a context of its own and delivers to its block on the context's queue, with a
progress when there is a current one, and cancels. Neither writes SQL the way the release does:
the objects are set and saved in a context of their own, so the model's rules apply to what a
batch update sets. `+mergeChangesFromRemoteContextSave:intoContexts:` brings a context up to
date afterwards. See `facts/CoreData/BatchUpdate.md`, `AsynchronousFetch.md` and `RemoteMerge.md`.

The port's `NSURLSession` waits for connectivity and delays requests as iOS 11 does: `waitsForConnectivity` and
a background session make a task that begins with no network say so through
`URLSession:taskIsWaitingForConnectivity:` and begin when it comes back, `earliestBeginDate` delays the tasks of
a background session and `willBeginDelayedRequest` lets the delegate continue, replace or cancel them. The size hints
`countOfBytesClientExpects...` are kept and read by nothing. See `facts/Foundation/NSURLSessionConnectivity.md`.

`NLTokenizer` and `NLLanguageRecognizer` of NaturalLanguage, with the 57 `NLLanguage` constants, are carried in
the Foundation library: words, sentences and paragraphs come from the release's `CFStringTokenizer` with the
attributes and emoji sequences of the system, and the recognizer votes sentence by sentence with the release's tagger.
The scripts the release cuts with a smaller dictionary (Chinese) and the probabilities of the recognizer differ, and
the rest of the framework (`NLTagger`, `NLModel`, embeddings) is not carried. See
`facts/NaturalLanguage/NLTokenizer.md` and `NLLanguageRecognizer.md`.

The path monitor of Network is carried in the Foundation library: `nw_path_monitor_*`, `nw_path_*` and `nw_interface_*`
of iOS 12, over the reachability of iOS 6, so that `NWPathMonitor` and `NWPath` have something to stand on. It reports
the path when it starts and when it changes, on the queue it was given, and says satisfied, unsatisfied or
satisfiable, the interface (`en0`, or cellular and expensive) and the addresses. Connections and the rest of Network are
not carried. See `facts/Network/NWPathMonitor.md`.

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
