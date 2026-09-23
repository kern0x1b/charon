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

## Two build-system defects this port's own files exposed, both in `modules/apple/backports.lua`

**Charon's own internal helpers must not share an object file with a class the band reexports -
fixed.** `charon_js_box`, `charon_js_unbox`, `charon_ns_string`, `charon_js_push_callback` and
`charon_js_pop_callback` used to live in `JSValue.m` and `JSContext.m`, next to the `JSValue`/
`JSContext` classes themselves. `band()` correctly reexports those two classes from the system on
any release from iOS 7.0 (where JavaScriptCore is genuinely there) - and drops their whole object
file doing it, taking the five helpers with it, even though `JSExportBridge.m` (whose own class,
`CharonExportBinding`, is never a real SDK name and so is always kept) calls them
unconditionally on every band. That produced "Undefined symbols: _charon_js_box" at `write_deb`'s
multi-band link only, never at a single-release `build()`, which never reexports anything -
confirmed by instrumenting `link()` directly (not committed): kept every JavaScriptCore object on
the 6.1.3 band, kept only `JSExportBridge.o` on the 7.0 band. Fixed by moving all five, plus the
block/opaque-object `JSClassRef` machinery and the pthread callback frame stack they depend on,
into `JSInternal.m`, which defines nothing but Charon's own names - `band()` always keeps it
regardless of what else in the library gets reexported.

**`-framework X` embeds the SDK's own install path for X, not the band's - fixed, generalized
past JavaScriptCore.** Fixing the helpers above surfaced a second, independent defect: on the
7.0 band, `libJavaScriptCoreBackports.dylib` loaded
`/System/Library/PrivateFrameworks/JavaScriptCore.framework/JavaScriptCore`, which iOS 7.0 does
not carry. Measured directly against both caches (`dyld.load` on `6.1.3` and `7.0`):
`JavaScriptCore` moved from `PrivateFrameworks` to `Frameworks` exactly at iOS 7.0. The 6.1.3
band linked clean only because the SDK's own path happens to still match iOS 6's. Checked all 21
frameworks this package's `LIBRARIES` table names against both ends of the covered range
(`6.1.3` and `10.3.4`) - `JavaScriptCore` is the only one whose path differs; the other 20 are
stable across the whole range, so this was not a second live case, only a first confirmed one.
Fixed generally, not as a JavaScriptCore special case: `framework_install_path()` reads, for
every framework a library links, where that band's own cache actually carries it (the same fact
`stubs()` already reads from the cache for symbols a band reexports, applied to the framework
itself), and `link()` rewrites the one load command afterward with `install_name_tool -change`
where it differs from what the SDK embedded. The ordinary, full-declaration `-framework X` link
stays exactly as it was - tried building a `.tbd` scoped to only this band's own exports instead
(the same technique `stubs()` uses for reexported symbols) and reverted it: it silently dropped
the declarations `UTType.m`'s weak, `API_AVAILABLE`-guarded calls to `_UTTypeIsDeclared`/
`_UTTypeIsDynamic` need to bind as weak imports rather than hard-undefined, since a band-scoped
stub carries no symbol arriving in a later release the same way the band's real firmware does
not - the rewrite-after-linking approach needs no such declaration, since the ordinary
`-framework` link already provides every one the SDK knows about.

**A third defect, found trying to make the first one fail loudly instead of as a bare linker
error, is real and still open.** The idea: after `band()` picks `kept`, check that every
`charon_`/`Charon`-prefixed symbol a kept object references undefined is actually defined
somewhere in `kept`, and name the object and the (likely reexported-away) object that should have
carried it, instead of leaving the discovery to whatever `Undefined symbols` the linker happens to
print. Implemented and reverted (not committed) after it fired a false positive on a single-release
`build()`: `CharonMetalEncoder.o needs _CharonMetalBindEpoch`, naming no provider, for a symbol
that links and runs fine today. The classification of "undefined, external" symbols from the
Mach-O `nlist` table (`kind & 0x0E == 0x00 and kind & 0x01 ~= 0`) does not distinguish a true
`N_UNDF` external reference from a **common symbol** (`N_UNDF` with a nonzero value field, a
tentative definition the linker resolves without another object defining it) or a **weak
definition**, and `_CharonMetalBindEpoch` is one of those, not a true undefined reference. A
version of this check worth trying again needs to read the `nlist` value field (zero for a true
undefined reference, nonzero for a common symbol) and the `N_WEAK_DEF`/`N_WEAK_REF` bits
(`n_desc`, not `n_type`) before deciding a symbol is genuinely missing - left open rather than
shipped half-right, since a check that gives a false positive teaches the next person to ignore
it, and then it misses the real one too.
