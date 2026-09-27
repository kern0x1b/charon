# Accessibility on a release that has the C library and not the classes

`libAccessibilityBackports.dylib` carries the first group of the Accessibility framework of SDK
26.2: six of its thirty classes, and the declarations the port's own SDK has no header for. Every
registry entry of this framework points here.

## What the release has, measured

`tools/intents/measure-release-carries.lua` against the **6.1.3 armv7 cache** — 580 libraries
walked, with the control symbol found, so "carries none" is a measurement and not a probe that
could not look:

```
the release carries 0 of 30, and does not carry 30
```

Zero, and yet the release has had Accessibility since iOS 3. What it has is the **C** library:
`/usr/lib/libAccessibility.dylib`, and the names the corpus does not list — `AXBrailleTable`'s
older C spelling among them. So this framework is two things stacked: a C API the release already
answers for, and thirty Objective-C classes the SDK of 26.2 declares on top of it, of which this
delivery carries six.

That is why no band needs a straggler here: nothing in this group is a class the release exports,
so every band builds the library whole and `tools/intents/measure-group.lua` — the check that
found the `INPaymentMethodResolutionResult` red — has nothing to name.

## The four headers 16.4 does not have, and what this header says

16.4 ships eight Accessibility headers, 26.2 twelve. The four that are new are `AXRequest.h`,
`AXMathExpression.h`, `AXBrailleTranslator.h` and `AXFeatureOverrideSessionManager.h`, and
`CharonAccessibility.h` is where the names in the first, the third and the fourth are declared,
transcribed word for word in their contract. It also carries `AXTechnology`, which is Apple's own
`NSString *const` typedef and whose nine constants are externs — spelled out because a backport
writes the declaration itself.

One spelling worth recording, because it cost a compile and would cost the next person the same:
**`AXTechnology` is `NSString *const`**, so an ivar of that type is a *const pointer* and can never
be assigned. The class's storage is an `NSString *` and the property's accessor answers it
unchanged.

## The three walls, and what each answers

**A request is the system's.** `+[AXRequest currentRequest]` is the request the system's assistive
technology is serving, and `technology` is the one serving it. No assistive-technology service
holds a request on this release, so `+currentRequest` is **nil** and the class is the container an
application keeps its own request in: `-charon_withTechnology:` builds one, the coding and the copy
carry it, and `+currentRequest` says there is none.

**A feature override is a service.** `beginOverrideSessionEnablingOptions:disablingOptions:error:`
is how an application asks the system to turn grayscale on, or Voice Control on, for a while. The
system that does it is not on this release, so the manager answers **nil with
`AXFeatureOverrideSessionErrorUndefined`** — the header's own name for a session that could not be
begun for no more specific reason, and there is no more specific one: there is no service, so
there is nothing to be entitled to, nothing already active, and nothing registered under a UUID.
`endOverrideSession:` answers NO for the same reason, and a session that cannot exist is not
invented so that the call has something to end.

**A braille table is Apple's data.** `AXBrailleTable` is a provider's dot patterns, and
`AXBrailleTranslator` maps print text onto the table it is given. The table the system installs is
not on this release, so `+supportedLocales` is an **empty set**, the two other sets are empty, and
`+defaultTableForLocale:` is nil — which is what makes the translator's answer honest rather than
invented: a translation of nothing is the input with **no cells**, and the location map is empty
because no cell was produced. Both directions answer that way, the second without guessing print
text out of dot patterns. A table an *application* builds is real and is kept, coded and copied.

## What is not carried, and why each

247 of the 270 entries are `absent`, and the reasons are in three buckets rather than one excuse:

* **The sixteen `AXMathExpression` classes** are a parser and an evaluator for the mathematics
  grammar — numbers, identifiers, operators, fractions, superscripts and subscripts, tables, under
  and over, multiscript, fenced expressions. An ivar per property would answer a parse that never
  happened, so this delivery does not implement that grammar and says so in every entry. **This is
  open work, not a wall**: a parser is a day's writing, and the next group of this framework is it.
* **The chart and data classes** (`AXChartDescriptor`, `AXDataPoint`, `AXDataSeriesDescriptor`,
  `AXNumericDataAxisDescriptor`, `AXCategoricalDataAxisDescriptor`, `AXCustomContent`, …) are
  containers the release does not have and this delivery has not reached: they are the next group,
  and their entries name that.
* The C API rows (13 `AX*` functions) get **no entries at all**: a case of an enumeration and a
  header's own function are what `registry/README.md` calls the header's own, and the compiler
  writes the value into the application.

## What is not measured here

Not run: not on the device, not in the emulator, not through the generated call test. Every entry
here is **device-unverified**, and the package build that checks every band is what the delivery
report quotes.
