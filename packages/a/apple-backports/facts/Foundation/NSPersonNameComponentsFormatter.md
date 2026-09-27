# The person name components formatter, iOS 9.0 and 10.0

The class, the five styles, the annotated string, the parse, the phonetic option and the locale, and
the eight attribute names the annotated string is written with.

Source: the SDK 26.2 headers, and the host's own `NSPersonNameComponentsFormatter` over ten locales
and eleven component sets, through `tests/backports/host/personname` (the port's class compiled
under a name of its own, so the two answers sit side by side), with the readings kept in
`.agent-work/probe/order.m` and `batch.m`.

## The name order is six language codes, and the separator is one string

Both were read out of the host's own formatter over **every locale it knows — 1,072 of them**:

- the separator is a plain space in all 1,072, so it is one string and not a table;
- six languages write the family name first — **hu, ja, ko, vi, yue, zh** — and the other 1,040 write
  the given name first.

That is CLDR's `nameOrder`, one bit per language, and the port keeps the six. The
`ABRecordCopyCompositeName` route this file started with is *not* what is here: that call answers for
the **device's** language, which is right only while the formatter is left on the current locale and
wrong the moment an application sets another one — which the differential found, on `ja_JP` and
`zh_Hans_CN`, where the port wrote "John Appleseed" where the system writes "Appleseed John".

## The five styles, as the host answers them

| style | what it is | en_US "Dr. Johnathan Maple Appleseed Esq." | ja_JP, the same |
| --- | --- | --- | --- |
| long | prefix, given, middle, family, suffix, in the language's order | `Dr. Johnathan Maple Appleseed Esq.` | `Dr. Appleseed Johnathan Maple Esq.` |
| default, medium | given and family, in the language's order | `Johnathan Appleseed` | `Appleseed Johnathan` |
| short | the nickname, else the given name, else the family name | `Johnny` | `Johnathan` |
| abbreviated | the given and the family initial, in the language's order | `JA` | `AJ` |

Two of the header's own examples are not what the system answers, and the system is followed: the
header illustrates `short` with "C Darwin" (the host answers the nickname alone, or the given name
alone) and `abbreviated` with "CRD" (the host answers the two initials of the given and the family
name, and never a middle initial). Both are in the differential's cases.

Three smaller rules, all measured:

- **A nickname with nothing else** answers for `long` and `abbreviated` too, not only for `short`.
- **A middle name or a suffix alone** is a long name: the host answers "Maple" and "Esq.".
- **Nil components** raise `NSInternalInconsistencyException` on both sides.

## The annotated string

The default form, with one run per component and the *name of the component* under
`NSPersonNameComponentKey` — `givenName`, `familyName`, `middleName`, `namePrefix`, `nameSuffix`,
`nickname` — and one run for the separator whose value is `NSPersonNameComponentDelimiter`, which is
the constant's own string and not the separator's text (measured: the host's runs for a Japanese name
are family, delimiter, given, in that order). The eight names are defined in this file, beside the
code that writes them, so a formatter and the names it writes are one object and one release group.

## The parse

Fifteen strings, read on both sides. A comma reads as family-then-given ("Appleseed, John" gives the
given name John and the family name Appleseed). Otherwise the first word is the given name, a first
word ending in a full stop is a prefix, a last word ending in a full stop is a suffix, and everything
between them is the family name, so "Dr. John Maple Appleseed Esq." gives the prefix Dr., the given
name John, no middle name, the family name "Maple Appleseed" and the suffix Esq. A string with nothing
in it is not a name: `personNameComponentsFromString:` answers nil and
`-getObjectValue:forString:errorDescription:` answers NO with the error description "Person's name
could not be detected".

## One recorded divergence, asserted rather than compared

The host **raises** `NSUnknownKeyException` when the abbreviated style is asked for a *phonetic*
representation, because its abbreviated template asks the phonetic object for the component keys it has
not got. The port answers the two initials instead, because an API here must not crash its caller
(COORDINATION §2), and the differential asserts that difference on both sides rather than hiding it.

## Open, and it is the next thing to do

The suite is **not green**: it runs 515 checks with 9 of the recorded divergence and then **crashes**,
and the crash is not a memory error. What is measured about it:

- **AddressSanitizer and UndefinedBehaviorSanitizer are both silent** (`tests/backports/host/
  personname/asan.sh` builds the suite with both and runs it). The process dies on `EXC_BREAKPOINT`,
  which is a deliberate trap rather than a fault, and the ASan build reproduces it at the same case.
- The first run of it ended in the *test's* attribute walk with a dangling value on the **system**
  side, which is what put the eight names in an object of their own: a differential that links the
  port's definitions of eight exported symbols next to the system's has two definitions of each in one
  process, and that is worth not doing whatever else is true. The names are back in
  `NSPersonNameComponentKeys9.m` and the formatter's object no longer defines them.
- With the names moved, the same 515 checks pass and the crash is at the same place in the sweep: the
  **port's** long style, `en_IN` and the "given and family" set, style 3. The lldb frame for the
  earlier build was `-[NSAttributedString enumerateAttributesInRange:options:usingBlock:]` in the test,
  and the one after the split is the same case, so both are the port's long path reached through two
  different call sites.

What is left is one case in one locale: `en_IN`, "given and family", style 3. The next thing to do is
to narrow it further -- hold `en_IN` alone, print the pieces the port joins before it joins them, and
find which of them is the trap.
