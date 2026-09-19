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
    sh host/validatedformat/run.sh [pairs]
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

`host/fuzz/run.sh` runs one of three fuzzers against the host's Foundation:
`percentencoding` (percent encoding and the URL character sets, Base64 of
strings and data), `stringcase` (localized case, containment and transforms)
and `calendar` (the `NSCalendar` and `NSDateComponents` methods of iOS 8).
Each draws its inputs from a seeded generator and prints the seed, so a run can
be repeated with `run.sh <fuzzer> 0 <seed>`. Every difference is filed under a
category, one per method or option, and the first three of each are printed.
The host is newer than any release the port follows, so a difference is not by
itself a bug in the port: a category listed in `host/fuzz/tolerated/<fuzzer>.txt`,
with the reason on the same line after a tab, is counted but does not fail the
run. Any other category does.

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
- `haptics.m`: a process of its own for the feedback generators, linking UIKit
  but raising no window. It holds the port to what was read off iOS 10 rather
  than to a sensation: that the three generators are there and come from the
  backports library, that `UISelectionFeedbackGenerator` is **not** declared,
  that a style outside the three still builds a generator and simply plays
  nothing instead of raising, that the iOS 13 `-impactOccurredWithIntensity:` is
  not answered, and that every call returns without raising. It says nothing
  about how hard the motor turns: that was measured on an iPhone4,1 with the
  accelerometer and is written down in
  `packages/a/apple-backports/facts/UIKit/UIFeedbackGenerator.md`, since an
  emulated device has no motor and every call there plays nothing.
