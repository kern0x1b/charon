# Five session entry points, and one API that does not exist to make two of them work

Two objects carry five session entry points, and the split is the build system's own rule rather than a
preference: `VTSessionMultiPass7_0.m` has the multi-pass trio and `VTSessionOutputHandler9_0.m` has the two
output-handler variants. One object holds the API of ONE release, and `relcheck.lua` measured the trio on
the ladder at 7.0 against the handler variants at 9.0:

```
error: 1 objects hold API no single release introduced:
  VideoToolboxBackports: VTSessionVariants9_0.m defines VTCompressionSessionBeginPass
  VTCompressionSessionEndPass VTCompressionSessionGetTimeRangesForNextPass from iOS 7.0 and
  VTCompressionSessionEncodeFrameWithOutputHandler VTDecompressionSessionDecodeFrameWithOutputHandler
  from iOS 9.0; an object carries API that arrived in one release, so split it
```

so the registry's `introduced` for the trio is 7.0, which is what the ladder says, not the 8.0 the
header's own `API_AVAILABLE` claims.

## The multi-pass trio asks the session rather than assuming

`VTCompressionSession.h` says of `VTCompressionSessionBeginPass`, `VTCompressionSessionEndPass` and
`VTCompressionSessionGetTimeRangesForNextPass` that "It is an error to call this function when multi-pass
encoding has not been enabled by setting `kVTCompressionPropertyKey_MultiPassStorage`."

Multi-pass arrived with iOS 9.0 and the 6.1.3 encoder has no such property. That is a claim about the
release, and the release can be asked:

```c
static Boolean session_has_multi_pass_storage(VTCompressionSessionRef session)
{
    CFTypeRef storage = NULL;
    if (VTSessionCopyProperty(session, kVTCompressionPropertyKey_MultiPassStorage, NULL, &storage) != noErr)
        return false;
    Boolean enabled = storage != NULL;
    if (storage)
        CFRelease(storage);
    return enabled;
}
```

So the port does not decide "multi-pass is unsupported" once for the process; it asks the session in
front of it, per call. Two sessions in one process can be in different states and a module-level flag
would answer for both.

| function | session without multi-pass storage | session with one |
| --- | --- | --- |
| `VTCompressionSessionBeginPass` | `kVTParameterErr` (-12902) | `kVTVideoEncoderNotAvailableNowErr` (-12915) |
| `VTCompressionSessionEndPass` | `kVTParameterErr` (-12902) | `kVTVideoEncoderNotAvailableNowErr` (-12915) |
| `VTCompressionSessionGetTimeRangesForNextPass` | `kVTParameterErr` (-12902) | `kVTParameterErr` (-12902) |

`EndPass` does **not** write `*furtherPassesRequestedOut` on either path. The header makes the caller
read it only after a success, and writing `false` on an error would let a caller that forgets to check
the status end its loop believing the encoder wanted no more passes.

`GetTimeRangesForNextPass` names two error conditions in the header - multi-pass never enabled, and
`EndPass` not having asked for another pass - and both are `kVTParameterErr`. So there is one outcome and
not two, and the port writes one `return` rather than two branches with the same value: a check that
reads as if it distinguishes something it cannot is worse than no check. The second condition is also
unreachable here, because no pass ever ends - `BeginPass` and `EndPass` both refuse first.

## The two output-handler variants cannot deliver, and the cause is a measured absence of API

`VTCompressionSessionEncodeFrameWithOutputHandler` and
`VTDecompressionSessionDecodeFrameWithOutputHandler` exist to hand the caller the encoded or decoded
frame through a block passed per call. Both headers say why a session can be used that way at all:

> Cannot be called with a session created with a `VTCompressionOutputCallback`.

so the caller creates the session with a **NULL** callback and passes a block per call instead. But the
callback is fixed at `VTCompressionSessionCreate` / `VTDecompressionSessionCreate` time, and **no API
changes it afterwards**. Measured, by grep over both header sets the port builds and tests against:

```
$ grep -rn "SetOutputCallback\|SetDecompressionOutputCallback" \
      <iphoneos-sdk 16.4>/System/Library/Frameworks/VideoToolbox.framework/Headers
(no output)
$ grep -rn "SetOutputCallback\|SetDecompressionOutputCallback" \
      <iPhoneOS26.2.sdk>/System/Library/Frameworks/VideoToolbox.framework/Headers
(no output)
```

Neither name exists in the 16.4 SDK or the 26.2 one. So the port can start the encode, and there is no
way for it to route the encoder's output to the block the caller handed in.

What it does is the release's own behaviour for a session with no output callback: the frame is encoded
or decoded, the status is passed back untouched because the work really happened, and the output goes
where the release sends output for such a session - nowhere. **The handler is not called, and a caller
cannot see that from the status.** That is the gap, it is Apple's rather than the port's, and it is
written up for `coordination/crutches.md` rather than left in a registry `effect` field nobody reads.

## What was checked, and how

```
$ clang -fsyntax-only -fobjc-arc -Wall -Werror=objc-missing-property-synthesis \
      -target armv7-apple-ios6.0 -isysroot "$(cat /tmp/land/sdkpath)" \
      -Ipackages/a/apple-backports -Ipackages/a/apple-backports/VideoToolbox \
      packages/a/apple-backports/VideoToolbox/VTSessionMultiPass7_0.m
(no output)
$ ... the same for VTSessionOutputHandler9_0.m
(no output)
$ nm -gU .../VTSessionMultiPass7_0.o
_T VTCompressionSessionBeginPass   _T VTCompressionSessionEndPass
_T VTCompressionSessionGetTimeRangesForNextPass
$ nm -gU .../VTSessionOutputHandler9_0.o
_T VTCompressionSessionEncodeFrameWithOutputHandler
_T VTDecompressionSessionDecodeFrameWithOutputHandler
$ BP_LIBRARY=VideoToolboxBackports BP_SDK="$(cat /tmp/land/sdkpath)" xmake l \
      $HOME/Git/projects/ios/coordination/work-2026-10-03/tools/relcheck.lua
compiled 29 objects of VideoToolboxBackports
check_releases: every object of VideoToolboxBackports holds API of one release
```

The host is not the oracle for any of the five: a host that has multi-pass would answer
`furtherPassesRequestedOut` from its own encoder, and a host that has a callback setter would prove the
port's answer wrong rather than right. What the host could confirm - the strings and the enumerator
values - the frame-processor harness already confirms, and the two questions here are about the RELEASE's
API surface, which is measured by reading the two SDKs rather than by running anything.