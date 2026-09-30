// UIKit26_4.m - the 26.4 band, and the row that could not be written.
//
// ONE OBJECT, ONE RELEASE: 26.4, on its own.  A reader is the only thing that would notice this in
// UIKit26_0.m, because release-split reads band points only.
//
// UITextInput.unobscuredContentRect IS OWED, AND THIS FILE IS EMPTY BECAUSE OF IT.  It is a protocol
// property, so the accessor would have to be a category on NSObject, and the first version of this file
// built exactly that - which put the object and the row in direct opposition: the row said "the accessor
// is not declared, so respondsToSelector: answers NO and an unchecked call raises" while the object
// declared it.  The gate reads the OBJECT, and it was right to.
//
// The accessors are gone and the row stays owed, which is the coherent choice: the SDK 26.2 surface does
// not declare this name and a 26.4 name cannot appear in a 26.2 surface by construction, so nothing
// compiled against this surface can spell it, and an accessor for a name no caller can name is API that
// exists only to satisfy a queue.  coordination/api-queue.md names the row; what closes it is a newer
// surface that declares it.
