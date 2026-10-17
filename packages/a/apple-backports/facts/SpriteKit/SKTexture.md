# SKTexture (iOS 7)

The iOS 7 surface of SpriteKit's `SKTexture`: a rectangle of an image, its size, its filter and its mipmap flag, and the
two constructors that need no image loader. The port's object is `SpriteKit/SpriteKitTexture7.m`, declared by
`SpriteKit/CharonSpriteKit.h`. The rows are in `registry/SpriteKit/ios7.json` (with the owed constructors), `ios8.json`
(the noise and normal-map members) and `ios9.json` (`CGImage`).

## Oracle and what was measured

The oracle is the host's own SpriteKit: macOS 27.0.1 (26A434), arm64. The committed check is
`tests/backports/host/spritekit-sprite/`: `differential.m` is one runtime-only program built against the host framework
and against the port's objects, and the stdout of the two runs is compared line by line (42 lines, identical); the control
moves a sprite's default anchor point and differs on one line. `crash.m` runs one case per process (see the crash cases
below).

## The measured rules

- `textureWithData:size:` gives a texture of the whole image (rectangle (0, 0, 1, 1)) of the size given (4 by 4 pixels in
  the differential), with the linear filter and no mipmaps.
- `textureWithRect:inTexture:` takes its rectangle in the unit square of the image, and the texture's size is that
  rectangle's size times the image's size. A rectangle (0.25, 0.5, 0.5, 0.25) of a 4 by 4 image has the size (2, 1). A
  rectangle cut from that texture is not composed with the first: a rectangle (0.5, 0.5, 0.5, 0.5) cut from it keeps
  (0.5, 0.5, 0.5, 0.5) and has the size (2, 2), which is the rectangle times the 4 by 4 image.
- A rectangle outside the unit square is stored as given (measured: (0.5, 0.5, 1, 2) of a 4 by 4 image is stored, with the
  size (4, 8)).
- `filteringMode` is stored as set (measured: set to nearest, it reads 0).
- `usesMipmaps` is stored as set (measured: set to YES, it reads YES).
- A copy keeps the rectangle, the size and the filter; it does not keep the mipmap flag (measured: a copy of a texture with
  mipmaps reads NO, and a copy of a nearest-filtered texture reads nearest).

## Crash cases (host, one process each; crash.m and run.sh)

- `textureWithRect:inTexture:` with a nil texture: the host is killed by SIGSEGV (status 139). The port answers nil and
  exits 0.
- `textureWithData:size:` with nil pixels: the host answers nil (measured).
- `textureWithData:size:` with pixels shorter than the size needs (8 bytes for 4 by 4 RGBA): the host answers a texture
  of the size given, with no error (measured). The port does the same and does not check the length.

## Owed and unmeasured

- `textureWithImageNamed:`: the host answers a texture of 128 by 128 for a name that is not found, and logs
  `SKTexture: Error loading image resource: "<name>"` on stderr (measured). The iOS answer is not measured, so the
  constructor is owed to the image loader, and not answered with the host's placeholder.
- `textureWithImage:`, `textureWithCGImage:`, the flipped and row-length `textureWithData:` forms, `preloadTextures:`
  and `preloadWithCompletionHandler:` load pixels: owed with the texture loading.
- `textureByApplyingCIFilter:` needs the renderer: owed with the effects step.
- The NSSecureCoding conformance and the archive: owed with the archive of the node tree.
- `init` on its own is not a row of the SDK and is not measured; the port's `init` gives a whole-image texture of no size.

## Device

The port's texture is device-unverified in the sense that its pixels are not carried yet: the size, rectangle and filter
are the only things it holds. The iOS 7 object is compiled for armv7 only.
