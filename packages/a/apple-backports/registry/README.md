# The registry of what the backports do and do not carry

An application that calls API the device lacks stops there, so every API a
release added is decided on before it is missed. The entries live under
`registry/<Framework>/`, a file per author - `base.json` beside `ios10.json`,
`ios11.json`, `floor.json` - so that work on different releases never edits the
same file; a plain `<Framework>.json` beside them is read as well. A file holds
an array of entries, or an object with `framework` and `entries`, and one API
named by two files stops the build with both names.

    {
      "framework": "UIKit",
      "entries": [
        {
          "api": "-[UIView tintColorDidChange]",
          "kind": "method",
          "introduced": "7.0",
          "status": "implemented",
          "facts": "facts/UIKit/UIView+TintColor.md",
          "source": "UIKit 18.0 arm64e"
        },
        {
          "api": "UIDragInteraction",
          "kind": "class",
          "introduced": "11.0",
          "status": "absent",
          "reason": "dragging is carried by a system service the release does not run",
          "effect": "the class is not there: NSClassFromString answers nil and alloc on a compile time reference crashes"
        }
      ]
    }

`api` names what an application writes: a class as `UIStackView`, an instance
method as `-[UIView tintColorDidChange]`, a class method as
`+[UITraitCollection traitCollectionWithDisplayScale:]`, a property, both
accessors at once, as `UIScreen.captured`, a function as
`UIGraphicsBeginImageContextWithOptions()`, and a constant by its symbol,
`UIFontTextStyleBody`. A class whose whole surface shares one status is one
entry; a method of an implemented class that is not implemented gets its own.

`introduced` is the release the SDK's availability gives, and for a private
entry point a backport calls, the release of the API that needed it. `removed` names the
release that took the API away, so that what modern iOS no longer has is not
backported as though it were current. `minimum` is the release below which the
entry becomes `absent`, which is how a release older than the one a backport
needs is written down once instead of once per release. `maximum` is its mirror,
the release from which the entry becomes `absent` although the release itself
does not have the API either: a member of a class the backports implement
themselves, whose behaviour lives inside that implementation, is gone once the
release carries the class and lays it out itself. `facts` points at the
file the behaviour was read into. It is required of an entry that claims
behaviour - one whose API the package itself carries - and of every `ignored`
entry; a record that only says where an API begins or ends, for a symbol this
release has nothing of, needs `reason` and `source` instead. `source`
names the library, release and architecture the behaviour was read from.

`status` is one of four, and there is no fifth:

- `implemented` — the real behaviour, with facts behind it and tests in
  `tests/backports`.
- `inert` — declared, does nothing, and says so once in the log the first time
  it is used. It is allowed only where doing nothing is a safe reading of the
  API: a visual effect the release cannot draw, haptics it has no hardware for,
  a hint to a scheduler it does not run. The reason belongs in the entry and in
  the README section that lists them.
- `absent` — not there at all, so `respondsToSelector:` answers honestly. This
  is the default, and it is required wherever quiet inaction would corrupt data
  or mislead: security, encryption, saving, payment, permissions, the network.
- `ignored` — the call reaches the release's own implementation, which does
  something else with it, and nothing of ours is in the way: an option of an
  enumeration the compiler writes into a system call, a key of a dictionary a
  newer release reads and this one does not. There is nothing for
  `respondsToSelector:` to answer, since the method is the system's own, and
  nowhere to write a line, since the call never passes through the backports, so
  `effect` and `facts` are required and say what comes out instead. This is the
  quietest of the four and the one a port is least likely to notice, so a report
  says it first.

A value the header itself carries - a `static const`, a macro, a case of an
enumeration - gets no entry, because the package carries nothing of it: the
compiler writes the value into the application, and neither side of the check can
see it. `UIStackViewSpacingUseSystem` is one of those. Where such a value changes
what an API does, the entry of the API that reads it says so, and its file of
facts says what the value means.

The build checks the registry against what the package really defines: the
classes its libraries carry and the selectors its categories add. A class or
selector without an entry, an `implemented` entry that names nothing the build
carries and nothing the release itself exports, and an entry whose status comes
without the reason, effect or facts it owes stop the build; a band built for a
later release drops what that release already has, so only the libraries of the
port's own release are checked both ways. Entries that are not `implemented`
cannot be derived from anything, so they are written by hand, and a delivery
without them is not accepted.
