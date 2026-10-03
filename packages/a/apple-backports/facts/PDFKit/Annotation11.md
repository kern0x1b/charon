# PDFAnnotation's widget members, and what the rest of the category needs

## What is here

Nine of the 38 members `PDFAnnotation (PDFAnnotationUtilities)` declares, and they are the nine that are
**`/Ff` bit reads**. Every one is measured on the host over `widget-flags.pdf`, which carries **one
annotation per bit with only that bit set** - thirteen bits, thirteen annotations - plus
`widget-allflags.pdf`, which carries every bit at once. That shape is the whole reason these are
measurable: a fixture with all the bits set answers every member YES and proves nothing.

The fixture table's first version wrote each bit as a **list**, so `str(bits)` produced `"[1]"` and the
dictionaries carried `/Ff [1]` - an array where the format wants an integer - and the host then answered
every flag member NO on every fixture, which read as "the host ignores /Ff". Two more fixture bugs in the
same family, both silent and both looking like a host behaviour:

* `WIDGET_FIELD_TYPES` passed the field type both as the helper's argument and as an extra pair, so every
  dictionary carried `/FT` twice and the host answered three of the four field types rather than four.
* the one-field-type-per-fixture loop named all three `/Ch` fixtures `widget-ftch.pdf`, so each overwrote
  the last and only the first was ever measured.

## The bits, and what the fixtures add to the table

The NAMES below are the format's own, and an earlier version of this page had two of them wrong: it
called bit 16 "RadioInUnison" and bit 26 "RichText" as if each had one name. **Table 8.39's bit 16 is
Radio**, and **bit 26 is RadiosInUnison in the BUTTON field table and RichText in the TEXT field table.**
So two of the three members the earlier version called "not what the table says" ARE the table's rule, and
the claim itself was wrong.

| `/Ff` bit | value | the member that moves | fixture |
| --- | --- | --- | --- |
| 1 ReadOnly | 1 | `readOnly` -> YES | annotation 0 |
| 2 Required | 2 | - no member reads it | annotation 1 |
| 13 Multiline | 4096 | `multiline` -> YES | annotation 2 |
| 14 Password | 8192 | `isPasswordField` -> YES | annotation 3 |
| 15 NoToggleToOff | 16384 | `allowsToggleToOff` -> **NO** | annotation 4 |
| 16 Radio | 32768 | `widgetControlType` -> 1 | annotation 5 |
| 17 Pushbutton | 65536 | `widgetControlType` -> 0, `allowsToggleToOff` -> **NO** | annotation 6 |
| 18 Combo | 131072 | `listChoice` -> **NO** | annotation 7 |
| 19 Edit | 262144 | - | annotation 8 |
| 21 FileSelect | 1048576 | - | annotation 9 |
| 22 MultiSelect | 2097152 | - | annotation 10 |
| 25 Comb | 16777216 | `comb` -> YES | annotation 11 |
| 26 RadiosInUnison (buttons) / RichText (text) | 33554432 | `radiosInUnison` -> YES | annotation 12 |

**Two of the members ARE the table's rule.** `radiosInUnison` reads bit 26, which is RadiosInUnison in
the button table - and the host reads it in a TEXT field too, which is where the same bit is called
RichText (`widget-flags.pdf` is all `/Tx`). `widgetControlType` is the table's mapping of the two bits:
Pushbutton -> 0, Radio -> 1, neither -> CheckBox.

**And what the fixtures add is only two things the tables cannot say:**

* **Both bits at once answer `RadioButton`.** `widget-allflags.pdf` carries bit 16 and bit 17 together and
  answers 1. A two-bit field read as a shift would answer 0, 1, 2 and 3 for the four shapes rather than
  0, 1, 2 and 1, and the **CheckBox default** is what tells the two rules apart.
* **Bit 17 clears `allowsToggleToOff`.** The table says bit 15 NoToggleToOff and says nothing about a
  pushbutton. The bit-15 fixture and the bit-17 fixture each answer NO while the other eleven answer YES.

## `activatableTextField` is not a bit either

It is a **text field that is not read-only**: `/FT` must be `/Tx` *and* bit 1 must be clear. Measured on

* six fixtures with one field type each, alone on its page - `/Tx` YES, `/Btn` NO, `/Sig` NO, a `/Ch`
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

So the skip is a `/Widget` whose `/FT` is `/Ch` **unless its `/Opt` is an array** - which is the format's
own requirement (Table 8.39 makes `/Opt` required for a choice field) and the host enforcing it, the same
shape as the `/Rect` skip. Six fixtures, one field type each and alone on its page, because a fixture
carrying all four field types can only say that *one* of them is missing.

## `fieldName`: the `/T` IS read, and the coordinator's challenge is what found it

The previous commit registered this row `inert` on the reading that **the host synthesises the name
rather than reading it**, because a widget with no `/T` answered `"text0"`, `"text1"`, `"button0"` and a
widget that DID carry `/T` answered the synthesised name too. That reading was wrong, and it was a
fixture defect of exactly the kind this family keeps producing.

**The fixture's bytes, as asked.** The first version of `widget-values.pdf`'s first annotation carried:

    /Subtype /Widget /Rect [40 40 240 70] /F 4 /FT /Tx /FT /Tx /V (typed) /DV (preset) /MaxLen 7 /Q 2
      /Opt [(one) (two) (three)] /T (the field) /TU (alternate) /DA /Helv 12 Tf 0 g

and the `/T` is a **literal PDF string**, so "written as a name" was never the cause. Two things in that
line are, and they are the third and fourth fixture bugs of this family:

* **`/FT /Tx` twice** - the helper writes the field type and the fixture's extra pairs wrote it again.
* **`/DA /Helv 12 Tf 0 g`** - and this is the one that mattered, though not for the reason the first
  version of this page said. **`/DA` is a TEXT STRING**, so the format spells it
  `/DA (/Helv 12 Tf 0 g)`, and this fixture wrote the content-stream operators **bare into the dictionary**.
  That is a syntax error rather than a reading: `CG_PDF_VERBOSE=1` says **`encountered unexpected symbol
  'Tf'`** and the host then answers **NO ANNOTATIONS AT ALL** for the page - so the widget carrying `/T`
  was not in `-annotations`, and the two that remained named nothing.

  **Written the way the format makes it, a `/DA` is read like any other key.** `widget-t-extra-DAstring`
  carries `/DA (/Helv 12 Tf 0 g)` beside `/T (the field)`, and the host answers **one annotation and the
  field name "the field"**, with nothing on `CG_PDF_VERBOSE`. And `widget-values.pdf` with its `/DA` as a
  string keeps **all three** of its annotations, and its first - the one carrying `/T (the field)` -
  answers **"the field"**.

  So the earlier sentence here, that a `/DA` is not readable in an annotation dictionary at all, was a
  statement about the fixture and not about the host, and it is withdrawn. The reading the `/DA` rows need
  - `font`, `fontColor` and the `/DA` colour - is measured against this spelling.

With the `/DA` gone, six fixtures fix the rule:

| fixture | what it carries | the host answers |
| --- | --- | --- |
| `widget-t-literal` | `/T (the field)` on the widget | `the field` |
| `widget-t-empty` | `/T ()` | the **empty string** |
| `widget-t-name` | `/T /TheField`, a PDF **name** | not read - it synthesises |
| `widget-t-merged` | the widget's `/Parent` is a field with `/T (parent field)` | `parent field` |
| `widget-t-mergedname` | both, and the widget has `/T (child too)` too | `parent field.child too` |
| `widget-t-extra-*` | `/T (the field)` plus one of `DA`, `TU`, `Opt`, `Q`, `MaxLen`, `V`, `DV`, `F` | `the field` in all nine |

So the `/T` of the merged field and widget is read, **the parent's first and the widget's own appended
with a dot**, both as PDF strings only. The port implements that reading and the harness compares it
over the twelve fixtures that name their widgets.

**And the answer for a widget that names NOTHING is still not implementable** - which is why the row is
inert rather than implemented, and why the reason on it is rewritten rather than removed. The synthesised
name's number is a **process-global counter**. Five fixtures opened in order in one process:

    three widgets alone          text0, text1, text2
    a link then two widgets       text3, text4
    a widget, a link, a widget    text5, text6
    one widget alone              text7
    five annotations, two widgets text8, text9

so the counter does not restart per document and is not a property of any file. The earlier reason said
"by document position", and `widget-mixed.pdf` is the fixture that shows that is wrong: its two widgets
are the **third and fifth** of five annotations and answered `text7` and `text8` in that run, because four
files had been opened before them.

**The harness therefore prints a `fieldName` key only over the fixtures that name their widgets**, and the
list is spelled out in `host.m` rather than being a prefix test. A prefix test swept in
`widget-t-name.pdf`, whose `/T` is a NAME and so names nothing, and the differential caught it - the same
way it catches everything else here.

## The 27 rows that are not implemented, and why each one waits

Each of the 27 carries the host's measured answer in its `reason` in
`registry/PDFKit/annotation11.json`. Grouped:

* **the `/V` and `/DV` pair.** `widget-values.pdf`'s first annotation carries `/V (typed)` and `/DV
  (preset)`; the host answers **nil** for the string value and an **empty string** for the default. One
  fixture, two different shapes, neither of them a reading of the key - so these wait for a measurement
  that says what the host reads instead.
* **`buttonWidgetState` and its string.** So far: `/AS /Yes` on a `/Btn` answers 1, `/AS /Off` answers 0,
  `/AS /On` answers **0**, and a `/Tx` widget with `/AS /Yes` answers -1. The mapping is not the format's
  off/on pair, and it needs a fixture per (`/FT`, `/AS`) combination before it is a rule.
* **the keys whose effect is not established** - `maximumLength` (`/MaxLen 7` -> 0), `alignment`
  (`/Q 2` -> 0), `choices` and `values` (`/Opt [(one) (two) (three)]` -> empty), `open`, `caption`, `URL`.
  Each is written in a fixture and the host does not answer it from there, which says the key or the scale
  is something else and not what I assumed.
* **the three colours and the font**, which need the Mac Catalyst third binary and a colour reader for
  `/MK` `/BC`, `/MK` `/IC` and the `/DA` colour string. `backgroundColor` is the nearest: its key is
  already measured for `-[PDFAnnotation border]`, where a widget's `/BC` decides whether it has a border.
* **the geometry six** - `startPoint`, `endPoint`, `startLineStyle`, `endLineStyle`, `paths`,
  `quadrilateralPoints`. `/InkList` is a list of variable-length point runs and needs a bezier-path object
  the port does not carry; `PDFLineStyle` is a class the port does not carry; `/QuadPoints` is a flat array
  of eight numbers and no fixture writes one.
* **the two write paths**, `addBezierPath:` and `removeBezierPath:`, which need `-paths` first and then
  write to the document.
* **`iconType`, `markupType`, `stampName`**, whose keys are name strings no fixture writes.

## The run

    $ sh tests/backports/host/pdfkit-document/run.sh
      images differ by construction: host=/System/.../PDFKit.framework/.../PDFKit
                                      port=.../runs/pdfkit-document/port-side
      COMPARED 11511 MISMATCHES 0  (not compared: 152, expected to differ: 456, of which 72 compared from the Catalyst side)
      RED CONTROL ok: the comparison goes red on a mutated port, and names the key

133 fixtures. **Twenty-three named red controls name a flag or skip key**, among them one per member over
`widget-flags.pdf`'s first annotation, the three fixtures that pin `widgetControlType`'s priority
(`noflags`, bit 16, bit 17, `allflags`), the two that pin the inversions (bit 15 and bit 18), the one that
pins `radiosInUnison` off bit 26, the field-type fixtures that pin `activatableTextField`, and the three
annotation **counts** that pin the choice-widget skip - `widget-fttx1` (1), `widget-ftch2` (0) and
`widget-ftch4` (1).

The harness prints the nine members one key per line, for the reason the outline facts were lost the first
time round: a line carrying several `key=value` pairs registers as one key and drops the rest.
