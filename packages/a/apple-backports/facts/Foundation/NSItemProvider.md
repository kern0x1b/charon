# NSItemProvider, iOS 8

Introduced in iOS 8: a provider of an item that has one or more representations, each named by a type identifier, so
that an extension, a drag or a pasteboard can ask for the one it understands. iOS 9 added a coercion error, and iOS 11
the representations of data and files, the loading of objects and the built-in types of `NSString` and `NSURL`.

Source: the host's own Foundation, asked for every answer below and held against the port by the `itemprovider` and
`itemproviderbuiltins` groups of `tests/backports/host/uikit2/run.sh`, which compile the port with its names changed and
put it beside the system's class. The class is not in the shared caches of iOS 6.0 and 7.0, and the conformance of types is
that of the UTI functions of MobileCoreServices, which iOS 6 has.

## What the port does as the system does

- The types of a provider are kept in the order they were registered, and a type registered again keeps its place.
  `hasItemConformingToTypeIdentifier:` is true when a registered type conforms to the type asked for, by the UTI
  conformance of the release: a provider of `public.plain-text` has `public.text` and `public.data`.
- `loadItemForTypeIdentifier:options:completionHandler:` answers the first registered type that conforms. A type
  nobody has, and an item that is `nil`, answer `NSItemProviderErrorDomain` -1000 at once, whatever error a load handler
  gave. The class the completion handler's argument is declared with is read from the handler and is the class the value
  is coerced to: the same class comes as it is; a string comes from a URL and from data of a text type, data comes from a
  file URL, an image from data or a file that decodes as one, an attributed string from a string; asking for a URL of
  anything else, or for an image of data that is no image, answers -1100 (unexpected class), and any other pair
  answers -1200 (no coercion). A handler that names no class gets the value as it is.
- A load handler registered with `registerItemForTypeIdentifier:loadHandler:` is called after the load call returns, on
  the main queue when the caller is on it, and is told the class asked for and the options, which are an empty
  dictionary when none were given for a class and `nil` when a handler names none. An item given to
  `initWithItem:typeIdentifier:` comes on a background queue. An item with no type raises
  `NSInvalidArgumentException`.
- `initWithContentsOfURL:` registers the type of the file (by its extension), `public.file-url` and `public.url`; the
  type of the file answers the contents of the file, as a string, data, an image or an attributed string, and is
  no URL; the two URL types answer the URL as data, and as a URL, a string or data.
- A copy is another provider with the same types. `previewImageHandler` and `loadPreviewImageWithOptions:completionHandler:`
  answer what the handler gives, or -1000 with none.
- `registerDataRepresentation...` and `registerFileRepresentation...` register the representations of iOS 11, which
  `loadDataRepresentation...`, `loadFileRepresentation...` (a copy in a folder of its own, gone when the handler returns)
  and `loadInPlaceFileRepresentation...` load, preferring a representation of the kind asked for; the types can be
  listed and asked for with the file options. `registerObject:visibility:`, `initWithObject:`, `canLoadObjectOfClass:`
  and `loadObjectOfClass:completionHandler:` go through `NSItemProviderWriting` and `NSItemProviderReading`, and
  `NSString` and `NSURL` write and read as the system's do.

## What it cannot do

A provider lives in the process that made it: nothing crosses to another process, since the release has no extensions,
no drag and drop and no shared pasteboard of items. The built-in types of `UIImage`, `UIColor` and `NSAttributedString`
of iOS 11 are not carried, so `initWithObject:` of them and `canLoadObjectOfClass:` for them are not answered as the
system's are, and `NSString` and `NSURL` are not declared to adopt the two protocols, though their methods are there.
The visibility of a representation is kept and no process of another team or group exists to be shut out. The host
answers a few coercions with defects the port does not copy: an attributed string from a string comes back as a
serialised blob, a web URL asked for as data is never answered, and the contents of a text file registered by a URL
come back empty; the port answers those with the coercion or the error the rules above give.
