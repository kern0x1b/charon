# PDFOutline over the document's /Outlines tree

## What it is, and what it took to reach

`PDFOutline` is a class neither band carries: `objc.inventory` reports it as carried by neither 6.1.3 nor
4.3, with `ZZNotAClassAnywhere` answering "not carried". So it is the port's own, like `PDFDocument`,
`PDFPage`, `PDFBorder` and the action family.

An outline is a **linked structure**, not a tree of nested dictionaries. PDF 1.7 Table 8.2:

* the catalog names a root dictionary through `/Outlines`, and that dictionary holds the `/First` of the
  top-level chain;
* every item names its `/Parent`, its `/Prev` and its `/Next`;
* an item's children are its `/First` … `/Last` chain, and `/Count` sits on the item itself.

So the fixtures cannot be written as a literal — the object numbers depend on how many items are above
them — and `build_outline()` in `tools/make-object-fixtures.py` emits the whole tree from a nested spec
with every number measured as it is written. Two arithmetic bugs in that generator are worth recording
because both were silent and both looked like "the host cannot read outlines":

* the first object a fixture may write was computed as `5 + page_count + 1` instead of
  `3 + 2 * page_count + len(annotations) + 1`, so **every reference in every outline fixture was one too
  high** and the host answered *no outline root at all*. The fixtures now print their own object numbers,
  so a wrong one is visible without running the host.
* the outline root dictionary takes its number **before** the items, because a top-level item's `/Parent`
  *is* that dictionary and its number has to be known before the items are written.

And one fixture bug in the older makers, which this family exposed: **the `/Pages` node carried no
`/Parent`.** A conforming writer emits one, and nothing can walk *up* from a page to the catalog without
it — which is exactly how `-outlineRoot` finds the `/Outlines`. Every fixture in the harness now has it.

## `-[PDFDocument outlineRoot]`, and the catalog

**There is no `CGPDFDocumentGetDictionary` in this SDK** — not in `CGPDFDocument.h`, and not in the
release's export table — so the trailer is not reachable directly and the catalog cannot be asked for by
name. The port walks **up**: `CGPDFPageGetDictionary` of page 1, then `/Parent` to the `/Pages` node, then
`/Parent` again to the object whose `/Type` is `/Catalog`, bounded at 64 steps. Every step is the
release's own dictionary reader.

The root is then an outline like any other — measured: it answers an **empty** `-label` because it carries
no `/Title`, `-numberOfChildren` from its `/First` chain, `-index` 0, a nil `-parent` and a `-document` —
so it is built by the same constructor the items are, with no parent and index 0.

## The members

| member | measured |
| --- | --- |
| `-init` | the header's designated initializer (`PDFOutline.h:20`); a fresh one answers an empty label, no children, index 0, closed, no parent, no document, no destination, no action |
| `-document` | an object for the root and every item of every fixture; nil for a fresh `-init` |
| `-parent` | an object for every item; nil for every root |
| `-numberOfChildren` | the length of the `/First` … `/Next` chain; 0 when there is no `/First` |
| `-index` | **zero-based** — the second child of `outline-open`'s root answers 1, the fourth of `outline-nocount` answers 3, the root answers 0 |
| `-childAtIndex:` | the item at that position |
| `-label` | the `/Title`; a **missing** `/Title` answers an **empty string**, not nil |
| `-isOpen` | see below — not the format's rule |
| `-destination` | the `/Dest`: an array is the destination, a name or string builds one with a nil page, anything else nil |
| `-action` | see below — the opposite order from an annotation's |

## `-isOpen`: the sign the other way round, and a rule about two keys

**PDF 1.7 Table 8.2 says a positive `/Count` means the item is CLOSED. The host reads it the other way
round.** `outline-signs.pdf` carries two items of the *same shape* — two children each — one with
`/Count +4` and one with `/Count -4`, and the positive one answers `isOpen` **YES** and the negative one
**NO**. So the first clause is: *an item with a `/Count` answers YES when the count is positive.*

The second clause took four fixtures, because "no `/Count`" turned out not to be enough. An item with no
`/Count` answers YES only when it has no `/Title` either:

| fixture | leaf | `/Title` | `isOpen` |
| --- | --- | --- | --- |
| `outline-titlekey` | under "None" | **absent** | **YES** |
| `outline-titlekey` | under "Empty" | `/Title ()` | NO |
| `outline-titlekey` | under "Text" | `/Title (leaf)` | NO |
| `outline-titlekey` | under "NoTitleNoF" | absent, and no `/F` either | YES |
| `outline-titlekey` | under "NoTitleWithDest" | absent, with a `/Dest` | YES |
| `outline-nocount` | A, B, C, D | all titled, none with a `/Count` | NO, NO, NO, NO |
| `outline-untitled` | four items deep | all absent | NO, NO, NO, **YES** |
| `outline-titled` | four items deep | all titled | NO, NO, NO, NO |

`outline-untitled.pdf` and `outline-titled.pdf` are the pair that isolates it: two chains of four items
with **the same shape**, differing only in whether each `/Title` is written, and the untitled one answers
YES at the leaf where the titled one answers NO three times out of three runs. The item's `/F` and
`/Dest` make no difference, which `outline-titlekey`'s last two rows fix.

So the rule is: **YES when the `/Count` is positive, and YES when there is no `/Count` and no `/Title`.**
Whether that is what the host means or a side effect of how it stores the flag is written down nowhere in
the SDK; this is what it answers, and each clause above is the fixture that fixes it.

## `-action`: the opposite order from an annotation's

An outline item and an annotation carry the same two keys, and **the host reads them in opposite
priorities**. `outline-shapes.pdf`'s "Child" carries `/Dest [3 0 R /XYZ 1 2 3]` *and* `/A << /S /GoTo /D
[3 0 R /Fit] >>`, and the host answers the **`/Dest`'s** 1, 2, 3 for both `-destination` and `-action`.

`ann-dest-and-a.pdf` is the annotation with the same pair, and it answers the **`/A`'s** `/Fit` — which is
what `PDFAnnotation11.m` implements, and why the two are separate rules rather than one shared one.

So: a `/Dest` gives a GoTo synthesised over it (Table 8.2: an item's `/Dest` *is* the destination of a
go-to action), and an `/A` is read only by an item with no `/Dest` — measured on `outline-open`'s "Two", a
`/URI` action, which answers `PDFActionURL`. An item with neither answers nil for both.

## `-childAtIndex:` out of range: the host RAISES

`-[PDFOutline childAtIndex:]` with an index past the last child throws `NSRangeException`, `"childAtIndex:
2 out of bounds"`. Measured, and it is a **boundary and not a match**: a differential cannot compare a
raised exception against an answer, so the harness does not ask one past the end, and a caller that gets
`nil` can say so where a caller that gets an exception cannot. The row says the same.

## What is NOT here, and why

* **`-insertChild:atIndex:` and `-removeFromParent`** — the two write paths. Both are registered `inert`
  with that reason: nothing in this port writes a PDF, so a method that changed an outline would either
  answer without changing the file behind it or have to grow a writer. It is the same boundary
  `PDFAnnotation`'s `-setValue:forAnnotationKey:` rows name.
* **`-childAtIndex:`'s exception**, as above.

## The run

    $ sh tests/backports/host/pdfkit-document/run.sh
      images differ by construction: host=/System/…/PDFKit.framework/…/PDFKit
                                      port=…/runs/pdfkit-document/port-side
      COMPARED 7505 MISMATCHES 0  (not compared: 115, expected to differ: 345, of which 72 compared from the Catalyst side)
      RED CONTROL ok: the comparison goes red on a mutated port, and names the key

113 fixtures, 98 of them this series' — 3 box, 3 hand-written text, 9 annotation and 2 conforming-writer
text from before, plus 98 from `tools/make-object-fixtures.py`, each with every xref offset measured from
the object bytes as they are written.

94 named red controls, 22 of them naming an outline key. Two of them exist because this family got two
things wrong that a control has to catch:

* `outline-signs.pdf.c0.outline.isOpen` and `outline-signs.pdf.c1.outline.isOpen` — the two items of the
  same shape with opposite `/Count` signs. A control on one of them proves the flag is read at all; a
  control on both together is what would catch a sign flip.
* `outline-untitled.pdf.c0.c0.c0.c0.outline.isOpen` against `outline-titled.pdf.c0.c0.c0.c0.outline.isOpen`
  — the same position in the untitled chain and in the titled one. Those two keys differ **only** because
  of the `/Title`, so a mutant that made them equal is caught by planting on either.

The harness's own printing had to be fixed twice for this family, both times in the same way: a line
carrying several `key=value` pairs registers as **one** key and loses the rest, so every outline fact is
printed one key per line — the shape every other fact in this harness already had.