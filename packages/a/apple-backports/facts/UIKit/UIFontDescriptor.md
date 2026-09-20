# UIFontDescriptor, iOS 7

Source: the host's own UIKit under Mac Catalyst, asked for the class's answers, and UIFoundation of iOS 6.0 armv7
(`+[UIFont fontWithDescriptor:size:]` is in the `UIFont_AttributedStringDrawing` category, and `-[UIFont CTFontDescriptor]`
beside it), and iOS 6.0 on the emulator, through `tests/backports/device/uikit2.m`.

## Why the class is not carried

On iOS 7 `UIFontDescriptor` is a wrapper of a CoreText font descriptor (the newest release's class is a private
subclass named after CoreText), and the attributes it holds are CoreText's, which is why its keys are strings such as
`NSFontNameAttribute`. iOS 6 has no such class, but it has a method of the name an application would call with one:
`+[UIFont fontWithDescriptor:size:]` is in the release and takes a `CTFontDescriptorRef`. Handed an object that is not
one, it crashes: an `NSObject` passed on the emulator ended the application. A class the port carried would be handed to
that method by every application that uses it, and the port does not replace the release's methods.

So `UIFontDescriptor` is absent, `+[UIFont fontWithDescriptor:size:]` is recorded as the release's own, and an
application that guards its use of the class - the SDK makes the class weak - goes the way it goes when the class is
missing. An application that names the fonts it wants, by `+fontWithName:size:`, never needs either.
