# MusicKit for a legacy Apple platform

A module named `MusicKit`, for `armv7-apple-ios6.1.3`, so that a program written against MusicKit 26
compiles and runs on a device this port serves.

## What it is

The service is Apple's: the catalogue, the search, the previews and the library are requests to
`api.music.apple.com` over the Apple Music API. What this package adds is the surface — the model
types, the requests and the decoding — and `MusicAuthorization`.

The declarations are transcribed from `MusicKit.swiftinterface` of the 16.4 SDK, which is the SDK the
corpus measures the surface against. What each of them answers is in the table below.

## What it answers, and how

| | |
| --- | --- |
| `MusicItemID` | the catalogue's own string for an item, wrapped whole |
| `MusicItem` | what every catalogue item has: its identifier, and nothing else |
| `MusicAuthorization.currentStatus` | `.notDetermined` — a device with no Apple Music has not been asked |
| `MusicAuthorization.request()` | `.denied` — see below |
| the catalogue types, the requests, the responses | not carried yet; the next delivery |

**`MusicAuthorization` is answered as a device with no Apple Music at all**, which is every device
this port runs on: no Music app, no Apple Music account, and no way to grant one. A request therefore
answers `.denied` — the status a device that will not grant says. That is a real answer and not a
refusal: the call neither fails nor blocks, and a caller that checks the status before it plays gets
a decision it can act on. The interface's own four cases are carried with their four raw values, and
a string that is not one of the four is not a status.

## The toolchain, and why the recipe resolves the compiler

The module compiles for `armv7-apple-ios6.1.3` and **not for 6.0**: the port's Swift standard
library declares 6.1.3 as its own minimum, which is the port's own release. The compiler comes from
`swift-runtime`'s `SWIFT_EXEC` and never from a path, because the store holds two builds of swift
6.4.0 and only the patched one reaches that release — the unpatched one still refuses any target below
iOS 7.0 with *"Swift requires a minimum deployment target of iOS 7.0.0"*, which is the check
`packages/s/swift/patches/no-minimum-ios-for-a-bundled-runtime.patch` removes.

## `async`

**Measured: an `async` function compiles for `armv7-apple-ios6.1.3` under the port's flags, with no
extra flag.** The runtime the port builds carries `libswift_Concurrency.dylib` and
`_Concurrency.swiftmodule` for that release, so the async spellings are real and the catalogue
requests are written with them rather than with a completion handler that is not the API a caller of
MusicKit 26 writes. The interface guards every `async` behind `#if compiler(>=5.3) && $AsyncAwait`
precisely because the two spellings both exist.

What has **not** been measured is that an `async` call *runs* on a device at 6.1.3; that needs the
emulator or a device, and it is the first thing the next delivery does with the first catalogue
request.

## Not carried yet

The catalogue types, the search and library requests, the responses, the players and
`MusicLibrary`. The surface is 1316 rows; this is its foundation — the identity every item has and
the authorization a client asks for before it uses any of it.
