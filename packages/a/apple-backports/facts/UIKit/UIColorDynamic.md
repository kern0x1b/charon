# Dynamic colours and the system colours of iOS 13

Introduced in iOS 13: `+colorWithDynamicProvider:`, `-resolvedColorWithTraitCollection:` and the semantic colours - the labels, the
separators, the backgrounds, the fills, the grays 2 to 6 and the two new tints.

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), for how a dynamic colour behaves and for the palette where the host
shares it with iOS, held against the backport by the `colors13` group of `tests/backports/host/uikit2`; the values that are the
iPhone's own are from Apple's published table of the iOS 13 system colours (Human Interface Guidelines, Color), which is public
documentation and not code.

## The palette

**The host is not a source for most of the palette.** Under Mac Catalyst the semantic colours are the Mac's own: the label colour is
black at 0.847, the secondary background is 236 gray, the dark background is 30, the blue is (0, 136, 255). The values that are the
same on the two are held to the host, and the host and the port agree on them for every trait combination:

- `linkColor` (0, 122, 255) and, dark, (9, 132, 255);
- the four fill colours, in light and dark and with high contrast - `systemFillColor` (120, 120, 128) at alpha 0.20, 0.36, and 0.28,
  0.44 with contrast; the secondary 0.16, 0.32, 0.24, 0.40; the tertiary (118, 118, 128) at 0.12, 0.24, 0.20, 0.32; the
  quaternary (116, 116, 128) at 0.08, and (118, 118, 128) at 0.18, 0.16 and 0.26 in the others;
- `systemGray2Color` to `systemGray6Color` in light, dark and both with high contrast (the host's dark base equals the iOS 13 table).

The rest is the iOS 13 table: the labels black and white with the secondary, tertiary and quaternary as (60, 60, 67) at 0.6, 0.3
and 0.18 in light and (235, 235, 245) at 0.6, 0.3 and 0.16 in dark; the placeholder as the tertiary; the separator (60, 60, 67) at
0.29 and (84, 84, 88) at 0.6; the opaque separator (198, 198, 200) and (56, 56, 58); the backgrounds white, (242, 242, 247), white
in light and black, (28, 28, 30), (44, 44, 46) in dark, with the elevated dark ones (28, 28, 30), (44, 44, 46), (58, 58, 60), and the
grouped ones the other way round; the brown (162, 132, 94) and (172, 142, 104) and the indigo (88, 86, 214) and (94, 92, 230). The
high contrast values of these are the normal ones: the table has no other values for them that the port could check.

## Dynamic colours

A dynamic colour is made with a provider, asked for the traits it is to answer for. The host does not ask at creation; the port must,
since it draws the colour by its light value, so it asks once with the current collection and then again for each
`-resolvedColorWithTraitCollection:` - a colour the provider returns that is dynamic is resolved again, and one that is not is the
answer. A colour that is not dynamic resolves to itself, as the host's do. Two colours made from one provider are two colours, and a
colour of the same components made with `colorWithRed:...` is not dynamic.

**What differs.** A dynamic colour is a colour of the release with the provider kept beside it, so everything that reads it - a view's
background, a label's text, `CGColor`, `getRed:...` - reads its value for the collection current when it was made, the light one, and
does not follow a collection that is made current later. `-colorWithAlphaComponent:` of a dynamic colour is a colour of the light
value with that alpha and is not dynamic, where the host keeps it dynamic. Equality is the release's, by components.

The named colours are made once, each a dynamic colour of its table, so the same object answers every call.
