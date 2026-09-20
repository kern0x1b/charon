# UISearchTextField, UISearchToken and the search bar's text field, iOS 13.0

Introduced in iOS 13.0: the text field of a search bar, which can hold tokens - small labelled chips - before the text. iOS 6 has the
field inside its search bar but no tokens; the port carries the class as a `UITextField` subclass that keeps the tokens and draws each as a
plain chip before the text.

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), held against the backport by `tests/backports/host/uikit2` (the `search` and
`searchcategories` groups), and the header of SDK 16.4.

## UISearchToken, as UIKit does

- `+tokenWithIcon:text:` takes a nil icon and a nil text; `representedObject` is nil and kept as set. A token is not copyable, is not
  secure coding and two tokens are equal only when they are the same object; `-init` makes a blank one.
- The system's `+tokenWithIcon:text:` answers an object of a private subclass (`_UISearchToken`), so its description names that class;
  the port's is a `UISearchToken`. The text is a copy; the icon is kept.

## UISearchTextField, as UIKit does

- A field made with `-initWithFrame:` has a rounded border, a clear button while editing and a magnifier as its left view, always shown;
  `allowsCopyingTokens` and `allowsDeletingTokens` are YES and `tokenBackgroundColor` is the system grey, RGB 142 142 147, until set; setting nil
  brings it back. The port draws the magnifier itself.
- `tokens` is a copy; nil is the empty array; the same token may be there twice. `text` **excludes** the tokens.
- `-insertToken:atIndex:` and the others raise as the system's do: a nil token, a negative index for remove and position:
  `NSInternalInconsistencyException`, "Invalid parameter not satisfying: token != nil" and "... tokenIndex >= 0"; an index out of range:
  `NSRangeException` "Token index 10 out of range: [0, 3)" for insert, remove and replace, `NSInvalidArgumentException` "Token index 4 out of range [0, 4)" for
  the position of a token. An index one past the end of an insert or replace, or the end itself for a remove, raises the message of
  the array the host keeps them in ("NSMutableRLEArray ...: Out of bounds").
- `-replaceTextualPortionOfRange:withToken:atIndex:` takes the text of the range out and puts the token in; a nil range or token raises.
- `searchSuggestions` arrived in iOS 16 and is not answered.

## What the port does

- Each token is a chip - a rounded label in the token background with white text, at most 120 points wide - laid out after the magnifier; the
  text, the placeholder and the editing rectangle start after the last chip, and never leave the text less than 30 points.
- A backspace with the caret at the start and no text deletes the last token when `allowsDeletingTokens` is YES, and sends the field's editing-changed event.
- `allowsCopyingTokens` is kept and does nothing: no token can be selected, so `-searchTextField:itemProviderForCopyingToken:` is never sent,
  and no paste item is made, so `-setSearchTokenResult:` is never sent.

## Where it differs

- Positions are the release's own, counted over the text: the tokens are **not** characters of the document. `positionOfTokenAtIndex:` answers the
  start of the document for every token, `textualRange` is the whole document, and `tokensInRange:` answers every token for a range that starts at
  the start of the document and none for one that does not or for the range `textualRange` answered (which the host's tokens, being before it, are not in).
  The host counts each token as one position, so a range over just the first position holds one token there and all of them here.
- Tokens are not selected, dragged, copied or shown as bubbles with an icon: the icon is kept and not drawn.

## UISearchBar.searchTextField

- Answers the text field the search bar holds - the release's `UISearchBarTextField`, found among its subviews at any depth - and nil when
  it finds none. That class is not a `UISearchTextField`, so the port gives the field a subclass of its own class, made once, with the token members
  added, and switches the field to it: the tokens are **kept and not drawn** there, and a backspace does not delete one. The object is the same each
  time it is asked, and it answers `isKindOfClass:` for its own class and not for `UISearchTextField`. A field that is already a `UISearchTextField` is
  answered as it is.

## UISearchController

- `automaticallyShowsCancelButton`, `automaticallyShowsSearchResultsController` and `showsSearchResultsController` of iOS 13 are carried by
  `UISearchController` itself; see `UISearchController.md`.
- `automaticallyShowsScopeBar` is kept, starts YES as the header says (the host, a Mac, starts it NO) and changes nothing: the controller never shows
  the scope bar of its search bar, and says so once in the log when the property is set.
