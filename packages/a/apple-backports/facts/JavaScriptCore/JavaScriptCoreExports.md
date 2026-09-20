# The C API of JavaScriptCore that iOS 6 already exports

The SDK dates the JavaScriptCore headers after iOS 6, and asked one by one with `dlsym` after every framework
of the release was loaded, iOS 6 exports thirteen of the names the registry would have called absent. They are
the release's own and are not carried here.

Source: an iPad 2 running 6.1.3 and the iOS 6.0 emulator.

## What the release exports

`JSContextGetGlobalContext`, `JSContextGetGroup`, `JSContextGroupCreate`, `JSContextGroupRelease`,
`JSContextGroupRetain`, `JSGlobalContextCreate`, `JSGlobalContextCreateInGroup`, `JSObjectMakeArray`,
`JSObjectMakeDate`, `JSObjectMakeError`, `JSObjectMakeRegExp`, `JSValueCreateJSONString` and
`JSValueMakeFromJSONString`. The framework is one of the release's private ones, and what these functions do was
not compared with a newer release: the names are exported, and nothing more is claimed.

The Objective-C API of iOS 7 (`JSContext`, `JSValue` and the rest) is not in the release, and is absent.
