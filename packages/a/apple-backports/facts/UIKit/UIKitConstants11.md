# Two loose constants of iOS 11.0

Not every name a release adds belongs to a class the port can carry. These two
are strings an application writes into a dictionary or an array, where a name
that is missing is worse than a name that is there and unused: a weak import
that stays `NULL` becomes a `nil` key, and a dictionary raises on one.

Source: UIKit of the arm64 shared cache of iOS 11.0 (iPod7,1 15A372), the
exported constants at `0x1aa619318` and `0x1aa645bf0`, read for their values.

| constant | value |
|---|---|
| `UIImagePickerControllerImageURL` | `UIImagePickerControllerImageURL` |
| `UIActivityTypeMarkupAsPDF` | `com.apple.UIKit.activity.MarkupAsPDF` |

The second one is why both were read rather than assumed: its value is not its
own name but a reverse-domain identifier, and a port that guessed would have
excluded nothing.

## What they do here

`UIImagePickerControllerImageURL` is a key of the dictionary an image picker
hands its delegate. This release's picker never puts it there, so an
application that looks for it is answered `nil` and falls back to
`UIImagePickerControllerReferenceURL`, which this release does fill in. The key
itself must exist for that lookup to be written at all.

`UIActivityTypeMarkupAsPDF` names an activity of the share sheet. This release
has `UIActivityViewController` and never offers that activity, so excluding it
excludes nothing; what the constant buys is that an application can name it in
`excludedActivityTypes` without building an array around a `nil`.

Neither constant makes anything happen, and neither pretends to: the behaviour
they belong to is the release's own, and it is unchanged.
