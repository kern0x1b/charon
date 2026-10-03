# PDFAnnotation's widget members, and what the rest of the category needs

## What is here

Nine of the 38 members `PDFAnnotation (PDFAnnotationUtilities)` declares, and they are the nine that are
**`/Ff` bit reads**. Every one is measured on the host over `widget-flags.pdf`, which carries **one
annotation per bit with only that bit set** — thirteen bits, thirteen annotations — plus
`widget-allflags.pdf`, which carries every bit at once. That shape is the whole reason these are
measurable: a fixture with all the bits set answers every member YES and proves nothing.

The fixture table's first version wrote each bit as a **list**, so `str(bits)` produced `"[1]"` and the
dictionaries carried `/Ff [1]` — an array where the format wants an integer — and the host then answered
every flag member NO on every fixture, which read as "the host ignores /Ff". Two more fixture bugs in the
same family, both silent and both looking like a host behaviour:

* `WIDGET_FIELD_TYPES` passed the field type both as the helper's argument and as an extra pair, so every
  dictionary carried `/FT` twice and the host answered three of the four field types rather than four.
* the one-field-type-per-fixture loop named all three `/Ch` fixtures `widget-ftch.pdf`, so each overwrote
  the last and only the first was ever measured.

## The bits, and the two that are not what the table's names suggest

| `/Ff` bit | value | the member that moves | fixture |
| --- | --- | --- | --- |
| 1 ReadOnly | 1 | `readOnly` → YES | annotation 0 |
| 2 Required | 2 | — no member reads it | annotation 1 |
| 13 Multiline | 4096 | `multiline` → YES | annotation 2 |
| 14 Password | 8192 | `isPasswordField` → YES | annotation 3 |
| 15 NoToggleToOff | 16384 | `allowsToggleToOff` → **NO** | annotation 4 |
| 16 RadioInUnison | 32768 | `widgetControlType` → 1 | annotation 5 |
| 17 Pushbutton | 65536 | `widgetControlType` → 0, `allowsToggleToOff` → **NO** | annotation 6 |
| 18 Combo | 131072 | `listChoice` → **NO** | annotation 7 |
| 19 Edit | 262144 | — | annotation 8 |
| 21 FileSelect | 1048576 | — | annotation 9 |
| 22 MultiSelect | 2097152 | — | annotation 10 |
| 25 Comb | 16777216 | `comb` → YES | annotation 11 |
| 26 RichText | 33554432 | `radiosInUnison` → YES | annotation 12 |

Three of those are not a reading of Table 8.39, and each is the fixture that says so:

* **`radiosInUnison` is bit 26, not bit 16** — even though bit 16's name in the table *is*
  RadioInUnison. Bit 16 alone answers NO and bit 26 alone answers YES.
* **`allowsToggleToOff` is the negation of bit 15 *and* of bit 17.** The bit-15 fixture answers NO and so
  does the bit-17 one, while the other eleven answer YES. Bit 17 is Pushbutton, and nothing in the
  format's own name for it says it clears this.
* **`widgetControlType` is a priority, not a two-bit field read as a shift.** Neither bit answers 2
  (CheckBox), bit 17 alone answers 0 (PushButton), bit 16 alone answers 1 (RadioButton), and both at once
  answer 1. A shift of the pair by 16 would answer 0, 1, 2 and 3 for those four — so the **default of 2**
  is what told the two rules apart, and it is the default the host answers for a widget with no bits at
  all (`widget-noflags.pdf`).

## `activatableTextField` is not a bit either

It is a **text field that is not read-only**: `/FT` must be `/Tx` *and* bit 1 must be clear. Measured on

* six fixtures with one field type each, alone on its page — `/Tx` YES, `/Btn` NO, `/Sig` NO, a `/Ch`
  with an `/Opt` NO;
* the thirteen `/Tx` fixtures of `widget-flags.pdf`, of which the bit-1 one answers NO and the other
  twelve answer YES;
* every `/Link` in the harness, which has no `/FT` and answers NO.

The first version of this read it as `!readOnly` alone, and the harness found it on the first `/Link` it
met: the port answered YES where the host answers NO.

## A third skip in `-[PDFPage annotations]`, found by the same fixtures

`-[PDFPage annotations]` already skipped an annotation with no `/Rect` and a `/Line` with no `/L`. The
field-type fixtures found a third: **a choice widget is not surfaced at all.**

    widget-ftbtn0.pdf   /FT /Btn                  one annotation, surfaced
    widget-fttx1.pdf    /FT /Tx                   one annotation, surfaced
    widget-ftch2.pdf    /FT /Ch                   NO annotations
    widget-ftsig3.pdf   /FT /Sig                  one annotation, surfaced
    widget-ftch4.pdf    /FT /Ch  /Opt [(one) (two)]   one annotation, surfaced
    widget-ftch5.pdf    /FT /Ch  /Opt (a string)      NO annotations

So the skip is a `/Widget` whose `/FT` is `/Ch` **unless its `/Opt` is an array** — which is the format's
own requirement (Table 8.39 makes `/Opt` required for a choice field) and the host enforcing it, the same
shape as the `/Rect` skip. Six fixtures, one field type each and alone on its page, because a fixture
carrying all four field types can only say that *one* of them is missing.

## `fieldName` is SYNTHESISED, and that is the row worth reading

`PDFAnnotation.fieldName` does not read `/T`. Measured:

* a widget with **no `/T`** answers `"text0"`, `"text1"`, … `"text12"` by document position;
* a `/FT /Btn` widget answers `"button0"`, `"button1"`, …;
* a `/FT /Sig` widget answers **nil**;
* and a widget that **does** carry `/T` — `widget-values.pdf`'s first annotation, `/T (the field)` —
  answers the **synthesised** name anyway.

So the number is an index into an enumeration the document does not carry, and a port cannot reproduce a
number it cannot derive. The row is `inert` with that measurement as its reason rather than implemented
with an invented counter, which would be a different answer wearing the same name.

## The twenty-seven rows that are not here, and why each one waits

`registry/PDFKit/annotation11.json` carries all 36 rows of this batch: 9 `implemented` and 27 `inert`,
each with the host's measured answer in its `reason`. Grouped:

* **the `/V` and `/DV` pair.** `widget-values.pdf`'s first annotation carries `/V (typed)` and `/DV
  (preset)`; the host answers **nil** for the string value and an **empty string** for the default. One
  fixture, two different shapes, neither of them a reading of the key — so these wait for a measurement
  that says what the host reads instead.
* **`buttonWidgetState` and its string.** So far: `/AS /Yes` on a `/Btn` answers 1, `/AS /Off` answers 0,
  `/AS /On` answers **0**, and a `/Tx` widget with `/AS /Yes` answers −1. The mapping is not the format's
  off/on pair, and it needs a fixture per (`/FT`, `/AS`) combination before it is a rule.
* **the keys whose effect is not established** — `maximumLength` (`/MaxLen 7` → 0), `alignment`
  (`/Q 2` → 0), `choices` and `values` (`/Opt [(one) (two) (three)]` → empty), `open`, `caption`, `URL`.
  Each is written in a fixture and the host does not answer it from there, which says the key or the scale
  is something else and not what I assumed.
* **the three colours and the font**, which need the Mac Catalyst third binary and a colour reader for
  `/MK` `/BC`, `/MK` `/IC` and the `/DA` colour string. `backgroundColor` is the nearest: its key is
  already measured for `-[PDFAnnotation border]`, where a widget's `/BC` decides whether it has a border.
* **the geometry six** — `startPoint`, `endPoint`, `startLineStyle`, `endLineStyle`, `paths`,
  `quadrilateralPoints`. `/InkList` is a list of variable-length point runs and needs a bezier-path object
  the port does not carry; `PDFLineStyle` is a class the port does not carry; `/QuadPoints` is a flat array
  of eight numbers and no fixture writes one.
* **the two write paths**, `addBezierPath:` and `removeBezierPath:`, which need `-paths` first and then
  write to the document.
* **`iconType`, `markupType`, `stampName`**, whose keys are name strings no fixture writes.

## The run

    $ sh tests/backports/host/pdfkit-document/run.sh
      images differ by construction: host=/System/…/PDFKit.framework/…/PDFKit
                                      port=…/runs/pdfkit-document/port-side
      COMPARED 10251 MISMATCHES 0  (not compared: 133, expected to differ: 399, of which 72 compared from the Catalyst side)
      RED CONTROL ok: the comparison goes red on a mutated port, and names the key

133 fixtures. **Twenty-three named red controls name a flag or skip key**, among them one per member over
`widget-flags.pdf`'s first annotation, the three fixtures that pin `widgetControlType`'s priority
(`noflags`, bit 16, bit 17, `allflags`), the two that pin the inversions (bit 15 and bit 18), the one that
pins `radiosInUnison` off bit 26, the field-type fixtures that pin `activatableTextField`, and the three
annotation **counts** that pin the choice-widget skip — `widget-fttx1` (1), `widget-ftch2` (0) and
`widget-ftch4` (1).

The harness prints the nine members one key per line, for the reason the outline facts were lost the first
time round: a line carrying several `key=value` pairs registers as one key and drops the rest.
