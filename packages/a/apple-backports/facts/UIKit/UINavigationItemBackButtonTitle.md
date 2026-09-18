# The back button title of a navigation item, iOS 11.0

Introduced in iOS 11.0: an item can say, in one string, what the back button
should read when the next item is pushed on top of it - without building a
whole bar button item for it.

Source: UIKit of the arm64 shared cache of iOS 11.0 (iPod7,1 15A372),
`-[UINavigationItem backButtonTitle]` at `0x18a043a9c`, `-setBackButtonTitle:`
at `0x18a043618` through `-_setBackButtonTitle:lineBreakMode:` at
`0x18a043628`, and `-currentBackButtonTitle` at `0x18a04e8e8`, which is where
the order below is decided; the value behaviour from the differential test
against the host's UIKit (`tests/backports/host/backbuttontitle`).

## What it is and what it is not

The setter copies the string into an ivar of its own and tells the bar that the
back button's content changed, so that it can draw again. It does **not**
touch `backBarButtonItem`, and `backBarButtonItem` does not touch it: an item
that was given only a title answers `nil` for the item, an item that was given
only an item answers `nil` for the title, and an item given both keeps both,
whichever came first.

The two meet in `-currentBackButtonTitle`, which is what the bar actually
draws: if `backBarButtonItem` is there, its `title` wins; otherwise the
`backButtonTitle`; otherwise the item's own `title`, shortened if it has to be.

## What the port does

iOS 6 draws the back button from `backBarButtonItem` and from the previous
item's title, and nothing else, so that is where the string has to go. The port
keeps the title of its own, as Apple does, and when it is set it also builds a
plain `UIBarButtonItem` of that title and puts it in `backBarButtonItem` - but
only where that would not take an item away from the application: if the item
there is one the application set, the port leaves it and only remembers the
title. That is the same order UIKit resolves in, and it comes out the same way
round on this release: an application's own item wins, a bare title is drawn,
and a title set to `nil` takes the port's own item away again.

## The one divergence

After setting a back button title, `backBarButtonItem` is no longer `nil` on
this release, while on iOS 11 it stays `nil` - the port has to put the string
where the release looks, and the release looks there. An application that reads
`backBarButtonItem` to decide whether it has configured a back button sees an
item it did not make. Everything the test measures about the title itself -
what is stored, what the two properties answer about each other, the copy on
the way in, the last write winning, clearing with `nil` - matches the system
exactly.
