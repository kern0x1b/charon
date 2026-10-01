# AVFoundation release 10 demand rows

Corpus: `DEMAND-AVFoundation-10.tsv`, 5 rows, CRASH-ON-USE, each called by 1 app in the corpus.
`python3 tools/cache-index/first-rung.py playImmediatelyAtRate: initWithOutputSettings: supportedColorSpaces automaticallyConfiguresCaptureDeviceForWideColor automaticallyWaitsToMinimizeStalling`
answers 10.0.1 for all five (10.0.1 is the oldest *held* rung that carries the names; the SDK's own
`introduced` is 10.0, which is what the registry rows use).

`objc.inventory` over `~/.charon/dyld/6.1.3/dyld_shared_cache_armv7` shows `AVPlayerItemVideoOutput`
already carries `-initWithPixelBufferAttributes:` - the same pixel-buffer-attributes dictionary that
`-initWithOutputSettings:` takes under its later name - so `AVFoundationDemand10.m` forwards one to
the other rather than reimplementing the class.

`-playImmediatelyAtRate:` and `automaticallyWaitsToMinimizeStalling` are implemented together: 6.1.3's
`-[AVPlayer setRate:]` already starts playback immediately (6.1.3 has no stall-avoidance wait at all),
so `-playImmediatelyAtRate:` is that same assignment with the header's own guard against being called
while the flag is YES.

`supportedColorSpaces` answers the one color space 6.1.3's capture stack has ever produced
(`AVCaptureColorSpaceSRGB`); `automaticallyConfiguresCaptureDeviceForWideColor` is stored as a real
flag but never finds a wide-color format to switch to, since `supportedColorSpaces` never reports one
on this port's held hardware (no iPad 2 or iPhone 4S camera reports wide color).
