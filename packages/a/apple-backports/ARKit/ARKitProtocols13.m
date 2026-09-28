// ARKitProtocols13.m - the metadata of the ARKit protocols the 13.0 headers introduced.
//
// A protocol that is only named in a header nothing references emits no metadata: `@protocol` is the
// one expression that forces the runtime's description of a protocol to exist, and with nothing
// evaluating it a class's conformance is a list of names the linker can drop. The measurement that
// showed it was a built dylib with zero occurrences of the string and no `OBJC_PROTOCOL_$_` symbol for
// a row the registry calls implemented.
//
// The reference lives in an object of the release the protocol arrived in, because an object carries
// the API of one release and this is 13.0's - ARTrackable, with ARSessionObserver and ARSessionDelegate
// beside it in the same headers. It is not API: the functions are not exported, the pointers are static,
// and nothing outside this library reads them. What it does is give the runtime something to keep.

#import <ARKit/ARKit.h>

/// Each of these is the one expression that makes the runtime's description of a protocol exist:
/// `@protocol(X)` evaluates the protocol object, and nothing else in a program has to. It is not a
/// compile-time constant, so it cannot initialise a static, and it is in a function body rather than at
/// file scope for that reason; `used` keeps the linker from dropping the function before it is
/// evaluated, which is the whole of what is wanted here - the metadata has to survive the link, not the
/// function to be called.
///
/// `ARAnchorCopying` is 11.0 and is not here - an object carries the API of one release, and this is
/// 13.0's. It is already emitted, by ARAnchor's class extension conforming to it.
__attribute__((used)) static Protocol *CharonEmitARTrackable(void) { return @protocol(ARTrackable); }
__attribute__((used)) static Protocol *CharonEmitARSessionObserver(void) { return @protocol(ARSessionObserver); }
__attribute__((used)) static Protocol *CharonEmitARSessionDelegate(void) { return @protocol(ARSessionDelegate); }
