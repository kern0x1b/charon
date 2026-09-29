# The uniform type identifiers CoreServices added from iOS 8.0 to 9.1

CoreServices of iOS 8 added 52 `kUTType…` names, iOS 9.0 one and iOS 9.1 one: 54 in all. They are
carried here with the texts CoreServices itself gives them, and the values are read out of a real
cache rather than typed:

    each value read out of the arm64e shared cache of iOS 18.0 through its own symbol, with
    tools/cfconst.py — the symbol's address in the image's symbol table, the pointer stored there,
    the __cfstring it points at, and the bytes that names

`kUTType3DContent` is `public.3d-content`, `kUTTypeAVIMovie` is `public.avi`,
`kUTTypeAppleProtectedMPEG4Video` is `com.apple.protected-mpeg-4-video`. The text matters and is not a
spelling of the symbol: a uniform type identifier is what a file's type is **compared by**, so a name
carried with the wrong text is a type no file would ever match.

**Checked against a second source**, the host's own CoreServices, which exports all 54:
`tests/backports/host/coreservicesnames` reads each value on both sides and compares.

    54 agreed, 0 differed, and the host has no such name for none of them

**One file per release**, because an object carries the API of one release: `CoreServicesNames80.m` (52
names), `…90.m` (1) and `…91.m` (1), each carried from the release the armv7 ladder measures it first
appearing in.

**The release's own answer to a type it does not know.** `kUTTypeLivePhoto` and `kUTTypeSwiftSource` are
carried so an application that names one loads; the release's declaration store has no type under
either, so a file of that type is still typed by what the release says, and no file is reclassified
because the port knows a name for it. That is the same line the Contacts labels take
(`facts/Contacts/Values.md`): the name is carried, the classification is the release's.

## The one row that is not a name

`UTTypeCopyAllTagsWithClass()` is a **function**, not a constant, and it is the one row of CoreServices
that is not carried here. What it takes is measured: the armv7 shared cache of iOS 6.1.3 exports
`UTTypeConformsTo`, `UTTypeCopyChildIdentifiers`, `UTTypeCopyDeclaration`,
`UTTypeCreatePreferredIdentifierForTag` and `UTTypeCopyDeclaringBundleURL` from its
**MobileCoreServices**, and **no `UTTypeCopyAllTagsWithClass`** — it arrived in iOS 8. So the function
would be written over the release's own declaration walk (the type and its children, each identifier
of which is asked `UTTypeConformsTo(identifier, tagClass)`), and it would be held to the host's own
`UTTypeCopyAllTagsWithClass` — which macOS has — over a list of types.

It is not written in this delivery because it is the one piece here whose *release* behaviour cannot be
measured without a device run, and the emulated 6.1.3 run that would measure it is queued behind every
other heavy job on the machine. The row is recorded in `registry/CoreServices/names.json`'s sibling as
what it is rather than left to look like an oversight.
