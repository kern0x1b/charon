# Why Network's floor is iOS 6.0

Every type of Network's C API is an `OS_OBJECT` type: `nw_endpoint_t`, `nw_connection_t`,
`nw_parameters_t` and the rest are `OS_OBJECT_DECL`, which `nw_object.h:32` defines in terms of
`OS_OBJECT_DECL` - a protocol plus a typedef of `NSObject` to that protocol. The port's objects are
`NSObject`s that adopt those protocols, so a release where the object types are not Objective-C
objects has nothing for them to be.

The release decides that, and the SDK says so itself in `usr/include/os/object.h:67`:

```c
#elif TARGET_OS_IOS && __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_6_0
#  define OS_OBJECT_HAVE_OBJC_SUPPORT 0
```

and `OS_OBJECT_USE_OBJC` follows it (`object.h:81-93`): with no Objective-C support the whole family
is 0, so under a deployment target below iOS 6.0 `nw_endpoint_t` is not an `NSObject` protocol
type at all. That is the same measured reason ARKit, Vision and CoreML already sit at 6.0 on this
port.

So **every entry in `registry/Network/` carries `minimum: 6.0`**, the 4.3 band leaves the library
out with the usual note, and nothing of Network is compiled for 4.3 - including the connection
object api-upstreams brought, which is told the same in the delivery note.

`SSLCreateContext` being iOS 5.0 API is therefore moot for this port: the TLS of a connection is
never reached on a release that has no Network.

## Where the 4.3 gate's failing compile actually is

Measured, and it is not the 4.3 band. `xmake l -v` on the 4.3 gate prints the argv of every compile,
and the compile that fails names its own target:

    ccache …/clang -target armv7-apple-ios6.0 -isysroot …/iPhoneOS16.4.sdk … -c …/Network/nw26-path.m

**ios6.0.** The 4.3 gate stages the bands between the deployment and the highest minimum, so it builds a
6.0 band as well as the 4.3 one; the objects placed at 6.0 are compiled for that band, and the first one
that includes `CharonNW.h` is the first that fails. The 4.3 band's own `build/objects/` has no Network
directory, so nothing of Network is compiled at the 4.3 target at all, and the 6.1.3 gate compiles the
same 41 objects at 6.1.3 without an error.

So: every Network object is placed at the 6.0 floor this file measures, none is compiled for 4.3, and
the failure is a 6.0 band whose header set does not carry Network's own protocols - `<Network/Network.h>`
resolves to nothing there, so every `OS_nw_*` is undefined. That is the lift being given a different set
of frameworks per band (`cc435f9d Let a lift read the frameworks its caller names`), and it is the same
family of question as f76910d1's registry-spelling fix rather than a row or a declaration of this
band's. The two things to check next, both outside this tree: whether the 6.0 band's lift is given
Network, and whether a band may name a framework its own minimums place objects at.
