# The anchors of a view, iOS 9

Source: the host's own UIKit, asked anchor by anchor, and the differential run of
`tests/backports/host/layout/run.sh`, which builds every constraint both implementations can make from
every anchor and compares them - 4320 constraints and 1800 baseline arrangements, none of them different.

A view answers twelve anchors, and each one is a value that stands for the view and one attribute:

| anchor | class | attribute |
|---|---|---|
| `leadingAnchor`, `trailingAnchor`, `leftAnchor`, `rightAnchor`, `centerXAnchor` | `NSLayoutXAxisAnchor` | Leading, Trailing, Left, Right, CenterX |
| `topAnchor`, `bottomAnchor`, `centerYAnchor`, `firstBaselineAnchor`, `lastBaselineAnchor` | `NSLayoutYAxisAnchor` | Top, Bottom, CenterY, FirstBaseline, LastBaseline |
| `widthAnchor`, `heightAnchor` | `NSLayoutDimension` | Width, Height |

An anchor is made once and kept: the same view answers the same object every time, two views never share
one, and a constraint made from it names that view as its item and that attribute as its attribute. Its
description names the view it belongs to. Nothing else is stored in it - the anchor is the pair, and the
constraint it makes carries the relation, the multiplier, the constant and the priority.

`-viewForFirstBaselineLayout` and `-viewForLastBaselineLayout` answer the view itself. They are the hook a
container overrides so that a baseline constraint against it reaches the view that really draws the text -
`UIStackView` answers its first or last arranged subview - and the differential compares the answer for
every axis and alignment a stack can be arranged in.
