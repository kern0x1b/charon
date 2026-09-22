# JSContext, JSValue, JSVirtualMachine and JSManagedValue, the objects over iOS 6's own engine

Source: SDK 16.4's own JSContext.h/JSValue.h/JSVirtualMachine.h/JSManagedValue.h/JSExport.h for the
contract; `coordination/corpus/caches/6.0.tsv` for what iOS 6 itself exports; `tests/backports/host/jscontext`
for the sixteen checks this was measured against on the host (renamed at compile time, since the classes
share their names with the host's own JavaScriptCore.framework, which this file's checks are not a
differential against - there is no host JSContext to hold the backport to, only the header's contract).

## What iOS 6 already carries

`facts/JavaScriptCore/JavaScriptCoreExports.md` said thirteen C API names, from an iPad 2 asked one by one
with `dlsym` after every framework had loaded. That undercounts: `coordination/corpus/caches/6.0.tsv`, built
from the release's own export table rather than a running process's memory, names 89 `JS`-prefixed symbols in
the framework, including `JSEvaluateScript`, `JSObjectCallAsFunction`, `JSObjectSetProperty`,
`JSClassCreate` and the rest of what a real bridge needs - not just the thirteen the device probe happened to
ask for and find loaded. The dlsym probe is not wrong about what it found; it is silent about what it never
asked. `JavaScriptCoreExports.md` is corrected alongside this file.

## The shape of the bridge

Every one of the four classes is a wrapper over the C API the table above confirms: `JSVirtualMachine` a
`JSContextGroupRef`, `JSContext` a `JSGlobalContextRef`, `JSValue` a `JSValueRef` (protected with
`JSValueProtect` for its own lifetime, unprotected on dealloc), `JSManagedValue` a weak hold on a `JSValue`.
Conversion between an Objective-C object and a `JSValueRef` follows the table JSValue.h itself documents -
nil/NSNull/NSNumber/NSString/NSDictionary/NSArray/NSDate/NSBlock/id each get their own JavaScript shape,
recursively for the two collection types.

## JSExport

A class conforming to a protocol that incorporates JSExport gets one JavaScript wrapper object, built once
per Objective-C class (not per instance) by walking that protocol's own `@required` properties and instance
methods with the Objective-C runtime - `protocol_copyPropertyList` and
`protocol_copyMethodDescriptionList` - and caching the name-to-selector table. A property becomes a
JavaScript accessor; an instance method becomes a callable function, its JavaScript name the default
colon-stripping conversion the header describes unless `JSExportAs` names it something else. Calling either
marshals arguments and the return value through the object's own `-methodSignatureForSelector:` and an
`NSInvocation` - not a re-derivation of the protocol's own encoded types, so what is marshaled is what the
class actually implements, superclass methods included. Supported types: id and Objective-C instance
pointers, BOOL, the C integer types to 64 bits, float, double, and the four structs JSValue itself converts
(CGPoint, CGRect, CGSize, NSRange). A method outside that set is still exported; calling it from JavaScript
throws rather than reading an argument off the wrong-sized slot.

## Blocks as JavaScript functions

An NSBlock is exported as a callable JavaScript function only when its own Objective-C type encoding, read
with `_Block_signature` rather than assumed, shows every argument and the return value as object-pointer
shaped. Checked types, not just checked counts: a block that takes a `double` or returns a `struct` is still
wrapped, and throws in JavaScript when called, rather than reading a garbage value off an argument slot
sized for a pointer. The invoke happens through the block literal's own `invoke` field - `{isa, flags,
reserved, invoke, ...}` - not the block's own address, which is a struct pointer whose first bytes are `isa`,
not code; that distinction cost one segfault before `tests/backports/host/jscontext` caught it.

## What is simplified, named rather than hidden

- **`+currentContext`/`+currentThis`/`+currentCallee`/`+currentArguments`** answer from a pthread-local stack
  of frames, pushed before and popped after a callback JavaScript makes into an exported block or JSExport
  method - nested callbacks each get their own frame, popped in order.
- **`-[JSVirtualMachine addManagedReference:withOwner:]`** keeps a plain retaining map from owner to the
  objects registered under it, in place of the real engine's garbage collector scanning the same graph: a
  reference lasts exactly as long as the owner given to add it does, not for as long as some other path also
  reaches it. `JSManagedValue` itself holds its value weakly, so it reads back nil exactly when nothing else
  - ARC's own hold, or this map for a registered owner - keeps the value alive, which is the same outcome the
  real "conditionally retained" contract describes, reached by a different mechanism (measured in
  `tests/backports/host/jscontext`: a JSManagedValue's value reads back nil once the only other strong
  reference to it is dropped).
- **`valueWithNewPromiseFromExecutor:`/`valueWithNewPromiseResolvedWithResult:`/
  `valueWithNewPromiseRejectedWithReason:`/`valueWithNewSymbolFromDescription:`/`isSymbol`** are iOS 13,
  past the iOS 7-10 band JSContext itself is scoped to. The header declares them unconditionally, so they are
  implemented as safe no-ops - a promise that never settles, a plain string standing in for a symbol - rather
  than left to raise "unrecognized selector" the first time code built against a later SDK reaches them.
- **`-name`** is kept locally rather than shown anywhere, since the release exports no
  `JSGlobalContextSetName` to show it to; **`-isInspectable`** is stored and has no other effect, since there
  is no Web Inspector on this release to show it to either.
- **A plain Objective-C object that does not derive from one of the bridged types and does not conform to a
  JSExport protocol** becomes an opaque JavaScript wrapper with no properties or methods - it round-trips
  back through `-toObject`, but nothing more.
- **`-isArray`** asks the context's own `Array.isArray` rather than the C API's `JSValueIsArray`, which iOS 6
  does not export (introduced iOS 9); `-isDate` asks `-isInstanceOf:` against the context's own `Date`.
