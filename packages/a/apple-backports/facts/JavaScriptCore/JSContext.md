# JSContext, JSValue, JSVirtualMachine and JSManagedValue, the objects over iOS 6's own engine

Source: SDK 16.4's own JSContext.h/JSValue.h/JSVirtualMachine.h/JSManagedValue.h/JSExport.h for the
contract; `coordination/corpus/caches/6.0.tsv` for what iOS 6 itself exports; `tests/backports/host/jscontext`
for behaviour. That test is a differential: the same `checks.m` runs first against the host's own
JavaScriptCore.framework, which ships these four classes and is the oracle every expectation has to pass,
then against the backport, renamed at compile time and linked over the host's C API. Both answer 105 of
105.

**Device-unverified.** The host runs a modern engine; the release's is the 2012 one. Until `checks.m` has
run on an iOS 6 device (iPad 2) as a device binary, everything below that depends on the engine - above all
the Promise script, the weak object map and private properties - is measured on the host only.

## What iOS 6 already carries

`facts/JavaScriptCore/JavaScriptCoreExports.md` said thirteen C API names, from an iPad 2 asked one by one
with `dlsym` after every framework had loaded. That undercounts: `coordination/corpus/caches/6.0.tsv`, built
from the release's own export table rather than a running process's memory, names 93 `JS`-prefixed symbols in
the framework (`awk -F'\t' '$2=="JavaScriptCore" && $1~/^_JS/' 6.0.tsv | sort -u | wc -l`), including
`JSEvaluateScript`, `JSObjectCallAsFunction`, `JSObjectSetProperty`, `JSClassCreate` and the rest of what a
real bridge needs - not just the thirteen the device probe happened to ask for and find loaded. The dlsym
probe is not wrong about what it found; it is silent about what it never asked.

## Private C API this uses, and why

Every call below is exported by the release but declared in no public header - WebKit's own private
headers, which the release's own Objective-C bridge (iOS 7 and later) is built on. The public C API has no
equivalent, so there is no public mechanism to prefer:

| Call | Declared in | Why nothing public does it | Exported by (6.0.tsv ladder) |
| --- | --- | --- | --- |
| `JSWeakObjectMapCreate/Set/Get/Remove` | `JSWeakObjectMapRefPrivate.h` | the only reference to a JavaScript object the collector clears; `JSValueProtect` only keeps. JSManagedValue, the one-wrapper-per-object cache and the per-global Promise constructor need a reference that does not keep | 6.0, 7.0.1, 10.3.4, 12.0, 16.0, 18.0 |
| `JSObjectGet/Set/DeletePrivateProperty` | `JSObjectRefPrivate.h` | a property script cannot see, enumerate or change: a promise's state, a managed-reference node | same six |
| `_protocol_getMethodTypeEncoding` (libobjc) | objc-runtime's private header | a JSExport method's extended type encoding - the class of each argument; `protocol_getMethodDescription` answers `@` for every class | same six |

Measured with `grep "^<symbol>\t" coordination/corpus/caches/<release>.tsv` over 6.0, 7.0.1, 10.3.4, 12.0,
16.0 and 18.0: every one is exported by all six. The host's own JavaScriptCore imports `__protocol_getMethodTypeEncoding` (and
`__Block_signature`), `dyld_info -imports /System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore`:
the release's bridge reads method encodings the same way. A block's signature is not on this list: it is read as the
documented clang Block ABI lays it out (below), not through `_Block_signature`.

## The shape of the bridge

Every one of the four classes is a wrapper over the C API the table above confirms: `JSVirtualMachine` a
`JSContextGroupRef`, `JSContext` a `JSGlobalContextRef`, `JSValue` a `JSValueRef` (protected with
`JSValueProtect` for its own lifetime, unprotected on dealloc), `JSManagedValue` a GC-weak hold on the
JavaScript value itself (JSManagedValue.m and JSVirtualMachine.m describe the graph). An Objective-C object
boxed more than once in a context gets the one wrapper, as the release keeps one.

## Conversions

Measured against the host's JavaScriptCore case by case and written as its JSContainerConvertor walks it
(JSInternal.m, `Convert`):

- `-toObject`: undefined is nil and null NSNull at the top; a wrapped Objective-C object is itself; a `Date`
  is an NSDate (an invalid one an NSDate of NaN); an array is read by its `length`, anything else - a
  function, an Error, a RegExp, a boxed number included - as a dictionary of its enumerable property
  names, inherited ones included. Inside a container null is NSNull; undefined and a hole are NSNull in an
  array and left out of a dictionary. Every object is converted once: a cycle or a shared reference gives
  back the same Objective-C object, and the walk uses a worklist, not recursion. A getter that throws is
  left out and reported nowhere, as the host reports it nowhere.
- `-toArray`/`-toDictionary`: any object is read as the container asked for (`{a:1}` is an empty array,
  `[5,6]` is `{0:5, 1:6}`), undefined and null are nil, any other primitive is nil and a TypeError
  "Cannot convert primitive to NSArray/NSDictionary" to the context's exceptionHandler.
- `-toString`/`-toDouble`/`-toInt32`/`-toNumber`/`-toDate` that run a throwing `toString`/`valueOf` answer
  nil/NaN/0/NaN/nil and send the exception to the exceptionHandler.

## Arguments by their declared class

A block's or JSExport method's object argument is converted by the class its extended type encoding names
(`@"NSString"`), as the release does - measured on the host for thirteen declared types against thirteen
kinds of value: `JSValue *` receives the value itself (a missing argument is undefined); `id` receives
`-toObject`; `NSString`, `NSNumber`, `NSDate`, `NSArray` and `NSDictionary` receive the matching `-to...`
conversion; any other class receives the bridge's own wrapper of an instance of it, nil for undefined and
null, and for anything else a TypeError "Argument does not match Objective-C Class" is thrown into the
calling script before the block or method runs. A conversion that fails is thrown the same way.
`+currentArguments` holds every JavaScript argument, not only the declared ones.

A block's encoding is read as the documented clang Block ABI (clang's `docs/Block-ABI-Apple.rst`) lays it
out: `flags & BLOCK_HAS_SIGNATURE (1 << 30)`, then the descriptor's signature field, past `copy`/`dispose`
when `BLOCK_HAS_COPY_DISPOSE (1 << 25)` is set. The compiler that built the block writes it, not the
runtime. Measured on the host: the pointer read this way is the very pointer `_Block_signature` answers, for
a global, a capturing and a primitive-typed block. A method's comes from `_protocol_getMethodTypeEncoding`
(table above); a property setter's from the property's own `property_getAttributes`.

A block taking a block, a `Class`, a `SEL`, a pointer, a struct other than CGPoint, CGSize, CGRect and
NSRange, or a class the runtime does not know is no function to JavaScript (`typeof` answers "object"), as
on the host (measured for a block, `Class`, a one-int struct; NSRange and seven `id` arguments are
functions). The invoke goes through the block literal's own
`invoke` field, not the block's own address, which is a struct pointer whose first bytes are `isa`.

## What differs from the release, named

- **A block taking or returning a C number or one of those four structs, or taking more than six arguments,** is a function the
  release would call; this bridge calls blocks through their `invoke` pointer with object-sized arguments
  only, so calling one throws a TypeError in JavaScript instead of reading a value off the wrong-sized slot.
  JSExport methods have no such limit: they go through `NSInvocation`, which marshals every C type.
- **The JavaScript class name of a wrapper** is the bridge's own (`[object CharonOpaqueObject]`,
  `[object CharonExportObject]`) where the host shows the Objective-C class (`[object NSURL]`), so
  `String(wrapper)` differs.
- **Promises** are the release engine's own ES5 script (JSValue.m, `CharonPromiseSource`) over native
  helpers; a context made by `-init` gets a global `Promise` (the iOS 6 global has none), a context adopted
  from a web view page does not. Reactions run when the outermost Objective-C call into JavaScript returns;
  jobs queued with no such call on the stack (script run through the C API directly, a page) run on the
  thread's next run-loop turn. JSValue's property accessors do not drain the queue.
  `valueWithNewPromiseResolvedWithResult:nil` resolves with undefined, where the host raises
  NSInvalidArgumentException: an API must never crash its caller (COORDINATION.md section 2).
- **Symbols**: the 2012 engine has none. `valueWithNewSymbolFromDescription:` notes a TypeError on the
  context and answers undefined, and `isSymbol` answers NO - an honest refusal at the seam.
- **`-name`** is kept locally rather than shown anywhere, since the release exports no
  `JSGlobalContextSetName`; **`-isInspectable`** is stored and has no other effect. Whether iOS 6's
  webinspectord could list a bare JSGlobalContext at all is not measured.
- **`-isArray`** asks the context's own `Array.isArray` rather than `JSValueIsArray`, which iOS 6 does not
  export (introduced iOS 9); `-isDate` asks `-isInstanceOf:` against the context's own `Date`.

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
