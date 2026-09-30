# PDFDocument and PDFPage over the release's own CGPDFDocument

## What the subtraction said, and how

`objc.inventory` — an Objective-C class census — reports `PDFDocument` and `PDFPage` as carried by
**neither** 6.1.3 nor 4.3, with `ZZNotAClassAnywhere` and `CGPDFKitNotAThing` answering "not carried".
So these are the port's own classes.

The same census is the **wrong test** for the CoreGraphics side, because `CGPDFDocument`, `CGPDFPage`
and `CGPDFScanner` are C types that no Objective-C inventory can see. The dyld export tables answer
instead, and they answer that the substrate is the release's own: `CGPDFDocumentCreateWithURL`,
`CGPDFDocumentGetNumberOfPages`, `CGPDFDocumentGetPage`, `CGPDFDocumentRelease`, `CGPDFPageGetBoxRect`,
`CGPDFPageGetDictionary` and `CGPDFScannerCreate` are exported by **both** bands, with
`CGPDFKitNotAFunction` answering "not in the release".

**And the two scanner readers are not:** `CGPDFScannerScanString` and `CGPDFScannerGetString` are
exported by neither. So string extraction through the scanner is not feasible on this release, `-string`
answers only what the port holds, and the scanned extraction is owed. No row claims otherwise.

## The harness, and why it is two binaries

One binary with the port's objects compiled in under renamed class names cannot work: the host
framework's PDFKit and the port's `@interface` share a translation-unit universe, and a small integer
ended up in the port's `CGPDFDocumentRef`. So there are two, with nothing of the other side in either
process, and the images `dladdr` names are asserted to differ before any fact is compared.

    $ sh tests/backports/host/pdfkit-document/run.sh
      images differ by construction: host=/System/…/PDFKit.framework/…/PDFKit
                                      port=…/runs/pdfkit-document/port-side
      COMPARED 10 MISMATCHES 0  (not compared: 15)

Ten facts the host can answer, all agreeing: `pageCount` on three fixtures (1, 1, 3), each document an
object, and `pageAtIndex:` one past the end nil on all three. The fifteen it cannot are named per line —
the host's `PDFDocument` has no `documentAttributes` and no `documentAttribute:`, and its `PDFPage` has no
`mediaBox` and no `cropBox`.

## What the crash was, and what the ownership change is

**The crash was missing bodies.** Repeated rewrites of PDFDocument11.m dropped the definitions of
-charon_readAttributes, -documentAttribute:, -pageAtIndex: and -pageCount while CharonPDFKit.h kept
declaring them, and `-respondsToSelector:` answers YES for a declared method with no body — which is how
a method that does not exist reached a differential printing "the port has it=1". The crash was always

    -[PDFDocument charon_readAttributes]: unrecognized selector sent to instance …

and the compiler's `-Wincomplete-implementation` was naming them while I read CF ownership.

**The ownership change is unproven either way.** The page holds its `CGPDFPageRef` as a Get, owns a
`CGPDFDocumentRetain`, and the document keeps the pages it handed out. That is correct by the CF rules on
its own — a `Get` is not owned, and the page needs a document reference to outlive its document, which
the header's `weak` document property (PDFPage.h:70) implies. But its red control no longer fires:

    the true inverse - the page retain/release AND pageAtIndex's release of the Get -  exit=0
    COMPARED 10 MISMATCHES 0  (not compared: 15)

so nothing here shows the ownership was what made the run pass, and the earlier bisect
("pageAtIndex:0, page kept" 0 / "pageAtIndex:0 then dropped" 139) was bisecting a tree that was also
missing four methods. The ownership is kept because it is right by the rules; it is not claimed as a
cure, because it is not shown to be one.

## The ownership as it stands

The page holds the `CGPDFPageRef` as a **Get** — `CGPDFDocumentGetPage` hands back a page the document
owns and no reference to it — and owns only a `CGPDFDocumentRetain`, released in its own `dealloc`. The
document keeps the pages it handed out. The bisect that found this:

    pageAtIndex:0, page kept          exit=0     a page that outlives its document is fine
    pageAtIndex:0, page dropped first  exit=139   the same call, and 139

Every count in the CF audit was balanced; the **order** was wrong, which is why reading the audit found
nothing. A `CGPDFPageRef` released while its document is alive is the direction CoreGraphics does not
support. Both controls now bite:

    control A, the true inverse (the page retain/release AND pageAtIndex's release re-added)  exit=1
    control B, pageCount planted to answer one more than the release says
      DIFFER  charon-fixture-3.pdf.pageCount  host='3' port='4'
      COMPARED 10 MISMATCHES 3  (not compared: 15)                                             exit=1

## What -init answers, measured on this host

The three ways the header's own comment names a document being made — "either the init method,
initWithURL:, or initWithData:" — do not agree with each other, and the host says which is which:

    [[PDFDocument alloc] init] -> an object  pageCount=0  document={
    }
    [PDFDocument new]          -> an object  pageCount=0
    -initWithData:nil           -> nil
    -initWithURL:nil            -> nil

So `-init` is a third **designated** initializer that makes an empty document, while nil data and a
nil URL give nil. All three call `[super init]` and none calls another, which is the shape
`-Wobjc-designated-initializers` asks for; the private `-charon_setUpWithData:` is an ordinary method
for the same reason.

## The fixtures carry text now, and one comparison is owed

`make-pdf.m` selected a font before drawing, so every page of the fixture carries a **literal** string
through a `Tj` - `BT 0.0002 Tc 12 0 0 12 20 752 Tm /TT1 1 Tf (page 1) Tj 0 Tc ET` - and
`check-fixture.m` reads each page's stream back through `CGPDFStreamCopyData` to prove it, because the
file's own bytes hold the compressed form and a grep over them sees nothing.

### The box comparison, and what the host does

`-[PDFPage boundsForBox:]` is now compared on both sides for all five kinds `CGPDFBox` declares, on
three fixtures: one naming every box, one with no `/CropBox`, and one rotated 90. The host's
`-[PDFPage boundsForBox:]` and `CGPDFPageGetBoxRect` were measured to **agree on every kind in every
case**, so the port's one call per kind is already right and it needed no change. What the measurement
shows: a named `/BleedBox` is honoured, a page with no `/CropBox` answers its MediaBox, and `/Rotate 90`
is reported through `rotation` and left out of every box.

The five box kinds are separate registry rows and all of them are `implemented` on that comparison;
`PDFPage.mediaBox` and `PDFPage.cropBox` stay `inert` with the reason the host has neither as a
property, and their row now points at the comparison that does cover the box they wrap.

### Owed

**The fixture writer still draws text through the deprecated calls.** `CGContextSelectFont` and
`CGContextShowTextAtPoint` are both marked deprecated and "No longer supported" in the SDK header, so
`make-pdf.m` is on a path that stops working, and `-Wall` now says so on every build of it. The
fixtures should be drawn with CoreText or with the CGPDFContext text operators instead. Not this
slice, and nothing here depends on it: the boxes the run compares come from the page dictionary and
not from what the writer drew.

**Owed, and unchanged: the `-string` extraction** The host's `PDFPage` has `-boundsForBox:` and answers it
(`responds to -boundsForBox:: 1`) while it has no `-mediaBox` or `-cropBox` (`responds to -mediaBox: 0`),
so the run is probing two selectors the host lacks and leaving a fact it can answer on the floor. The
comparison is the next slice, over all five box kinds `CGPDFBox` declares, with the rects compared
numerically.

## The rows

Three are `implemented`, and only those three: `PDFDocument`, `-pageCount`, `-pageAtIndex:` — the facts
the host answers and the run compares. The other seven are `inert` with the reason stated, because the
host answers none of them and a row may not say a host compared something no host fact covers.
`PDFPage.string` is among them, and its effect carries the scanner finding in full.
