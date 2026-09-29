# UIDocumentBrowserViewControllerDelegate, and the rest of the document browser

## What this piece declares

`UIDocumentBrowserViewControllerDelegate` as the 26.2 header declares it: seven questions, every
one of them `@optional`, including the two pairs spelled two ways — `didPickDocumentURLs:` (11.0) and
`didPickDocumentsAtURLs:` (12.0), and nothing else in this protocol has a second spelling.

The declaration is a **transcription**, not a design, and it lives in
`UIKit/UIDocumentBrowserViewControllerDelegate.h` because a 6.1.3-era SDK has no
UIDocumentBrowserViewController at all. `CharonDocumentBrowserTypes.h` carries the one enum and the
three `@class` lines the questions refer to, with no condition on which SDK is in use, so the same
file works against every SDK the port builds with.

Why a transcription at all: the 16.4 SDK this package builds against does not carry
UIDocumentBrowserViewController, so the names are not visible to a translation unit here and an
application compiled against the lifted header links the protocol through this declaration.

## Eight rows, and the check that justifies them

`registry/UIKit/documentbrowser.json` carries **eight**: the protocol and its seven questions, at the
header's own availability of 11.0. The seven are **counted from the AST's selector set**, not written
out by hand, so the file and the compiler cannot disagree about how many there are.

`tests/backports/host/documentbrowser/ast_check.py` is the gate, and it is green with both controls
named:

    UIDocumentBrowserViewControllerDelegate: header 7 selectors, port 7
      required: header 0, port 0
      the independent count of the port's method lines: 7
      control, @optional flipped: documentBrowser:didRequestDocumentCreationWithHandler: is now required
      control, documentBrowser:applicationActivitiesForDocumentURLs: removed: the AST went 7 -> 6 and named it
    PASS: the port's declaration is the header's, selectors and optionality

The optionality is read from the compiler and not from the file: an empty conformer compiled with
`-Wprotocol` is warned about for every `@required` method and for none of the optional ones, so the
selectors those warnings name are the required set. Measured directly on the flipped copy, seven
warnings appear and none appear unflipped, and **all seven of this protocol's questions are
optional**, so the required set is empty on both sides — which is what the header says and what the
port now agrees with.

## The fifteen rows that stay absent

The other **fifteen** of the twenty-three are not claimed: the transition controller's two properties
(`loadingProgress`, `targetView`), the view controller's nine properties, and the four instance
methods, with the two `transitionControllerForDocument…` spellings counting as two rows for one
method. A class is not `implemented` until all of its members are, so those wait for the pieces that
build it: the transition controller's two properties, then the nine properties, then the instance
methods, each with its own rows at the header's own availability and its own check.



## What the check compares, and what it cannot

Both sides are read the same way. The selector set comes from clang's JSON AST keyed by
`mangledName`. The required/optional split comes from the compiler and not from the file: an empty
conformer compiled with `-Wprotocol` is warned about for every `@required` method and for none of the
optional ones, so the selectors those warnings name are the required set. There is no line arithmetic
anywhere, because the compiler already knows.

The two sides differ only in the translation unit — the header's imports UIKit, the port's imports
Foundation and the port's own headers — and that difference is the whole reason the check can mean
anything. With the umbrella in the port's unit, the SDK's declaration of this protocol shadows the
port's and the compiler reads only the SDK's copy: the port's transcription checked against itself.
