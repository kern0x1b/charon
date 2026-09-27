# IntentsUI on a release with no Siri, no Shortcuts and no extension host

`libIntentsUIBackports.dylib` carries the three classes of the IntentsUI surface an application
reaches: the button that shows what a shortcut would do, and the two view controllers that take a
person through adding or editing one. Every registry entry of this framework points here.

## The wall, and what is on this side of it

What these three classes are for is **the system's own flow**: Siri's screens, taken through
adding a shortcut to a phrase, and written into the system's shortcut database. This release has

* no Siri,
* no Shortcuts database — the framework is iOS 12 and the database arrived with it,
* no extension host — `NSExtensionContext`, which the header's `NSExtensionContext` category is
  declared on, arrived with iOS 8 and is not here at all,
* and `INVoiceShortcut` **declares no initialiser at all** — only `init NS_UNAVAILABLE` and
  `+new NS_UNAVAILABLE` — because a voice shortcut is the system's own object. That is Apple's
  own header, and it is the measurement that decides what the two controllers can honestly do.

So the classes are real, the views are real, the state is real — and the flow ends where the
system's begins:

* `INUIAddVoiceShortcutViewController`'s **Add** calls
  `addVoiceShortcutViewController:didFinishWithVoiceShortcut:error:` with a **nil shortcut and an
  error**, which is the answer its own documentation names ("with either the successfully-added
  voice shortcut, or an error"). Inventing a voice shortcut would be a value that looks like the
  system's and is not.
* `INUIEditVoiceShortcutViewController`'s **Save** calls
  `editVoiceShortcutViewController:didUpdateVoiceShortcut:error:` the same way: the phrase of a
  voice shortcut is `readonly` in the SDK's own header and there is no database behind it here.
* Its **Delete** calls `editVoiceShortcutViewController:didDeleteVoiceShortcutWithIdentifier:`
  with the voice shortcut's own `identifier`, which is a `NSUUID` — the class can only be reached
  by an application that already holds one, and on this release nothing can make one.

The button's **press** asks its delegate for the *add* controller, which is the only of the two it
can build: making an edit controller needs a voice shortcut, and there is none. Both delegate
methods are the SDK's own declaration and are answered by the application's class, which is the
same treatment the 77 Intents protocols get.

## What the button answers

`INUIAddVoiceShortcutButton` is a `UIButton` that draws itself, because the six styles the header
names are a background, a border and a title colour:

* the two light styles take dark ink, the two dark ones take light, and the two outlines take a
  one-point border;
* **Automatic** and **AutomaticOutline** (iOS 13) follow the interface style, and the interface
  style is the one UIKit's own trait collection reports, so the style is applied again when that
  changes;
* `cornerRadius` is capped at half the button's height — the header's own rule, and the cap is
  applied again in `layoutSubviews`, where the height is known.

The button is titled with what the shortcut would say: the intent's
`suggestedInvocationPhrase`, or the user activity's title.

## The two view controllers

Both are laid out by hand in `viewDidLayoutSubviews` — a label, a field or a button, and two
buttons — because the screens are those few pieces and this release's UIKit has no auto layout
chain worth relying on for a view nobody loaded a nib for. The two buttons are the header's own
answers, and they call the three delegate methods the header declares.

## The hosted view, and why it is implementable here

`INUIHostedViewControlling` looked like it needed a system host, and it does not: **the `context`
argument is an enumeration** (`INUIHostedViewContextSiriSnippet`, `INUIHostedViewContextMapsCard`),
not an `NSExtensionContext`, and the parameters come out of the interaction — which the port
carries, donation and all. So both of the protocol's methods are implemented in full by
`CharonIntentsUIHostedViewController` (`CharonIntentsUIHostedView.m`):

* the interaction's parameters — its intent's own properties, by the key path an `INParameter`
  names, which is exactly what `-[INInteraction parameterValueForParameter:]` reads — become the
  view's content, one label each, and a parameter the interaction carries nothing for is **left
  out of the configured set** rather than shown empty;
* the interactive behaviour becomes the button the header describes for that case, and the four
  cases are four different things: `None` shows nothing at all (it is the header's own first
  case), `NextView` a navigation chevron, `Launch` a button to leave the context, and
  `GenericAction` a large tap target in a bigger font;
* the completions are answered with the size the content needs, and with the set of parameters
  that were really configured.

The class is named as **Charon's own**, because the SDK declares the *protocol* and the class that
conforms to it is the application's: this is the port's, so an application has a conforming class
to build on, and the name keeps it clear of any class Apple may add. A name no SDK header
declares changes swift-runtime's lift sets — this is the one such name in this delivery.

## What is not carried, and why each

Fifteen rows are `absent`, each with its reason in the registry, and none of them is answered
with a value that looks like something and is not:

* the four `INImage` members of IntentsUI's category (`+imageWithUIImage:`, `+imageWithCGImage:`,
  `+imageSizeForIntentResponse:`, `-fetchUIImageWithCompletion:`) need `UIImage`'s own PNG encoder
  and the response's image; the class the category names is the one the port carries, so the
  selectors are absent rather than answering with a value that looks like an image;
* the three `NSExtensionContext` members — there is no `NSExtensionContext` here at all;
* the eight `-init`, `-initWithFrame:` and `-initWithNibName:bundle:` the header marks
  `NS_UNAVAILABLE`, which a port cannot call.

The four enumerations and twelve constants of the surface get **no entries at all**: a case of an
enumeration and the type it belongs to are the header's own, and `registry/README.md` says so —
the compiler writes them into the application and the package carries nothing of them.

## What is not measured here

Nothing on this framework has been run: not on the device, not in the emulator, and not through
the generated call test, which has been run over the Intents registry only. Every entry here is
**device-unverified**, and the IntentsUI gate is still to come.
