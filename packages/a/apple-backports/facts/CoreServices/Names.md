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
that is not carried here. The armv7 shared cache of iOS 6.1.3 exports `UTTypeConformsTo`,
`UTTypeCopyChildIdentifiers`, `UTTypeCopyDeclaration`, `UTTypeCreatePreferredIdentifierForTag` and
`UTTypeCopyDeclaringBundleURL` from its **MobileCoreServices**, and **no `UTTypeCopyAllTagsWithClass`**:
it arrived in iOS 8, and the SDK marks it deprecated for ios 8.0 to 15.0.

What it answers is measured on the host by `tests/backports/host/uttypetags/probe.m`, one `TAGS` line per
identifier and class (the host is macOS; the run is the oracle, not the release):

- A declared type answers the declaration's `UTTypeTagSpecification[class]`, a string as a one-element
  array and an array as it is. `public.jpeg` gives `public.filename-extension = [jpeg, jpg, jpe]` and
  `com.apple.ostype = [JPEG]`; `public.folder` gives `com.apple.ostype = [fold, fldr, adcL, sbFd]`.
- Tags are not inherited. `public.zip-archive` conforms to `public.data` (`UTTypeConformsTo` answers 1),
  `public.data` declares `com.apple.ostype = [sbFl]`, and `public.zip-archive` answers
  `com.apple.ostype = NULL`. So the function reads the type's own declaration and does not walk its parents.
- A class the declaration does not name answers NULL: `public.item` answers `com.apple.ostype = NULL`.
- An undeclared identifier answers NULL for every class: `com.example.nonexistent`.
- A dynamic identifier has no declaration, and the host still answers: `dyn.ah62d4rv4ge80c6dp` gives
  `public.filename-extension = [apk]`. The answer is computed from the identifier, not stored.

It is owed, not written, because of the dynamic case. The port has no decoder from a `dyn.` identifier
to its filename extension: `UTTypeDynamic8.m` classifies a dynamic identifier and nothing more, and the
`zzqq` to `dyn.age81y8xvse` pair in `facts/MobileCoreServices/UTTypeDynamic.md` is the forward direction
only. A declared-only function would answer NULL where the host answers `[apk]`, which is a crutch, so
it is not written that way. What it needs: the release's dynamic identifier encoding measured in the
direction that gives the extension back; the release's answer for a dynamic identifier measured on the
6.1.3 emulator; and the declared-type rule above checked there as well, with the host output as oracle.
