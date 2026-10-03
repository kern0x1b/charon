# PDFSelection: the text a search answers, and the ranges it answers it in

Every number on this page was measured on this Mac's own PDFKit, through `tools/host-find.m`, over
fixtures that `make-text-fixture.m` writes with the release's own `CGPDFContext` - a conforming writer,
so the content streams carry a correct `/Length`. The run output the numbers come from is
`.agent-work/runs/v-pdfsel/host-find-final.txt` in the branch that measured them, and the predictions
that were written BEFORE each round of it asked the host are in
`.agent-work/runs/v-pdfsel/find-predictions.md`, in the same directory.

## The rule `-findString:withOptions:` answers, and how it was pinned

The starting point was eight observations that no rule over the characters explains: `shared` took no
trailing space while `third` did, and both are followed by one space and then a letter in the same
fixture. So a family of fixtures was built first - `cgfixture-words`, `cgfixture-gap`,
`cgfixture-lines2`, `cgfixture-tail`, `cgfixture-cross`, and later `cgfixture-blank`,
`cgfixture-inline`, `cgfixture-lead`, `cgfixture-tailpair`, `cgfixture-tab` - and every one of the 136
rows was predicted before it was asked. The rule that came out of them:

> **`findString:withOptions:` answers one selection per occurrence, and each selection's range is the
> matched substring in the page's own `-string` coordinates - extended by ONE character when the
> character after the match is a line break.**

Every part of that is measured:

| what | measured | where |
| --- | --- | --- |
| no snapping backward | `pha` in `alpha` is `{7,3}` and not `{5,5}` | cgfixture-words |
| no snapping forward | `al` is `{5,2}`, `alph` `{5,4}`, `bra` `{11,3}`, `charli` `{17,6}`, `ze` `{0,2}` | cgfixture-words |
| no extension over a space | `zero` `{0,4}`, `bravo` `{11,5}`, `charlie` `{17,7}`, `shared` `{0,6}` and `{11,6}`, `third` `{22,5}` | cgfixture-words, cgfixture-lines |
| ONE extension, over a line break | `two` `{4,4}`, `four` `{14,5}`, `one` `{7,4}`, `shared one` `{0,11}`, `alpha` `{0,6}` on the blank fixture, `bravo` `{6,6}` on the tab fixture | cgfixture-lines2, cgfixture-lines, cgfixture-blank, cgfixture-tab |
| and nothing else is taken | `alpha` `{0,5}` where the character after it is a NUL, not a break | cgfixture-inline, cgfixture-tab |
| one occurrence per match, in order | three `alpha` -> three selections at `{5,5}`, `{25,5}`, `{31,5}` | cgfixture-words |
| the same answer wherever the same word is | the three `alpha` ranges are three different offsets and one shape: the extension is a function of the match, not of where it sits | cgfixture-words |
| not found is an EMPTY array | `nothing here`, `o t`, `a  b`, `al.ha` -> `count=0` | several |
| a needle never spans a page | `bravo charlie` over two pages -> `count=0` | cgfixture-cross |
| a case-insensitive match answers the DOCUMENT's spelling | `ALPHA` with `NSCaseInsensitiveSearch` -> three selections, each `string` = `alpha` | cgfixture-words |
| `.` is literal either way | `al.ha` finds nothing with options 0 and nothing with `NSLiteralSearch` | cgfixture-words |
| `NSBackwardsSearch` reverses the array, not the ranges | `alpha` -> `{31,5}`, `{25,5}`, `{5,5}` | cgfixture-words |

`findString:fromSelection:withOptions:` carries on from a selection and starts at the document's
beginning when the selection is nil, which is `PDFDocument.h:277` in prose:

| call | answers |
| --- | --- |
| `alpha` from nil, fresh document | `{5,5}`, the first match |
| `page` from nil on the three-page fixture | `{0,4}`, page 0's match |
| `alpha` from nil, `NSBackwardsSearch` | `{31,5}`, the last match |
| from the match at `{5,5}` | `{25,5}`; from `{25,5}` -> `{31,5}`; from `{31,5}` -> nil |
| backwards, on the three-page fixture | page 2's match -> page 1's -> page 0's, so a search crosses PAGES even though a needle does not |
| a search before it | changes nothing: `findString:` then `from=nil` answers the first match again |

There is **no state left behind by a search**. An earlier draft of this page claimed a find cursor,
because the probe's own label printed `match#0` for both "the first match" and "no selection" and the two
were read as one; the label is now a named constant and the claim is retracted.

## What the page's own text is, which the ranges are offsets into

The ranges above are offsets into the page's `-string`, so the walk that produces it is part of this
family. Two things the host does that a walk which joins runs verbatim does not:

- **each LINE is trimmed and its interior whitespace is collapsed.** `alpha  bravo` (two drawn spaces)
  reads `alpha bravo`; `" alpha bravo "` reads `alpha bravo`; `"alpha "` on one line and `bravo` on the
  next reads `alpha\nbravo`, so the trailing space is gone; and `"alpha "` followed by `"beta"` at the
  SAME y reads `alpha beta`, so the trim is of the LINE and not of each run.
- **a control byte is a NUL, not whitespace.** `CGContextShowTextAtPoint` writes a newline or a tab in a
  show string as `(\000)`, and the character reaches the text as a NUL: cgfixture-inline's `-string` has
  length 11 and prints as its first five characters, and the search does not extend over it.

And the seams that were already there, still true: runs at the same y join with nothing, runs at
different y join with one newline and come out sorted by y descending with a tie in drawing order, and a
show that draws nothing is not written at all - cgfixture-blank's three drawn lines produce two
operators and a `-string` of 11 characters, not 12.

## The other members this family needs

| member | the host answers | what it takes |
| --- | --- | --- |
| `pages` | `[the page]`, and for a page the selection does not cover the selection has **no** text range on it | the page a match was found on |
| `rangeAtIndex:onPage:` | the match's own range, per page | the walk's characters |
| `numberOfTextRangesOnPage:` | 1 for a match inside one line, 0 for a page the selection does not cover | the same |
| `boundsForPage:` | `20.0000,357.2400,36.7080,12.0000` for `page 1`; `+inf,+inf,0,0` for a page the selection does not cover | per-character ADVANCES: 36.7080 is six Helvetica glyphs at 12pt and the y is the font's ascent below the baseline, not the 360 the text was drawn at |
| `selectionsByLine` | one selection per line the match covers; each line's `string` is the line's text WITHOUT the break that ends it, while the line's RANGE carries that break | the walk's lines |
| `attributedString` | the selection's own string with a font attribute over the whole of it: `Helvetica` at 12pt | the name `Tf` names and the size beside it |
| `color` | nil for every selection a find returns | nothing; the header's own default drawing colours are the host's |
| `initWithDocument:` | a fresh object: nil string, 0 pages, nil color | nothing |
| `copy` | a NEW object with the same string | `NSCopying` over the ranges |

## The write and draw methods

`addSelection:`, `addSelections:`, `extendSelectionAtEnd:`, `extendSelectionAtStart:` and
`extendSelectionForLineBoundaries` mutate a selection the caller holds, and `drawForPage:active:` and
`drawForPage:withBox:active:` draw into a context. A selection built by a find is exactly the object
those five mutators are documented for (`PDFSelection.h:66-79`: "Add the selection to this selection",
"Selections can be extended right off onto neighboring pages"), so they are reachable and are not the
write-into-the-file paths that `PDFOutline`'s two were: what they need is a real range list a selection
can grow, which is what the range model above is. `drawForPage:` needs a `CGContext` and a
`PDFDisplayBox`, which a port that reads documents has no way to be handed; those two are the same shape
as the outline's write paths and say so.