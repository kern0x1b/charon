# The twenty-six C API rows the corpus listed as absent, decided against the engine this port actually has

The corpus listed twenty-six rows of JavaScriptCore's C API as absent, every one of them with the same
reason: *the function arrived in iOS N, and nothing in iOS 6 has what it names*. That reason is a
statement about the release's export table, and for these twenty-six it is true and useless at the same
time. The port does not have to answer from the export table. It answers from the engine the release
already carries, and that engine is a whole JavaScriptCore: 885 symbols attributed to the framework in
`coordination/corpus/caches/6.0.tsv`, the ES5 C API end to end - `JSGlobalContextCreate`,
`JSEvaluateScript`, `JSValueToStringCopy`, `JSObjectGetProperty`, `JSClassCreate`, `JSValueIsObjectOfClass` -
and, under them, the engine itself, which evaluates JavaScript. So the question each of the twenty-six
has to answer is not *is the function in the release's table* but **what does the release's engine do
that this function would report, and can the port report it without inventing anything**.

The distinction is the whole family. Twenty-six rows read "absent" is the right answer for most of a
framework that a release does not carry at all. It is the wrong answer for a framework the release
carries in full and whose later API is mostly a matter of asking the engine a question the engine can
answer. Twelve of the twenty-six are such a question, and they are carried. Thirteen name a capability
the release's engine has no value for, and they stay absent with the capability named. One cannot be
answered in either direction and says so.

## The engine the release carries, and what it can be asked

`~/.charon/dyld/6.1.3/dyld_shared_cache_armv7` carries `JavaScriptCore.framework` in
`/System/Library/PrivateFrameworks` - the path Apple moved to `/System/Library/Frameworks` exactly at
iOS 7.0, the one framework of this package's 21 whose path differs across the covered range, and the
reason `modules/apple/backports.lua`'s `framework_install_path` exists. The image is the 2012 engine.
It is not a stub and it is not inert: `facts/JavaScriptCore/JSContext.md` carries the same checks.m
answering 151 of 151 on an iPad 2 running 6.1.3, over that engine, including a script that throws
(`checks.m:378` - `Promise` misuse throws a TypeError on the port's engine too, because the port's
Promise is a script the 2012 engine runs), and a `JSContext` whose `exceptionHandler` receives the
thrown value and whose `exception` is then set.

So the port's `JSContext` row answers *there is a JavaScriptCore here* truthfully, and the family below
is built on that answer rather than beside it.

Three measurements of what the engine can hold, all from the release's own files, no device involved:

| question | how | answer |
| --- | --- | --- |
| does the C API have a typed-array entry point? | `tools/cache-index/first-rung.py`, the oldest held rung carrying each name, over the 50 held rungs | 10.0.1 for all thirteen of `JSObjectMakeTypedArray*`, `JSObjectGetTypedArray*`, `JSObjectGetArrayBuffer*`, `JSObjectMakeArrayBufferWithBytesNoCopy` and `JSValueGetTypedArrayType` |
| does the engine have the classes? | the 6.1.3 armv7 cache's own symbol table, read by the same `names.lua` the index is built from | 300 `JSC::` symbols; `JSC::JSArray` (7) and `JSC::JSString` (2) are among them; `JSC::JSArrayBuffer`, `JSC::JSTypedArray`, `JSC::Symbol` and `JSC::Promise` are **0** |
| is the class count a real control? | same search, same file | `JSC::JSArray` and `JSC::JSString` are found, so a search that cannot see a JSC class is not what produced the four zeroes |

## The thirteen that name a value the engine cannot hold: absent

`JSObjectGetArrayBufferByteLength()`, `JSObjectGetArrayBufferBytesPtr()`, `JSObjectGetTypedArrayBuffer()`,
`JSObjectGetTypedArrayByteLength()`, `JSObjectGetTypedArrayByteOffset()`, `JSObjectGetTypedArrayBytesPtr()`,
`JSObjectGetTypedArrayLength()`, `JSObjectMakeArrayBufferWithBytesNoCopy()`,
`JSObjectMakeTypedArrayWithArrayBufferAndOffset()`, `JSObjectMakeTypedArrayWithArrayBuffer()`,
`JSObjectMakeTypedArrayWithBytesNoCopy()`, `JSObjectMakeTypedArray()`, `JSValueGetTypedArrayType()`.

Every one of the thirteen exists to report on, or to make, a value of a kind only an ES6 engine has. The
release's engine has none: not one `JSC::JSArrayBuffer` and not one `JSC::JSTypedArray` among the 300
`JSC::` symbols its own cache carries, and no C entry point that could make one before 10.0.1.

The tempting move is the obvious one, and it is the wrong one. Nine of the thirteen are getters, and
Apple's own answer for a value that is not a typed array is a zero, a null or `kJSTypedArrayTypeNone` -
so a port that returned those unconditionally would link, would not crash, and would be indistinguishable
from correct to any client that never holds a typed array. It would also be a lie to the one client that
does: a caller asking a typed array for its buffer on an engine where the array was made by something
else - a shim, a polyfill, a typed array from a newer context - would be told 0 by a function that has
not looked. `absent` is the honest end, and its effect says what a client actually sees: a weak reference
that is NULL, and no value to ask about.

Carrying them is not a wrapper's work either. A typed array on the release would have to be a value the
2012 engine knows how to make, index and hand to script, and nothing in this package makes engine values.
The workspace does have a JavaScriptCore that has them: `revenant-webkit` builds WebKit 254 with its own
JSC for armv7, where `_JSValueMakeSymbol` and `_JSObjectMakeDeferredPromise` are `T` (defined) symbols.
But both of its `JavaScriptCore.framework` targets declare the *system* framework's install name
(`otool -D` on `build/system/...` and `build/prefixed/...` both answer
`/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore`), the engine lives in the dyld shared
cache and cannot be replaced for one process, and bringing it in costs a loader tweak, `DYLD_FRAMEWORK_PATH`,
`DYLD_INSERT_LIBRARIES` and a re-exec. That is an environment substitution, not a backport, and it changes
the WebKit an application gets as well. `coordination/FLEET.md` carries the measurement and the reasoning
("neither a wall nor a layout question: replacing the engine whole"); this file does not repeat it.

## The row that can be answered in neither direction: `JSValueMakeSymbol()`

`JSValueMakeSymbol(ctx, description)` returns a unique value of the symbol type. There is no such value
on this release: `JSC::Symbol` is 0 among the 300 `JSC::` symbols, and no held release before 16.0 exports
the function. It is `absent`, and the row beside it, `JSValueIsSymbol()`, is carried - see below - so a
client has a way to *find out* that a value is not a symbol before it tries to make one.

The same sentence is what `facts/JavaScriptCore/JSContext.md` already carries for the Objective-C row
`+[JSValue valueWithNewSymbolFromDescription:inContext:]`: the context is told a TypeError and the answer
is undefined, rather than a string or an object standing in for a symbol, because a string standing in
for a symbol is a different value that claims to be the same one.

## The other thirteen, and what each of them is

The thirteen decided in this commit are decided by a value the release's engine cannot hold. The other
thirteen of the twenty-six are not, and the table is what each of them is in the source that defines it,
against the primitive the release's own export table does carry. They are carried by the next commit of
this series, with the code, and this file is rewritten there to say what each one answers.

| row | what the function is | the primitive the release carries |
| --- | --- | --- |
| `JSValueIsArray()` | `toJS(globalObject, value).inherits<JSArray>()` (JSValueRef.cpp:205) | the engine's own `Array.isArray`, which is the same test, and `charon_js_is_array` already asks it of the virtual machine's own context for `-isArray` |
| `JSValueIsDate()` | `inherits<DateInstance>()` (JSValueRef.cpp:217) | `Object.prototype.toString`'s `[[Class]]`, already asked by `charon_js_is_date` for `-isDate` |
| `JSValueIsSymbol()` | `toJS(value).isSymbol()` (JSValueRef.cpp:175) | nothing: no value of this engine is a symbol, so the answer for every value it holds is false |
| `JSObjectGetPropertyForKey()`, `JSObjectSetPropertyForKey()`, `JSObjectHasPropertyForKey()`, `JSObjectDeletePropertyForKey()` | `toJS(globalObject, key).toPropertyKey(globalObject)`, then the same `get`, `put`, `hasProperty` and `deleteProperty` (JSObjectRef.cpp:394-490) | `JSObjectGetProperty`, `JSObjectSetProperty`, `JSObjectHasProperty` and `JSObjectDeleteProperty`, all exported since 3.0 |
| `JSGlobalContextSetName()`, `JSGlobalContextCopyName()` | `globalObject->setName(name->string())` and `name()` (JSContextRef.cpp:223-250) | the name `-[JSContext setName:]` already keeps |
| `JSGlobalContextSetInspectable()`, `JSGlobalContextIsInspectable()` | `globalObject->setInspectable(bool)` and `inspectable()` (JSContextRef.cpp:255-282) | the flag `-[JSContext setInspectable:]` already stores |
| `JSObjectMakeDeferredPromise()` | a promise and its resolving functions (JSObjectRef.cpp:279) | the promise `+[JSValue valueWithNewPromiseInContext:fromExecutor:]` already builds for that context - the same object, not a second one |

Two of these cannot be compared with a host at all, and the fact is stated here rather than discovered
later: `JSGlobalContextSetInspectable` and `JSGlobalContextIsInspectable` are `API_AVAILABLE(macos(NA))`
in the SDK, so macOS's own JavaScriptCore does not carry them and no oracle for them exists on this
machine.
