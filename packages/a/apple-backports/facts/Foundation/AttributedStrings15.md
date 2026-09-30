# The attributed strings of iOS 15.0

Markdown, the attributed formatting of a format string, the language a table's text was found in, and the
inflection pass — one object for one release, six files and the rows they carry.

    sh tests/backports/host/attributed15/run.sh
    bytes 159616
    checks=48 failures=0

The port's selectors are prefixed (`tests/backports/host/prefix_selectors.py`, the mechanism `appgroup`
and `uikit2` use) and its Markdown class is renamed with a `-D` from its own object's symbols
(`tests/backports/host/uikit2/renames.sh`, the mechanism `presentationintent` uses), so the system's five
members and the port's five answer in one process and every case compares the two. The whole verdict is
48 checks and no failures: four constants, twenty-two formatting cases, the bundle lookup, five
inflection cases, fourteen Markdown cases, the task delegate's four, and four cases that ask the
*release* what it answers for the members of an abstract class.

Two things had to be measured before any of it could be written, and both are the kind of thing a header
does not say.

## The format is an attributed string, and the two families do not format numbers alike

`+[NSAttributedString localizedAttributedStringWithFormat:]` takes an `NSAttributedString`, not an
`NSString`, and a conversion can stand inside a run of its own attributes. Those attributes are what the
substituted text is drawn with:

| the format | the argument | the answer |
| --- | --- | --- |
| `pre %@ mid %@ post`, the colour over `%@ ` (4,3) | `ARG` bold, then `plain` | `ARG` coloured **and** bold, the space after it coloured, `mid ` and `plain` not |
| the same with `NSAttributedStringFormattingInsertArgumentAttributesWithoutMerging` | the same | `ARG` bold alone: the format's attributes are dropped |
| the same with `…ApplyReplacementIndexAttribute` | the same | both, and `NSReplacementIndexAttributeName` 1 and 2 on the two runs |
| `%d and %.2f` with de_DE, with fr_FR, with nil | `1234`, `1234.5` | `1234 and 1234.50` — **canonical**, whatever locale the initialiser was handed |
| `%d and %.2f` through `+localizedAttributedStringWithFormat:` | the same | `1.234 and 1.234,50` — the machine's `en_US@rg=plzzzz` |

So the explicit-locale initialisers format canonically and the two `localized` methods format with the
current locale. The port passes `nil` to the release's own formatter from the first family and
`[NSLocale currentLocale]` from the second; that is the whole of the difference and it is in
`NSAttributedStringLocalizedFormat15.m`.

A `%` that opens no conversion is consumed and what it read is text again: `a % b` answers `a  b` and
`a %1 b` answers `a 1 b`, while `x %q y` answers `x q y`; a format that is nothing but such a specifier
answers nothing, so `%q`, `%0` and `%-` are empty, and so is the `%q` at the end of `100%% %@ %q`. A
`%@` given nil is `(null)`, a number and an array are their own `-description`, and an attributed argument
contributes its own text.

**A format whose conversion has no argument behind it is not compared**, because it is not a question with
an answer: `50% off` answers `505ff` on one run of the system and `500ff` on the next, both from a
variadic slot nobody passed. It is left out of the differential and named here instead.

Two things about the va_list are the port's own and not the release's, and both were measured:

* A list cannot be handed to the release's formatter twice. The second call reads the floating-point
  register area as spent and answers `0.00` where the first answered `1234.50`, so each argument is taken
  out of the list with the type C promotes it to and formatted on its own (`CharonApply`).
* A variadic member cannot be reached through a non-variadic `objc_msgSend` prototype: the call is a
  misread, and a member given `Bob 7` answers `Ann 3`. `tests/backports/host/attributed15/ported.h`
  declares the prefixed members the way the SDK declares them, with the variadics, and `run.sh` checks
  every selector in it against the declarations header the tool writes, so the two cannot drift.

## The Markdown answer is a tree of intents, numbered in document order

Apple's own source for this does not exist and no public source implements it; the semantics come from
the release's own answers above, and `swiftlang/swift-corelibs-foundation` has neither the Markdown nor
the presentation intents (`Sources/Foundation/NSAttributedString.swift` carries neither). What a
document answers, measured on the system and reproduced by `NSAttributedStringMarkdown15.m`:

* a heading is a header intent with its level, a paragraph a paragraph intent, a fenced or an indented
  code block a code block intent with the info string as its language hint, `***` a thematic break whose
  text is the two-em dash U+2E3B, `> ` a block quote with a paragraph inside it, a list a list intent
  with an item intent per entry carrying its ordinal from 1 and a paragraph inside the item;
* the identities are numbered from 1 in document order, a container before what it holds: in
  `> quote` / a code block / a paragraph / a table / a table, the system answers 1…12 and so does the
  port, run for run;
* a link carries `NSLinkAttributeName` with its URL resolved against the `baseURL`, an image
  `NSImageURLAttributeName` likewise;
* a table is a table intent with its column count and the alignments of its header, a header row intent,
  a row intent per body row from 1 and a cell intent per cell with its column from 0; the cells of a row
  follow one another with nothing between them;
* the inline spans are `NSInlinePresentationIntent`: emphasized 1, strongly 2, code 4, strikethrough 32,
  a soft break 64 and a hard break 128, and the extended syntax is interpreted with the *default* options
  even though `allowsExtendedAttributes` answers NO;
* a soft break is one separator space and not the newline: `one\ntwo` answers `one two` with a run of one
  space carrying 64. `NSAttributedStringMarkdownInterpretedSyntaxInlineOnlyPreservingWhitespace` is the
  one option that keeps the source's own spacing;
* a document that cannot be read or decoded is the release's own refusal: `nil` and an `NSError` under
  `NSCocoaErrorDomain` / `NSFileReadUnknownError`.

`NSAttributedStringMarkdownParsingOptions` is a class the release 6.1.3 does not have at all: five
properties, a copy of the five and a keyed archive under the SDK's own property names. Its defaults are
measured and are the allocation's own — `allowsExtendedAttributes` NO, `interpretedSyntax` full,
`failurePolicy` return the error, `languageCode` nil, `appliesSourcePositionAttributes` NO.

### What is not carried, named

* **`NSListItemDelimiterAttributeName`** is a 16.0 name and the SDK this port builds against
  (`iPhoneOS16.5.sdk`) does not declare it, so a list item's run carries its intent and not the
  delimiter. The differential leaves that one key out of the comparison and prints what the system put in
  it on every run — `"-" at 46` for the bullet list, `"." at 7` for the ordered one — so the difference is
  on the output and not folded into a pass.
* **The styling is not carried.** A heading's font, a link's colour and a code span's monospaced face
  are the system's own private choices; no API fixes them, and the port does not invent sizes. What the
  release's own documentation says an attributed string from Markdown is *for* — an application that lays
  the text out by hand reading the intents instead of parsing the Markdown — is answered in full.
* **A positional conversion, `%1$@`, is not carried.** The system takes its argument from the position
  the format names (`%2$@-%1$@` answers `two-one`); the port consumes the specifier and leaves nothing in
  its place. It needs an argument table the port does not keep.
* **An HTML block and an entity reference are the source's own text.** The system marks them
  (`NSInlinePresentationIntentBlockHTML`, 512) and the port keeps the characters without the mark.

## Inflection: the rule travels in the string, and the tag goes when it has been followed

`-[NSAttributedString attributedStringByInflectingString]` is not a function on the text: its own header
says it inflects the portions tagged with `NSInflectionRuleAttributeName` by the rule in the attribute.
What the system does with the rule, measured for every shape the header names — an explicit rule
(Plural, Masculine), the automatic rule, a tagged run with a number in it, a whole string tagged — is to
answer the text as it stood, and to answer it as **one run with no attribute on it at all**: the tag is
dropped, because the rule has been followed. The port does the same, and coalesces the neighbours that
answer alike into that one run.

The rule the port carries is `NSInflectionRule` and `NSInflectionRuleExplicit`, which hold an
`NSMorphology` and no grammar, so `CharonInflection()` in `NSAttributedStringInflection15.m` answers the
range it is given. **A word under a case, a gender or a number is CLDR's rule table and this object does
not carry one**; the differential prints the text of every case so a reader can see that the two agree
rather than take it from the source. A table is data and not a function, and it is named here as the thing
that would change that one function.

## The bundle's answer carries the language it was found in

`-[NSBundle localizedAttributedStringForKey:value:table:]` is the release's own
`-localizedStringForKey:value:table:` with one thing added: the text comes back with
`NSLanguageIdentifierAttributeName` on it, holding the bundle's own current localisation. A key the table
does not carry answers the `value` the caller passed, tagged the same way. The lookup itself is 6.1.3's
and reads the same `.strings` and `.stringsdict`; a second reader of the tables would answer differently
from the release's on every rule the format has.

## The three attribute names, and the one whose name is not its value

`NSAlternateDescriptionAttributeName` is `NSAlternateDescription`,
`NSImageURLAttributeName` is `NSImageURL` and `NSInlinePresentationIntentAttributeName` is
`NSInlinePresentationIntent` — each read with `dlsym` out of the system's own image and compared in
`constant.*`. `NSLanguageIdentifierAttributeName` is **`NSLanguage`**, and the system exports no symbol for
it on either of its images, so the value is measured by `bundle.missingKey`, which prints the attribute
name the system itself put on the answer. All four are in `NSAttributedStringKeys15.m`, which is the
release's own object for the attribute names of 15.0.

## The per-task delegate

`NSURLSessionTask`'s `delegate` is `@dynamic` in `NSURLSession.m` with no accessor behind it, so a task
answered the accessor with `doesNotRecognizeSelector:`. `NSURLSessionTask+Delegate15.m` adds the two
accessors as a category with the value in an associated object, `OBJC_ASSOCIATION_RETAIN_NONATOMIC`
because the SDK's own declaration of the property is `(nullable, retain)`; the four `task.*` cases in the
differential read a fresh task (nil beside the system's nil), a delegate set and read back, and the
system's own doing the same.

The other half is the routing, and the host cannot measure it: the port's `NSURLSession` is a class the
host also defines, so that file cannot be linked beside the host's. `charon_task_delegate()` in
`NSURLSession.m` is the one place that decides — a task's own delegate answers the task-scoped messages
in place of the session's, and the eleven `-respondsToSelector:` guards and the eighteen sends all read
it, so a guard and its send cannot disagree about who was asked. `tests/backports/device/ios1516.m` is
where that runs; the canon build is what measures it and this band did not.

## The release answers the initialisers of an abstract class, and nothing can be held to the answer

Three rows of this slice are `inert` and not `absent`, and the difference is the whole of their reason.
`+[NSPresentationIntent new]`, `-[NSPresentationIntent init]` and `-[NSInflectionRule init]` are all
`NS_UNAVAILABLE` in the SDK's own headers, and the port's classes carry those selectors by inheritance
from `NSObject` while sending them nowhere. A claim that "the release has nothing" would be false, and
the release's own answer is what makes the row `inert` rather than `implemented` — measured in the
`release.*` cases:

    +new answers <NSPresentationIntent 0x…>: Paragraph (id 0), an instance of NSPresentationIntent,
    intentKind 0, identity 0
    -init answers an instance of NSPresentationIntent, intentKind 0, identity 0
    -[NSInflectionRule init] answers an instance of NSInflectionRule

The identity is **not initialised**: it reads 0 on one run and the pointer-shaped number
-6510171893482810916 on another, both measured. So the release does answer, and there is no value any
implementation could be held to — which is what `inert` says and what `absent` would deny.

## The release's own ladder

`python3 tools/cache-index/first-rung.py` from the repository root answers which held release carries each
name, and for this object's members it answers **16.0** for all of them — the four attribute names
(`_NSAlternateDescriptionAttributeName`, `_NSImageURLAttributeName`,
`_NSInlinePresentationIntentAttributeName`, `_NSLanguageIdentifierAttributeName`) and the ten selectors.
The held set is dense to 12.0 and then has no 13.0, 14.0 or 15.0, so 16.0 is an upper bound and never a
measured 15.x. `NSAttributedStringMarkdownParsingOptions` and `NSPresentationIntent` read `NONE` for
their class names and 16.0 for the members, which is why the objects that define them are placed by
their minimum. Two names read 3.0 and say nothing about their owner: `delegate` is another class's
selector and `-attributedStringByInflectingString` is 15.0, so the class-scoped reading is the one above
and not the bare selector's.
