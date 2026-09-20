# UIListContentConfiguration and its text and image properties, iOS 14.0

A value that says what a row shows: text, secondary text (plain or attributed), an image, and how each is set. Twelve style factories (cell, subtitle, value, three sidebars, headers and footers of plain and grouped lists, accompanied sidebars) and a bare `init`.

## What the port does as UIKit does
- Every default of every factory (fonts, colours, paddings, margins, side by side), measured.
- `updatedConfigurationForState:` follows the host: sidebar styles take the medium font, a focused row white text, a highlighted row 30% transformers, a faded one alpha 0.5, a disabled one tertiary and quaternary colours. What the application set - a font, a colour, a transformer, a tint - is kept when the state changes; alpha is multiplicative.
- Equality, copy, coding by the port's own keys and the description as the host prints it. Blocks are not archived.
- `UIListContentImageStandardDimension` is -CGFLOAT_MAX, as the header has it.

## Differences
- Font sizes and colours are read from the host's values, not from Dynamic Type; `adjustsFontForContentSizeCategory` is kept and does nothing on this release.
- `showsExpansionTextWhenTruncated` is iOS 15 and `@dynamic`.

## What the host measures that a phone would not

The host is Catalyst, so its metrics are those of the Mac idiom: row margins {15,16,15,8}, a plain row estimate of 40.04 (44 x 0.91), a sidebar inset of 12.987 (10 / 0.77), a corner radius of 26 for grouped and sidebar lists, some Mac colours. The port follows the host's raw values, except the row estimate of a list layout, which is 44, the phone's. Nothing here was measured on an iPhone; `Dynamic Light Alpha` was 0.12 in light and 0.4 in dark, and the port carries 0.12, since this release has no dark mode.

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), measured with random values and states side by side with the port in one process, and the header of SDK 16.4. The differential tests are `tests/backports/host/uikit2` (the `listvalues` group for values, the windowed `listcell` group for views); the device application is `tests/backports/device/lists.m`, held to the numbers the host recorded in `lists-expectations.h`.

## On iOS 6

The medium weight the sidebar takes for a selected row is the release's system font: the weight backport of `UIFont` maps every weight up to medium to the regular font, so a selected sidebar row is not different in its font, only in its colours and transformers when focused or highlighted.
