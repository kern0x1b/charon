# Backport tests

## Host

Differential tests against the host's own classes. Each script compiles the
backports for macOS (UIKit ones through Mac Catalyst) with every class they
define renamed, and compares the result with the system class on the same
inputs.

    sh host/url/run.sh
    sh host/session/run.sh      starts host/session/server.py on a free 127.0.0.1 port
    sh host/alert/run.sh
    sh host/layout/run.sh
    sh host/foundation2/run.sh  writes device/foundation2-expectations.h when it passes
    sh host/uikit2/run.sh
    sh host/keyedarchive11/run.sh  writes device/keyedarchive11-expectations.h when it passes
    sh host/foundation11/run.sh    writes device/foundation11-expectations.h when it passes
    sh host/validatedformat/run.sh [pairs] [seed]
    sh host/validatedformat/run.sh --mutants [pairs] [seed]
    sh host/fuzz/run.sh percentencoding|stringcase|calendar [rounds] [seed]
    sh host/directionaledges/run.sh  writes device/directionaledges-expectations.h when it passes
    sh host/directionalmargins/run.sh
    sh host/contentsize/run.sh
    sh host/fontmetrics/run.sh
    sh host/systemspacing/run.sh
    sh host/gesturename/run.sh
    sh host/rendererformat/run.sh
    sh host/batchupdates/run.sh
    sh host/interactions/run.sh
    sh host/traitstyle/run.sh
    sh host/animatorscrub/run.sh
    sh host/usernotifications/run.sh  writes device/usernotifications-expectations.h when it passes
    sh host/coredata/run.sh
    sh host/probes/run.sh
    sh host/swipeactions/run.sh
    sh host/registry/run.sh <dyld_shared_cache_armv7>
    sh host/blocks/run.sh
    sh host/textcontent/run.sh
    sh host/avcapture/run.sh
    sh host/oslog/run.sh  writes device/oslog-expectations.h when it passes
    sh host/imageflip/run.sh
    sh host/ios1516/run.sh  writes device/ios1516-expectations.h when it passes
    sh host/cachereader/run.sh <dyld_shared_cache> <image> <class> <selector>

`host/oslog/run.sh` runs the same 61 calls through the host's os_log, asked for its
developer output, and through the port's formatter, and compares the two texts; the calls both
platforms can make become the expectations of the device test.

`host/avcapture/run.sh` runs the discovery of capture devices, their types and the
default device against the host's own, through Mac Catalyst, over every combination of
types, media type and position; the microphone is compared on the device only.

`host/textcontent/run.sh` compares the 23 text content type constants and the
`textContentType` of a text field, a text view and a search bar with the host's own,
through Mac Catalyst.

`host/blocks/run.sh` runs the port's timers, threads and run loop blocks in one
process with the system's own, compiled with the selectors prefixed, and compares
what each does and raises; `host/imageflip/run.sh` does the same for the flipped
image through Mac Catalyst.

`host/uikit2/run.sh` also runs the `appearances` group: random sequences of changes on the six bar appearance classes,
and the bars that apply them, compared with the host's own, and it writes `device/appearances-expectations.h` when it passes.

`host/uikit2/run.sh` also runs a group that needs a window - the snapshots of a view, for one -
as an application: its `windowed` function builds the group with `windowed.m`, which is `main`, a scene delegate and
a window, into a Mac Catalyst bundle with `windowed.plist`, signs it ad hoc and runs it, and the group's
`charon_windowed_run(window)` is called once the window is up. A test written for it compares the system's answers with
the backport's the way the others do, for whatever UIKit will not do without a scene.

The `menus` group of `host/uikit2/run.sh` compares the menu elements, the menu identifiers, the context menu configuration and
interaction at rest, the preview parameters, target and targeted preview with the host's, and the `menucontroller` group holds the
two calls the new `UIMenuController` methods make to the old interface. `device/menus.m` is the device counterpart: it checks that the
classes and constants come from `libUIKitBackports.dylib` and repeats the checks that need no window.

The `symbols` group of `host/uikit2/run.sh` compares `UIImageConfiguration`, `UIImageSymbolConfiguration`, the two weight functions, the symbol members of `UIImage` on ordinary
images and `UIImageView.preferredSymbolConfiguration` with the host's, over generated configurations and every pair of them; `device/symbols.m` checks on the device that the
classes and functions come from `libUIKitBackports.dylib`, the value behaviours, and that `systemImageNamed:` answers nil.

`host/registry/run.sh` holds the build's check of the registry to a release's own
Objective-C metadata. The build refuses an `absent` entry whose class, method,
accessor or protocol the release carries, and an `ignored` entry the release
does not carry, within the releases the entry covers. The script gives the check
entries made up for the purpose, against the cache it is passed, and needs no
device.

`host/foundation2/run.sh` runs the cases of `device/foundation2-cases.m`, the
ones the device runs, against the host's Foundation and against the renamed
backports, compares the two and embeds the host's answers in
`device/foundation2-expectations.h`; it attaches the categories itself
(`host-attach.c`), since the host linker leaves `__objc_catlist` alone.

A test that attaches categories under a prefix at run time only renames the
methods it calls. If one method of the port calls another method the port also
carries, by an ordinary message, the host answers that call with its own
implementation, and the port's code never runs. `host/prefix_selectors.py`
closes that. It reads each source through clang's syntax tree and renames both
the port's method definitions and the messages sent to them, with their ARC
family kept, for example `initWith…` becoming `initCharonHostWith…`. The tests
then attach the renamed categories as they are. `foundation2`, `foundation11`,
`keyedarchive11`, `systemspacing`, `gesturename`, `batchupdates` and
`directionalmargins` are built this way. In the four UIKit ones the tool renames
the definitions and nothing else: no method there calls another the port
carries.
`host/keyedarchive11/run.sh` holds the iOS 11 keyed archiving API to the host's
own: it runs `device/keyedarchive11-cases.m` twice in one process, once against
the system's methods and once against the backport's, renamed by
`host/prefix_selectors.py` and attached by `host/foundation2/host-attach.c`, and compares the two
answer by answer. It writes `device/keyedarchive11-expectations.h` only when
every answer agrees. What it holds the backport to, beyond the obvious round
trip: `-encodedData` returns the archiver's own mutable buffer and the same
object every time, it answers for an archiver made with
`-initForWritingWithMutableData:` instead of raising, and an archive whose root
is missing or `nil` fails with `NSCoderValueNotFoundError`, not with
`NSCoderReadCorruptError`.

`host/foundation11/run.sh` does the same for the rest of the iOS 11 and 12
Foundation batch: reading and writing a property list through a URL,
`percentEncodedQueryItems`, `-decodeValueOfObjCType:at:size:` and
`NSSecureUnarchiveFromDataTransformer`. It renames the transformer's class as
well as attaching the categories, so the system's transformer and the
backport's stand side by side in one process. Among the answers it holds the
backport to: the error for a property list of the wrong kind is
`NSFileReadCorruptFileError` with the text naming the URL, a mutable receiver
reads a mutable array, a query item keeps its escapes, and the transformer
raises Apple's own wording for data that is not data and for a class that is
not allowed. It also holds the validated format to the host's: which formats
pass against which allowed specifiers, and the message for the ones that do
not. The matching rule itself was read off the running implementation - three
thousand random pairs of format and allowed specifiers, where the two agreed
on every verdict and every message - rather than out of CoreFoundation's
format parser.

`host/directionaledges/run.sh` holds `NSDirectionalEdgeInsets` to the host's
UIKit through Mac Catalyst: the text the insets format to, everything the
parser accepts and everything it refuses, the encoding the value carries, and
the bytes the coder writes with secure coding on and off.

`host/directionalmargins/run.sh` holds the directional layout margins to the
host's UIKit: which of the two projections wins when each is set last, and how
both read in either writing direction. It ends with a note rather than a check
for the one case the port cannot follow — a direction changed after the
directional margins were set, which would need `-layoutMargins` itself.

`host/contentsize/run.sh` holds the two content size category functions to the
host's: all one hundred and sixty-nine ordered pairs, the accessibility answer
for every category and for nil, and the exception an arbitrary string earns.

`host/fontmetrics/run.sh` holds `UIFontMetrics` to the host's UIKit at the
default content size category, which is the only category iOS 6 has: the
rounding to the display scale, the `maximumPointSize` cap, a custom font
keeping its family, the answer being a new object, and the wording of the
refusal when the font is `nil`.

`host/validatedformat/run.sh` fuzzes the validated format of `NSString`. It
compiles the port into the test under other selectors, puts random pairs of
format and allowed specifiers to the host's Foundation and to the port, and
compares their verdicts and messages. Where the arguments are the ones the
allowed string describes, it also compares every character of the output. Each
pair runs in a process of its own, since the host's formatter itself can crash
on a pair whose arguments it misreads. This method once slipped through the Foundation tests: its entry points
called the host's own initializer, so the port's check never ran on the host.
The port now does its work in one static function, and the fuzzer calls it
directly.

The pairs and the arguments come from a seeded generator, and the run prints
its seed, so `run.sh <pairs> <seed>` repeats it. The integer and float arguments
are drawn per pair, since a fixed argument hid three wrong strings for as long
as it was 7. Every fifty pairs the fuzzer switches a random half of what it can
write on or off - positionals, flags, widths, stars, precisions, lengths, odd
specifiers, `%P`, text, text outside ASCII, `%%`, an unfinished `%` - so a rare
combination is not always drowned by the common ones. A quarter of the pairs go
through the localized form. When a pair differs, the fuzzer cuts both strings
down, a piece at a time, for as long as they still differ, and prints the
smallest pair next to the one it found: `[%1$D%c] against [%D]` instead of
forty characters. Each pair runs in a child process that sends the host's answer
before it asks the port, so a crash of the host's formatter is counted apart,
and a crash of the port is a difference like any other.

`run.sh --mutants` checks the fuzzer itself. Each line of `mutants.txt` names a
rule of the port and a Perl substitution that breaks it; the script builds the
port with that one change, runs the fuzzer over it with a fixed seed, and says
`caught` with the smallest pair, `MISSED` when the fuzzer passes a broken port,
and `STALE` or `BROKEN` when the change no longer applies or no longer
compiles. It exits non-zero on anything but `caught`.

`host/fuzz/run.sh` runs one of three fuzzers against the host's Foundation:
`percentencoding` (percent encoding and the URL character sets, Base64 of
strings and data), `stringcase` (localized case, containment and transforms,
tried under `en_US` and `tr_TR` so a locale-blind rule shows up), and
`calendar` (the `NSCalendar` and `NSDateComponents` methods of iOS 8). Each
draws its inputs from a seeded generator and prints the seed, so a run can be
repeated with `run.sh <fuzzer> 0 <seed>`. Every difference is filed under a
category, one per method or option, and the first three of each are printed.
The host is newer than any release the port follows, so a difference is not by
itself a bug in the port: a category listed in `host/fuzz/tolerated/<fuzzer>.txt`,
with the reason on the same line after a tab, is counted but does not fail the
run. Any other category does.

`host/fuzz/run.sh --mutants <fuzzer> [rounds] [seed]` checks a fuzzer the way
`validatedformat`'s does: `mutants/<fuzzer>.txt` names, one per line, a rule of
the port and a Perl substitution that breaks it, over a private copy of
Foundation built for that one run; the script says `caught` with the category
the run failed under, `MISSED` when the broken port still passes, and `STALE`
or `BROKEN` when the change no longer applies or no longer compiles.

`host/probes/run.sh` holds the capability probes of DeviceCheck, ARKit and CoreNFC
to the host's own frameworks, which it reaches through Mac Catalyst since ARKit
and CoreNFC are not native on the Mac. The five sources are compiled with their
classes and constants renamed, and the port and the frameworks answer side by
side: the shared object and `-isSupported` of `DCDevice`, `+isSupported` of every
configuration, `+readingAvailable` of both sessions, the class each one derives
from, and the strings of the three error domains. What the host cannot answer
the same way is left to the device test: it has a daemon and hands out a token,
where the port answers an error. The settings and session calls the port leaves
out are checked to be absent, since the host has them.

`host/swipeactions/run.sh` holds `UIContextualAction` and `UISwipeActionsConfiguration` to the
host's UIKit through Mac Catalyst, with the two classes renamed: what an action holds, the
colour each style gives it and the one it gets back from nil, the copies it makes and the
one it does not, and a configuration that keeps the array it was given as it is.

`host/systemspacing/run.sh` holds the system spacing of a layout anchor to the
host's UIKit, comparing the whole shape of the constraint each method returns -
items, attributes, relation, multiplier, priority and the constant the spacing
ends up in. It covers the eight points between ordinary edges at four
multipliers, the three relations on both axes, the baseline spacing over five
pairs of font sizes, a baseline against an edge, two views with no font at all,
and an edge of the container. It ends with a note for the one combination the
port does not reproduce: a baseline of a text view under the baseline of a view
with no font.

`host/rendererformat/run.sh` holds the preferred formats and
`+formatForTraitCollection:` to the host's UIKit. It compiles the renderer
format classes renamed together with the categories, and compares what each
factory answers: its class, bounds, scale, whether it is opaque and whether it
prefers an extended range. The trait collections cover nil, empty, six display
scales on both sides of the two epsilons the releases have used, each display
gamut, a scale with a gamut, and a size class alone. A last check, for the port
alone, hands it an object that answers a display scale and not a display gamut,
as the trait collections of iOS 6 to 9 do, and expects the scale taken and the
gamut left unspecified.

`host/gesturename/run.sh` holds the name of a gesture recognizer to the host's:
that it starts empty, that it is copied rather than held, that clearing it
works, and that two recognizers keep their own. It notes the one thing the port
cannot do - the system prints the name inside `-description`, which belongs to
the release.

`host/animatorscrub/run.sh` is the contract for the two flags iOS 11 added to
`UIViewPropertyAnimator`, a class of the iOS 10 range: the defaults, where the
flag may be set and where setting it raises, what scrubbing does to an animator
built with animations, built without, paused and running, and what an animator
that pauses on completion does when its time has passed - it stays active and
not running, and holds its completion blocks until the application finishes it.
It fails until the class carries them; the properties answer `NO` before that,
because the class is the SDK's own interface under another name and the compiler
synthesises what nobody wrote, so every check is behaviour rather than
`respondsToSelector:`.

`host/usernotifications/run.sh` sets the notification values and triggers
beside the system's UserNotifications: what a trigger refuses and with what
text, the next date of every trigger through the triggers' own
`-nextTriggerDateAfterDate:withRequestedDate:` on 5760 fixed dates, a content
fresh, filled, copied, set to nil and archived both ways, requests, sounds and
the members of later releases the class must not answer. When it passes it
writes the device's expectations.

`host/traitstyle/run.sh` is the contract for the user interface style of a
trait collection, iOS 12 API on a class of the iOS 7-10 range: it runs one
script against UIKit's own collection and the same script against the port's,
and compares the style a collection is built with, what a collection of a scale
alone and of nothing at all answer, five merges, equality and hash against an
empty collection, four containment questions, the description, the copy, an
archive round trip, and the collection a screen is given. It fails until the
port carries the API, which is the point: the numbers in it are what the port
has to match.

`host/interactions/run.sh` covers two things a view holds for somebody else:
the list of `UIInteraction`s, and the attributed strings of accessibility. It
runs one script against UIKit's own implementation and the same script against
the port under its host names, and compares every answer - which interaction is
told what and when, the order of the list, the copy the getter hands out, the
three exceptions the current implementation raises for a `nil` argument, and
how an attributed label and a plain one stand for one value. The loose constants the port carries for this range are compared with UIKit's
own strings, values included, and the VoiceOver notification is compared with
the deprecated name it replaced as well - being the same string is the whole
reason it works here.

`host/batchupdates/run.sh` runs the same sequence of table updates twice, once
through the system's `-performBatchUpdates:completion:` and once through the
backport's, and compares the whole order of what happened: the update block
running inside the call, the completion arriving only after the run loop turns,
one completion per call, `nil` blocks and an empty block accepted, a nested
call, and the rows left after inserting, deleting and moving.

`host/uikit2/run.sh` renames selectors as well as classes, so a test holds a
backported method and the system one side by side, and checks the spring curve
against a real CASpringAnimation, which needs AppKit and so runs as a plain
macOS tool. What each of its tests holds the backport to:

- `spring_uikit.m` prints the spring UIKit itself builds for
  `+[UIView animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:]`;
  `spring_ours.m` compares the spring the backport solves for with it and writes
  the samples `spring_sample.m` checks against a real CASpringAnimation. A layer
  has a presentation layer only inside a window, so that part is the plain macOS
  tool, and the sample at the very end of an animation is left out, where Core
  Animation has already removed the animation and shows the model value.
- `motion_test.m`: Mac Catalyst answers nil for every motion effect, so the
  backport is held to the rules the UIKit headers state - the viewer offset runs
  from -1 to 1, the horizontal type maps -1 to the minimum relative value and the
  vertical type maps a downward tilt to it, a group adds the values of its
  effects, and the view applies the result to its layer.
- `sizes_test.m`: every content size category of the backport against the string
  the system's own constant holds, and that no two of them are the same string.
- `tint_test.m`: iOS 7 states that `-tintColor` returns the first colour set in
  the superview chain, that a dimmed adjustment mode greys the colour it returns,
  and that `-tintColorDidChange` reaches the views that inherit the colour.
- `bars_test.m`: on iOS 6 the tint colour of a bar is the colour of the bar
  itself, which is what iOS 7 calls the bar tint colour, so the backport keeps
  the value it was given and hands it to the iOS 6 tint colour.

## Device

The device tests run on an emulated iOS 6.0 (iPhone3,1). Until Charon runs the
emulator itself, a test is built by hand against the 6.0 band of the package
and started by the emulator lab:

    clang -target armv7-apple-ios6.0 -isysroot SDK -fuse-ld=LD64 -fobjc-arc -Idevice \
        device/url.m device/check.m -LBAND -lFoundationBackports -framework Foundation -o url
    ldid -S url BAND/*.dylib

and the libraries reach `/usr/lib/charon/org.charon.apple-backports/` of the
emulated root filesystem the way a device gets them: the data of
`org.charon.apple-backports_<revision>_iphoneos-arm.deb` unpacked into it and its
postinst run with `DPKG_ROOT` set to it.

- `mechanism.m`, `url.m`: a process of their own, Foundation only; they print
  `ok`/`FAIL` lines and exit with the number of failures. `url.m` includes
  `url_expectations.h`, the host's results that `host/url/run.sh` writes there
  when it passes, so the device is held to the same answers.
- `session.m` with `session-scenarios.m`: started from a LaunchDaemon on a full
  boot, with `host/session/server.py` running on the host and its port as the
  second argument (`session session PORT`); it writes
  `/private/var/backports/session.log` and `session.done`.
- `foundation2.m` with `foundation2-cases.m`: a process of their own, the second
  Foundation batch; it holds each case to `foundation2-expectations.h` and
  names, for every backported method, the image its implementation comes from,
  so a method the release already has is never taken from the library.
- `webkit.m` with `webkit-cases.m`: an application, the WebKit batch: a `WKWebView` over the `UIWebView` of the release
  is put through loads, history, decisions, JavaScript, scripts and messages, and every answer is held to what the
  system's `WKWebView` did in `webkit-expectations.h`, which `host/webkit/run.sh` records under Mac Catalyst. It needs
  the package built with `webkit = true`; three records that differ for a stated reason are tolerated by name.
- `localauth.m`: a process of its own, the LocalAuthentication batch: a context answers as a device with no fingerprint
  sensor and no way to ask for the passcode - the questions fail with the system's errors, an evaluation is answered
  off the main thread and never succeeds. The behaviour a device shares with the host is held to it by the
  `localauth` group of `host/uikit2/run.sh`. It needs the package built with `localauthentication = true`.
- `searchcontroller.m` with `searchcontroller-cases.m`: an application, the search controller of iOS 8 put through its
  presentation, its delegate's messages, typing, cancelling and the navigation item that holds it, and every answer
  held to what the system's `UISearchController` did in `searchcontroller-expectations.h`, which
  `host/searchcontroller/run.sh` records in an application under Mac Catalyst; nine records differ for a stated reason
  the test names.
- `itemprovider.m` with `itemprovider-cases.m`: a process of its own, `NSItemProvider` and `NSExtensionItem` put through
  what each type and each class asked for answers, the load handlers, the errors, a provider of a file, the
  representations of data and files, and objects, and every answer held to what the system's classes did in
  `itemprovider-expectations.h`, which `host/itemprovider/run.sh` records under Mac Catalyst. The behaviour that does not
  depend on the UTI database is also held by the `itemprovider` and `itemproviderbuiltins` groups of `host/uikit2/run.sh`.
- `ios1516.m`: a process of its own, what iOS 15 and 16 added that the port carries: `NSUUID`'s `compare:`, held to the answers
  `host/ios1516/run.sh` writes into `ios1516-expectations.h` after holding the port's method to the host's own, the
  orientation update of a view controller and the padding above a section header.
- `corelocation.m`: a process of its own, the CoreLocation batch: the circular region as a class, its notify flags,
  and the answers of the class methods about monitoring and ranging. It needs the package built with
  `corelocation = true`; it is checked on the emulated 6.0 and on the iPad 2, where location services and region
  monitoring are on and the emulator has no location daemon, so what depends on the daemon is compared with the
  release's own `+regionMonitoringAvailable`, not with a number.
- `tolerance.m`: a process of its own, the timer tolerance, which is a property
  and two CoreFoundation functions.
- `uikit2.m` (`uikit2-Info.plist`): an application for the second UIKit batch -
  the traits, the tint colour, the motion effects, the spring animation, the
  notification settings and the bar appearances. Where the environment cannot
  answer a check - an emulator delivers no device motion for the gyroscope - it
  prints a `skip` line with the reason instead of a verdict. Its controller
  answers NO to `-shouldAutorotate`, since iOS 6 ignores
  `-[UIApplication setStatusBarOrientation:animated:]`, which the traits step
  turns the status bar with, while the top-most full screen controller
  autorotates.
- `keyedarchive11.m` with `keyedarchive11-cases.m`: a process of its own for the
  iOS 11 keyed archiving API. It holds each case to
  `keyedarchive11-expectations.h`, names the image every backported method comes
  from, and checks the one thing the host cannot show: that a second
  `-finishEncoding` on iOS 6 neither raises nor touches the archive, which is
  what `-encodedData` stands on.
- `foundation11.m` with `foundation11-cases.m`: a process of its own for the
  rest of the iOS 11 and 12 Foundation batch, held to
  `foundation11-expectations.h`. Besides the cases it shares with the host, it
  names the image every backported method comes from and checks that the
  transformer answers to its name through `+[NSValueTransformer valueTransformerForName:]`.
- `security12.m`: a process of its own for `SecTrustEvaluateWithError`, `SecCertificateCopyKey` and
  the serial number of a certificate. It holds the trust evaluation to what the newest Security
  answers - the verdict, the domain, the code, the description and the underlying error - for a
  trusted certificate, an untrusted root, a name that does not match, an expired certificate
  and the combinations of them, and the same file, compiled against the host's own Security,
  passes all twenty-four of its checks, so the expectations are the host's answers and not
  ours. It links `libSecurityBackports.dylib`. It ran on an iPad 2 (6.1.3): twenty-seven checks and
  no failure.
- `tail11.m`: a process of its own that links UIKit, for the small rows that answer
  the same on every device: `-[NSProcessInfo thermalState]` answers nominal and its
  notification is never posted, the export presets of the image picker are kept per
  picker and the video one is copied, the key `UIImagePickerControllerPHAsset` carries
  its own name, and what is absent stays absent. It also holds the four volume keys
  of iOS 11 to what an iPad 2 answers - success and no value for a key it does not
  know, the available capacity for the important usage key - the refusal of a
  pattern that names a group, and `-trashItemAtURL:resultingItemURL:error:`
  answering the feature unsupported error, and the swipe action classes, whose
  answers it holds to those of the host. It ran on an iPad 2 (6.1.3): 52 checks
  and no failure; the log lines of the two `inert` answers came once each.
- `probes.m`: a process of its own for the capability probes, run on an
  iPhone 4S and an iPad 2 (6.1.3). It checks that every class the probes carry
  comes from `libFoundationBackports.dylib`, that `+isSupported` and
  `+readingAvailable` answer as the facts say, the hierarchy, the domains, and
  the one thing no host can show: `-generateTokenWithCompletionHandler:` is
  not answered before it returns, is answered from a background queue with
  `DCErrorFeatureUnsupported` and no user info, and a `nil` handler is ignored.
  It also checks that what is absent answers no to `respondsToSelector:` and
  `NSClassFromString`. The last full run answered 72 checks and no failure on
  each device.
- `directionaledges.m` with `directionaledges-cases.m`: a process of its own
  for `NSDirectionalEdgeInsets`, held to `directionaledges-expectations.h`. The
  structure's encoding is checked for its own name rather than against the
  host's, since `CGFloat` is a float on the device and a double on the host.
- `safearea-tweak.m`: the safe area and the directional layout margins, which
  need a real window and so run inside a running application rather than one of
  their own: it is a MobileSubstrate tweak filtered to Preferences, which
  `killall Preferences` restarts without a respring. It makes a window of its
  own below the normal level, checks forty-seven answers against what the
  algorithm read out of UIKit 11.0 says they must be - the safe area, the
  scroll view's adjusted content inset, the directional margins and
  `UIFontMetrics`, which shares the run because it needs the device's screen
  scale and its font cache - writes
  `/private/var/backports/safearea.log` and `safearea.done`, and hides its
  window again. Six of the checks are that `-safeAreaInsetsDidChange`,
  `-viewSafeAreaInsetsDidChange`, `-safeAreaLayoutGuide`,
  `-adjustedContentInsetDidChange`, `-systemMinimumLayoutMargins` and
  `-viewRespectsSystemMinimumLayoutMargins` are **not** there, since the port
  does not declare what it cannot deliver. The scroll view checks need a safe
  area that is not zero on any edge, which is why they run here and not on the
  host: the window gives `{30, 5, 15, 20}`, and each behaviour is held to the
  edges the algorithm says it keeps. The folder has to
  exist and be writable by the application first:
  `mkdir -p /private/var/backports && chmod 777 /private/var/backports`. Every
  check writes its own line to the log, since a tweak must not touch the
  application's `stdout`: a failure that only printed would be lost. The last
  full run answered `ok checks=47 failures=0` on an iPhone 4S (6.1.3, armv7).
  Three of those checks are not about the safe area at all: they ask the
  release's own visual format parser what it does with the iOS 11 spacing
  option, which is a question only a real iOS 6 can answer.
- `sblaunch/`: `charon-sblaunch`, one way to start an application on either
  device without `uiopen`, which has twice left the iPhone 4S to its watchdog.
  It takes one argument, the bundle identifier, the way the `sblaunch` already
  installed on the 4S does, and asks SpringBoard through
  `SBSLaunchApplicationWithIdentifier`, which it looks up with `dlsym` rather
  than linking a private framework.
  - Exit codes: 0 when the launch is accepted; 1 with SpringBoard's code, and
    whether the screen is locked, on standard error when it is refused; 2 for a
    wrong argument; 3 when the function is missing.
  - SpringBoard refuses a caller without the entitlement
    `com.apple.springboard.launchapplications`: without it the call returns 1
    even from root. `sblaunch.entitlements` carries it.
  - Build it with Charon's daemon rule, which installs it as
    `/usr/libexec/charon-sblaunch`, and sign it with `charon.entitlements`
    pointing at `sblaunch.entitlements`, relative to the project that builds
    it.
  - The iPad 2 has no `sblaunch`, and on 19 September 2026 this launcher
    started Preferences there and on the iPhone 4S alike.
- `uikit11/`: a MobileSubstrate tweak filtered to Preferences, for the iOS 11
  UIKit members that need a running application. It replays five host tests
  on the device: `interactions`, `systemspacing`, `gesturename`,
  `batchupdates` and `contentsize`.
  - Each host test's `differential.m` is compiled into the tweak unchanged: its
    `main` is renamed, its `printf` goes into the tweak's log through
    `capture.h`, and `alias.m` gives every method of the backport libraries
    the `charonHost` names the tests call their port side by.
  - On iOS 6 the system side of every test is the port. Each answer is held to
    the host's, which `refresh.sh` runs the host tests to write into
    `uikit11-expectations.h`.
  - A few answers depend on the release, and the tweak checks those against
    the release instead. These are the baselines of system spacing, which
    follow the formula with the device's fonts and the attributes its anchors
    give, and the moment a batch update's completion arrives, which is checked
    after the handler returns.
  - It also reads the back button a real `UINavigationBar` draws for each way
    of setting `backButtonTitle`: on every release this package supports, the
    property is UIKit's own.
  - Build it with Charon's tweak rule and `-fobjc-arc`, with `host/` and this
    folder on the include path and `capture.h` included first
    (`-include capture.h`). Launch Preferences with `sblaunch
    com.apple.Preferences`. It writes `/private/var/backports/uikit11.log`,
    one line per check, and `uikit11.done`. The last run on an iPhone 4S
    (6.1.3) answered `PASS`.
- `alert.m`, `layout.m`: applications (`alert-Info.plist`, `layout-Info.plist`)
  launched from SpringBoard; they write `/private/var/backports/NAME.log` and
  `NAME.done`, and `alert.m` logs a `SCREENSHOT <label>` line and pauses before
  each state worth a snapshot. `layout.m` holds a table of the system
  UIStackView's frames written by `host/layout/expectations.m`.
- `animator.m` also measures what scrubbing costs, since the answer only means
  something on the slowest hardware the port runs on. It times a scrub step
  three ways - an empty loop, freezing the layer, and rebuilding the animation,
  which is what the port does - and holds the last to one display frame. On an
  iPhone4,1 the three came out at 0.1, 4.4 and 109.2 microseconds against a
  frame of 16666.7. Reading the presentation layer needs `[CATransaction flush]`
  and a turn of the run loop first: before the first commit there is no
  presentation layer and the model value is what comes back.
  It also reads where a quarter of the fraction puts a view on an ease-in-out
  curve, which is the one thing `scrubsLinearly` changes and only a window
  shows: a quarter of the way when the animator scrubs linearly, and short of
  it, where the curve says, when it does not.
- `usernotifications.m`: a process of its own for the notification values and
  triggers. It holds 5760 next dates of calendar triggers, in five zones and
  around changes of clocks, to `usernotifications-expectations.h`, which
  `host/usernotifications/run.sh` writes from the system's own triggers when it
  passes; a zone whose rules changed after 2013 is not among them, since iOS
  6.1.3 keeps the rules of 2013.
- `notifications.m` (`notifications-Info.plist`): an application for the center,
  launched with `sblaunch` since it needs a running `UIApplication`. It asks for
  authorization, adds, replaces and removes requests, reads back what iOS 6 was
  given - the body and no title - checks which repeats are taken and which
  refused, and waits for a notification to arrive while it is in front.
- `avcapture.m`: a process of its own for the discovery of capture devices, linking
  `libAVFoundationBackports.dylib`. It holds a discovery session to the devices the
  release lists, by type, media type and position, in the order of the types, and
  the default device, the device types and the exception for a nil type to what was
  read off 10.3.4.
- `textcontent.m`: a process of its own for the text content types. It holds the 23
  constants to the strings read off iOS 10.3.4, and the property of the three views
  to its defaults and its copying. A process cannot make a text field, which needs a
  running application, so it uses instances that are allocated and not initialized;
  `host/textcontent` runs the same on real views.
- `oslog.m`: a process of its own for `os_log`. It calls the macros the way a program built for iOS 6
  does, on a battery of formats that `host/oslog` has run through the host's own os_log and embedded in
  `oslog-expectations.h`, and reads the messages back from ASL to compare them with the host's text, with the level and the
  facility they arrive at, and with what must not arrive.
- `blocks.m`: a process of its own for the block methods of `NSTimer`, `NSThread`
  and `NSRunLoop` and for `temporaryDirectory`, linking the backports library. It
  holds the timers, the thread and the run loop to what the host's own Foundation
  answers in `host/blocks`, the exception texts included.
- `imagescreen.m`: a process of its own for `-imageWithHorizontallyFlippedOrientation`
  and `maximumFramesPerSecond`. It flips all eight orientations, keeps the insets
  and rendering mode, and asks the release for the refresh interval the frame
  rate is worked out from.
- `coredata.m`: a process of its own for the Core Data container, linking
  `libCoreDataBackports.dylib`. It loads a SQLite store and, asynchronously, an
  in-memory one, inserts, fetches in and out of a context's block, saves in a
  background task and waits for the view context to merge it.
- `haptics.m`: a process of its own for the feedback generators, linking UIKit
  but raising no window. It holds the port to what was read off iOS 10 rather
  than to a sensation: that the three generators are there and come from the
  backports library, that `UISelectionFeedbackGenerator` is declared and its `-selectionChanged` does nothing,
  that a style outside the three still builds a generator and simply plays
  nothing instead of raising, that the iOS 13 `-impactOccurredWithIntensity:` is
  not answered, and that every call returns without raising. It says nothing
  about how hard the motor turns: that was measured on an iPhone4,1 with the
  accelerometer and is written down in
  `packages/a/apple-backports/facts/UIKit/UIFeedbackGenerator.md`, since an
  emulated device has no motor and every call there plays nothing.

## Checking an application against a release and the backports

`tools/check-app.lua` says, for a built armv7 binary, what stays unresolved on a
release and why. It asks the build's own import check what the binary imports
that neither the release's shared cache nor the backports' libraries export,
and sorts the answer into the imports the backports carry - which are
unresolved only because the binary binds the stock library first, and are cured
by linking `libUIKitBackports.dylib` or `libFoundationBackports.dylib` before it
or by retargeting the weak binding - and the imports nothing carries, which are
what a port is still missing.

    CHARON_ROOT=/path/to/charon xmake l tests/backports/tools/check-app.lua \
        6.0 /path/to/band/folder /path/to/App /path/to/Other

The release is one the `~/.charon/dyld` folder holds a cache of, and the band
folder is the folder of `libFoundationBackports.dylib` and its siblings that the
package builds for that release (`lib` of an installed `charon@apple-backports`,
or the `bands/<release>` folder of its deb). A binary that already loads the
backports by their install names is checked with those libraries supplied, so
it has nothing left in the first list.

## Reading what a release's library does

The facts behind an `implemented`, `inert` or `ignored` entry come from the release's own library, and
a shared cache holds it with no symbol for an Objective-C method. `tools/cache-methods.py` lists the
methods of an image's classes with the address of each implementation, and `tools/cache-disasm.py`
disassembles from an address, naming the string or the selector an `adrp` with an `add` or a `ldr`
reaches:

    python3 tools/cache-methods.py ~/.charon/dyld/12.0/dyld_shared_cache_arm64 CoreLocation CLLocationManager
    python3 tools/cache-disasm.py  ~/.charon/dyld/12.0/dyld_shared_cache_arm64 0x187d5acd8 300

They read the cache file and the sub-caches beside it (`.01`, `.02`, ...) themselves, so they need no
symbol file: an arm64 cache of iOS 12 has its pointers as a slide chain whose bits they mask off, an
arm64e cache of iOS 16 has authenticated pointers, and its method lists are the small, relative
kind whose selectors sit in a table of the shared cache that libobjc names in its `__objc_opt_ro`.
`tools/cache_reader.py` is the reader they share; `tools/cache-disasm.py` needs `capstone`
(`pip3 install capstone`). `host/cachereader/run.sh` holds the two to a method a cache is known to
have.

## Asking a release which C names it exports

`tools/surface-diff.py` knows the Objective-C classes and selectors the release carries, and no C name, so a
constant or a function that iOS 6 already exports itself shows as a gap, and an `absent` written for it tells an
application that a name is not there when it is. `tools/probe-exports.py` asks the release: it builds a small
program, runs it in the emulator, loads every framework of the release and calls `dlsym` for each name.

    python3 tools/probe-exports.py --registry --workdir "$TMPDIR/probe"
    python3 tools/probe-exports.py --names names.txt --workdir "$TMPDIR/probe"

`--registry` asks about every constant and function the registry lists as `absent`, and exits 1 when the release
exports one, which is the mistake to correct (the entry is the release's own, and says so in a file of facts).
`--names` takes one name a line, a function without its parentheses, for the names a pack of `absent` rows is about to
list: run it before writing the pack. It runs `xmake emulate` with the `XMAKE_GLOBALDIR` of the caller, which must
hold the `charon latest` addon of the tree named by `--charon`, and the emulator's answer for iOS 6.0 was the same as an
iPad 2 and an iPhone 4S running 6.1.3 gave.

## Measuring how much of an SDK the registry has decided

`tools/surface-diff.py` lists what an SDK declares for a framework - every class,
protocol, method, property, extern constant and function, with the release its
availability attribute gives for iOS - and says how much of it the registry has
decided. It reads the SDK the way the build reads one, from clang's AST of the
umbrella header, and needs no addon. A row is decided when the registry lists it
by name, lists its property's accessors, lists its class as `absent` or
`ignored`, or lists its class as `implemented` and the row arrived no later than
the class did; the rest is API nobody has said anything about, which is
`absent` by default, and is the gap the tool counts by framework and release.

    python3 tests/backports/tools/surface-diff.py Foundation UIKit CoreLocation \
        --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk

A macOS SDK is read as Mac Catalyst, whose `System/iOSSupport` carries UIKit and
the other iOS frameworks with the availability of iOS up to that SDK's release;
a framework that exists only on iOS is not in it, and a run against it reports
nothing. An iPhoneOS SDK takes `--target arm64-apple-ios16.4` and has them.
`--above` and `--up-to` cut the releases, `--list` prints every gap, and
`--rows FILE` writes every declared row for other tools to read.
- `safariviewcontroller.m`: an application of its own, the SafariServices batch: a controller is shown against a small server on the loopback address, and the delegate is asked for the initial load, a redirect, the activities and the dismissal. The rest of what a controller does before it is shown is held to the system's by the `safariviewcontroller` group of `host/uikit2/run.sh`. It needs the package built with `safariservices = true`.
- `aswebauth.m` (`aswebauth-Info.plist`): an application of its own, the web authentication session of iOS 12 over the loopback server `safariviewcontroller.m` uses: the callback URL of a redirect, the error of its own domain with the code 1 for a cancel and for an address that is not a web address, the second start refused and a session with no handler.
- `photos.m`: a command-line test of the photo authorization of `PHPhotoLibrary`: the status is the `ALAssetsLibrary` status, both access levels give it and never limited, and `+requestAuthorization:` is called only when the status is decided already, so no prompt is shown. It needs the package built with `photos = true`.
- `gamecontroller.m`: a command-line test of the GameController classes with nothing attached: the lists are empty, the current device and the coalesced keyboard are nil, the discovery calls its handler once on the main queue, the notification names are the strings of their own names, and the background flag keeps what it is given. It needs the package built with `gamecontroller = true`.
- `secitem.m` (`secitem-Info.plist`, `secitem.entitlements`): an application of its own, the synchronizable attribute of iOS 7 against the keychain of the release: the two constants and the library they come from, an item added with the attribute true and false, and what a query for it, for not, for Any and for nothing finds. The entitlements give the application a keychain access group, without which every `SecItem` call answers -25308 whatever it asks. Install `charon-sblaunch` first and run `su mobile -c uicache` before launching. It needs the package built with `security = true`.
- `metal.m`: a command-line test of `MTLCreateSystemDefaultDevice`: it comes from the backports, answers nil twice, and neither MetalKit nor the device protocol is there. It needs the package built with `metal = true`.
- `avauthorization.m`: a command-line test of the camera and microphone authorization of iOS 7: both statuses, the exception for another media type with its reason, and a request that calls its handler once off the main thread. It needs the package built with `avfoundation = true`.
- `coregraphics7.m` (`coregraphics7-cases.m`, `coregraphics7-expectations.h`): a command-line test of CoreGraphics colour spaces: the release's own `CGPathAddRoundedRect`, `CGPathCreateWithRoundedRect`, the generic colour functions and the constant colours over 265 cases held to the answers `host/coregraphics7/refresh.sh` records from the host's CoreGraphics, and the predicates and `CGColorSpaceCopyICCData` of `libGraphicsBackports.dylib`. `host/coregraphics7/run.sh` runs those predicates beside the host's own. It needs the package built with `graphics = true`.
- `textkit7.m`: an application of its own, the text batch of iOS 7: the attribute names, the document types, `NSTextTab` and what the release's HTML, RTF and plain-text import gives, read against the host's answers recorded by `host/textkit7/run.sh` from `textkit7-cases.m`.
- `nsdataasset.m`: an application of its own, `NSDataAsset` reading the small compiled catalogue in `data-assets/Assets.car` (written by `host/nsdataasset/make-car.py`); the group `nsdataasset` of `host/uikit2/run.sh` compares the port to the system's class on a catalogue an application was built with, named by `CHARON_DATA_ASSET_CATALOG`.
- `opengles.m`: an application of its own, the ES 3.0 functions in an ES 2.0 context: vertex arrays, occlusion queries, fence syncs, mapped buffer ranges, immutable textures and multisampled renderbuffers through the release's extensions, and the errors of the calls with no answer. `tools/gen-es3.py` writes the library from the SDK's two headers. It needs the package built with `opengles = true`.
- `imageextract.m`: an application of its own, the files `tools/assets-extract` wrote from a catalogue (`IMAGE_EXTRACT_DIR` in the build script): every name of the index is found by the stock `+[UIImage imageNamed:]`, at the scale and size of the best file for the screen.
- `uikitnames.m`: an application of its own, the names and small classes of iOS 7 to 10 - the transition context keys, the screenshot and background-refresh notifications, the activity types, the callout and title text styles, the edge pan recognizer and the percent-driven transition - read against the host's answers recorded by `host/uikitnames/run.sh` from `uikitnames-cases.m`.
- `foundation8b.m`: the names of iCloud metadata and app extensions, the deallocator blocks and file access intents of iOS 7 to 10, read against the host's answers recorded by `host/foundation8b/run.sh`: the intents are coordinated on a real folder, alone, together and for an item that is not there.

`host/previewaction/run.sh` records what the host's UIKit answers for `UIPreviewAction`,
`UIPreviewActionGroup` and `-previewActionItems` in `device/previewaction-cases.m`, and
`device/previewaction.m` runs the same cases against the port on the release, record by record.

`host/invalidation/run.sh` records what the host's UIKit answers for the collection view
invalidation contexts and for `-invalidateLayout` routed through `-invalidateLayoutWithContext:`
in `device/invalidation-cases.m`, and `device/invalidation.m` compares the port record by record.

`host/presentation/run.sh` records what the host's `UIPresentationController` answers in
`device/presentation-cases.m`, in a Mac Catalyst application with a window, and
`device/presentation.m` compares the port record by record on the release.

`host/imageio/run.sh` runs `device/imageio.m` against the host's ImageIO, and the same tool runs on
the release against the port: the key `kCGImageSourceShouldCacheImmediately` is the string ImageIO
gives it, and an image made with it set is the image made without it.

`host/inputview/run.sh` records what the host's `UIInputView` answers in `device/inputview-cases.m`,
in a Mac Catalyst application with a window, and `device/inputview.m` compares the port on the release.
