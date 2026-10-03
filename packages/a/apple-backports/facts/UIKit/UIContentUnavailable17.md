# UIContentUnavailable, the empty-state API of iOS 17.0

What the host's own UIKit answers was measured first, on the host's UIKit under Mac Catalyst, and
every number and answer below is the case's, not a reading of the header. The case is
`tests/backports/host/uikit2/contentunavailable_test.m`, run by the `contentunavailable` group in
`tests/backports/host/uikit2/run.sh`, and the port is
`packages/a/apple-backports/UIKit/UIContentUnavailableProperties.m`.

## M1. The three property bags and the state object are plain holders, with three measured defaults

`UIContentUnavailableTextProperties`, `UIContentUnavailableImageProperties` and
`UIContentUnavailableButtonProperties` each hold only what their properties say. The port's three are
the same holders, and the case sets every property on the port's copy and on the system's and reads
both back: 45 checks, 0 failures.

The header states **no** default for the text bag's font, colour or line break mode, so the port's
values are not read out of it. They are what the case measured, and the case's first run is what found
them wrong — the port held zeros where the host holds three things:

```
FAIL a fresh text bag holds the same line break mode: port 0 != system 4
FAIL a fresh text bag holds a font on both sides: port (null) system ".SFNS-Regular 17.00 pt. …"
FAIL a fresh text bag holds the same default colour: port nil != system <UIDynamicCatalogSystemColor: … name = labelColor>
```

So, measured: a fresh text bag breaks its **last** line, which is `NSLineBreakByTruncatingTail` and is
**4**; it holds the **system font at 17.0 points**; and it holds a **labelled colour**.

The two colour names are the host's, and they are the two the port cannot share, so the facts carry
them and the case compares the *role*:

| side | name |
|---|---|
| the host's fresh bag | a dynamic catalog entry, `labelColor` — `UIColor.labelColor`, iOS 13.0 |
| the port's fresh bag | `[UIColor darkTextColor]` — the release's own label text colour, 6.1.3 |

Neither name exists on the other side's release, and holding the names equal would ask the port to
answer a colour it has no way to build. The case therefore asks that both sides answer a colour that
is there and is not `UIColor.clearColor`, which is what a label colour is for. The font is the same
case: the host answers `.SFNS-Regular 17.00 pt.` and `.AppleSystemUIFont` for the family, the port asks
for the system font by size, and the case compares the size and whether either side answered a font at
all.

A button bag's `enabled` is a fresh `YES` in the port and the case reads the system's fresh bag; the
two agree, and that is the case saying so rather than this file. An image bag's fresh zeros — nil
symbol configuration, nil tint, zero radius, zero maximum size, `NO` — match the host's, read the same
way.

## M1a. The bags are archivable and the archive is read back

Each bag keeps `NSSecureCoding` and answers `+supportsSecureCoding YES`, so each writes its properties
out and reads them back. The first version answered `[self init]` from `initWithCoder:` and wrote
nothing, and the review's round trip is what that cost: a button bag archived with `enabled = NO` and
`role = UIButtonRoleDestructive` came back `enabled` and plain, because nothing was read. The state
class already had the right shape in the same file; all three bags now match it.

## M2. A state over no trait collection is refused

The host raises on `initWithTraitCollection:` with a nil collection:

```
*** Terminating app due to uncaught exception 'NSInternalInconsistencyException',
    reason: 'Invalid parameter not satisfying: traitCollection != nil'
```

The port raises the same exception with the same message, so the refusal the host has is not missing
here. Both initialisers are `NS_DESIGNATED_INITIALIZER` in the header, which is why the port's
`init` is not offered.

## M3. The two classes that are not carried

`UIContentUnavailableConfiguration` has a `button` and a `secondaryButton` of type
`UIButtonConfiguration`, which this library does not carry, and `UIContentUnavailableView` is built
over the configuration. Both rows are `absent` on that, and both land when `UIButtonConfiguration`
does.

**Corrected 2026-10-03: the paragraph above is stale.** `UIButtonConfiguration` is carried
(`UIKit/UIButtonConfiguration.m`, class row `implemented` in `registry/UIKit/ios15-16.json`), and so is
`UIContentConfiguration`, the protocol the configuration conforms to (`registry/UIKit/ios13rest.json`).
Neither class is blocked on substrate. What the configuration still waits for is seven host defaults
nobody has measured - `imageToTextPadding`, `textToSecondaryTextPadding`, `textToButtonPadding`,
`buttonToSecondaryButtonPadding`, `alignment`, `axesPreservingSuperviewLayoutMargins` and
`directionalLayoutMargins` (`coordination/api-queue.md`, owed since 2026-09-30) - and the view waits for
the configuration. Both rows' `reason` now say this; `UIKit17Absence.md`, "A stale blocker in M3,
corrected", is the same correction from the absence side.

## Not measured

- `supportsSecureCoding` on the port's copies answers yes, which is what the port has always answered for
  a value holder; the host's answer is not read by the case.
- Whether the host's empty/loading/search configurations differ in any property a fresh one holds: the
  configuration is not carried, so there is nothing to read them on.

## The red control for this group, and the 14.0 rows that are not this object's

### THE CONTROL, and why this group needed one more than the others

    $ sh tests/backports/host/uikit2/red-control.sh
    == the unplanted group, which must be green
       contentunavailable: exit=0
    == planting a line count nothing keyed asked for, in a scratch copy
    == the planted group, which must be RED and must NAME the key
       contentunavailable: exit=1
         FAIL a fresh text bag holds the same line count: port 99 != system 0
       the planted run names the line-count key, so the disagreement is attributable
    RED CONTROL OK: green before, red after, naming the key, tree untouched

The group is built for arm64-apple-ios15.0-macabi, where the four iOS 17.0 classes do NOT exist in the
system UIKit.  There is still a system side - the test holds the four classes under their own names and
the port's objects sit beside them with prefixed selectors - but the class EXISTENCE comes from the
test's own @interface declarations rather than out of a framework.  That is a weaker position than a
group whose other side the SDK supplies, and the review is right that a check which has only ever seen
its own clean output has not been shown to fail.

The plant is a VALUE, not a deletion: `_numberOfLines = 0` becomes 99 in the copy, so the group still
builds and still links.  A plant that broke the build would prove the compiler works, not that the
comparison works.  It is made in a scratch copy reached through UIKIT2_SOURCES - the runner already read
its source directory from that variable - and the control asserts the repository's own file is byte
identical afterwards, so a control that forgot to copy could not pass by editing the tree.

TWO THINGS THIS COST TO GET RIGHT, both caught by the control itself rather than by a reading:

  the first anchor was `return 0`, and numberOfLines is a synthesised PROPERTY over an ivar - there is
  no getter to edit, so the plant changed NOTHING and the run stayed green.  The file-unchanged
  assertion caught it.  A control that cannot tell a no-op plant from a real one will one day report a
  green run as a green plant.

  the suite is over ten minutes and contentunavailable is the LAST group in the file, so the control
  could never reach the group it controls.  UIKIT2_ONLY narrows the run to named groups, empty by
  default so an ordinary invocation is unchanged, and it is honoured by all THREE dispatchers - `group`,
  `windowed` and `prefixed_group`.  Filtering only one of them is what the first run showed: it built
  foundation14networkaccess and printed a listmenus compile FAIL from a group that never ran.

The control reads only ITS OWN group's failures, for that last reason: a shared build directory means a
skipped group can still leave a line in the log, and reading the whole log would credit this control with
a failure it did not cause.

### WHY THESE ARE 17.0 AND NOT 14.0, which is the question the review asks

The object adopts `<UIConfigurationState>` and implements `customStates`, `-initWithTraitCollection:`,
`-objectForKeyedSubscript:`, `-customStateForKey:` and `-setCustomState:forKey:`.  The registry dates
those same five members 14.0, in registry/UIKit/ios13rest.json:

    -[UIConfigurationState customStateForKey:]            introduced 14.0  implemented
    -[UIConfigurationState initWithTraitCollection:]      introduced 14.0  implemented
    -[UIConfigurationState objectForKeyedSubscript:]      introduced 14.0  implemented
    -[UIConfigurationState setCustomState:forKey:]        introduced 14.0  implemented

THE ANSWER: those rows name UIConfigurationState, and this object does not implement UIConfigurationState.
It implements UIContentUnavailableConfigurationState, a 17.0 class, and the five names above are the
PROTOCOL it adopts plus its own storage.  Concretely, and this is the distinction:

  A CONFORMANCE OBLIGATION.  `UIContentUnavailableConfigurationState : NSObject <UIConfigurationState>`
  declares the protocol, so the class MUST answer what the protocol declares or a caller holding it as a
  UIConfigurationState gets an unrecognised selector.  -initWithTraitCollection: and -objectForKeyedSubscript:
  are protocol members here; implementing them is conformance, not carrying 14.0 API.

  THE PORT'S OWN STORAGE.  `customStates`, `-customStateForKey:` and `-setCustomState:forKey:` are NOT on
  the protocol, and they are not in ios13rest.json at all.  They are this class's own dictionary-backed
  implementation of what the protocol's custom-state members mean for a state that carries a search
  field.  A 17.0 object implementing its own storage is not shipping a 14.0 release.

So the object adds exactly four rows and all four are introduced 17.0.  It adds no 14.0 row, carries no
14.0 implementation, and does not change ios13rest.json.  IF this object were instead re-declaring
UIConfigurationState itself, that would be carrying 14.0 API and would belong in a 14.0 object - it is not,
and the row set is the evidence: four 17.0 rows and nothing else.

The test compares the pair that matters and it is a real system comparison, not a self-comparison: the
keyed-subscript round trip ("a state holds what was keyed into it", "a state holds nothing at a key
nobody keyed", "a state's copy keeps the keyed value") runs the port's object and the system's object side
by side over the same key.  That is what the red control plants against.
