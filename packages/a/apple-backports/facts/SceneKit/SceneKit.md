# SceneKit: the .scn archive format, measured against real Telegram assets

Source of the measurements below: `/Applications/Telegram.app/Contents/Resources/{gift,diamond,star2,coin,badge,business,lightspeed,star,swirl}.scn`,
the macOS Telegram client installed on the development machine — a static app
resource, not user data. Read with `plutil -p` and with Python's `plistlib`
(walking `$objects`/`$class`/`$classname` to trace which object references
which). Cross-checked against a real `SCNScene(url:)` load on macOS SceneKit
via a throwaway Swift script, which is a real, running Apple SceneKit acting
as a behavior oracle, not a guess. iOS-asset equivalence is assumed, not
measured: the iOS bundle carries `gift2_<version>.scn` behind a decompression
step, and the version suffix is a real reason the two could differ. If they
do, `SCNKeyedUnarchiver`'s failure will name the missing class or leave a
property at its default — loud or silent-but-visible, not a crash.

## Fact: every color is a nested keyed archive, not an object reference

`SCNLight.color`, `.shadowColor`, `SCNParticleSystem.particleColor` are never
resolved through the outer archive's `$objects` table the way every other
object property is. Each is an `NSMutableData` whose bytes are themselves a
complete, independent `NSKeyedArchiver` payload (own `$archiver`/`$top`/
`$objects`), written by the real `NSColor` on the authoring Mac. Its root
object is class `"NSColor"`, with `NSColorSpace` (`NSICC` profile blob +
`NSSpaceID`) and `NSComponents` (a dictionary whose `NSRGB` or `NSWhite`
key holds a plain space-separated string of floats, e.g.
`"0.5764705882 0.4470588235 1 1"`).

This is a fact about Apple's keyed-archive format in general, not a SceneKit
peculiarity — the next reader who opens a `.plist`/`.scn`/`.data`-carrying
archive from Apple's own tooling should expect nested archives inside
`NSData` fields wherever the original author used a class the top-level
archiver didn't want to embed directly.

Implementation: `CharonSCNCoding.decodeColor:forKey:` opens a *second*
`NSKeyedUnarchiver` over the `NSData`, with `requiresSecureCoding = YES` and
`[unarchiver setClass:[CharonSCNArchivedColor class] forClassName:@"NSColor"]`
— it never requires a class actually named `NSColor` to exist (it does not,
on this platform). `CharonSCNArchivedColor` reads `NSComponents`/`NSRGB`/
`NSWhite` and vends a `UIColor`. This works unconditionally, independent of
whether an iOS-authored archive nests `NSColor` or `UIColor` — if it turns
out to be `UIColor` directly, `decodeColor:` already has a plain-object
fallback path.

## Fact: image/file content is `{"path": "<name>"}`, resolved beside the .scn

`SCNMaterialProperty.contents` and `SCNParticleSystem.particleImage`, when
they hold a file reference, do not carry image bytes. They are archived as
`{"path": "<filename>"}`, e.g. `coin.scn`'s three diffuse textures decode to
the literal strings `"lighterTexture.jpg"`, `"darkerTexture.jpg"`,
`"texture.jpg"`, and `gift.scn`'s `particleImage` decodes to `"particles.png"`.
In every case the named file is a flat sibling of the `.scn` in
`Contents/Resources/` — confirmed by `find`, not assumed.

`CharonSCNCoding.decodePathContents:forKey:` resolves this relative to the
scene's own source URL, tracked through `+[CharonSCNCoding pushSourceURL:]`/
`popSourceURL`/`currentSourceURL` (a small explicit stack, pushed by
`+[SCNScene sceneWithURL:options:error:]` around the decode and popped
after) — not a hidden global read at decode time from an ambient location.
This mirrors the real mechanism `loadCompressedScene` already depends on:
Telegram decompresses to a temp directory first specifically so this
relative resolution has something to resolve against.

## Two "вероятно" from the previous turn, closed by tracing referrers, not by reading types

- **`SCNPlane`** in `gift.scn`: exactly one instance, referenced only by
  `SCNParticleSystem.emitterShape` (never by any node's `.geometry`). It is
  a shape for particle emission math, not a drawn surface. Its own
  `.materials` array holds one `SCNMaterial` that has never had any of
  `diffuse`/`ambient`/`specular`/etc. touched (none of those keys appear in
  its archived dictionary) — every `SCNGeometry` carries a materials array
  by construction, this one is inert.
- **`SCNMaterial`/`SCNMaterialProperty`** in `gift.scn`: the nine
  `SCNMaterialProperty` instances belong to `SCNLight.gobo`/
  `.probeEnvironment` (five different lights) and `SCNScene.background`/
  `.environment` — not to any visible mesh (there is none in this file) and
  not to particles either (particle appearance goes through
  `particleImage`/`particleColor` directly, not through a `SCNMaterial`).
  None of the nine carry a `contents` key at all. Consequence: `gift` and
  `diamond` need zero texture-decoding code for materials — only property
  bags that decode to their defaults.

## Divergence table: API name vs. archive key name

The single most dangerous class of bug here: property exists, decoder
doesn't recognize the archive key, value silently stays at its default,
nothing crashes, the scene renders looking wrong. Keep this list as the one
place that protects against it — do not scatter individual notes in code
comments.

| Class | Public API name | Archive key | Effect if missed |
| --- | --- | --- | --- |
| `SCNNode` (`SCNParticleSystemSupport` category) | `particleSystems` (array) | `particleSystem` (**singular**, one object — plural `particleSystems` array key also exists and is additionally checked) | a node's particle emitter never attaches; nothing emits |
| `SCNCamera` | `fieldOfView` | `yFov` (falls back to `fov`) | camera renders at whatever default FOV we pick instead of the authored one — wrong framing |
| `SCNLight` | `categoryBitMask` | `lightCategoryBitMask` | light/geometry category masking silently doesn't match; harmless unless the scene relies on masks to exclude a light from some geometry — not the case in `gift`/`diamond`/`star2`/`coin`, all lights hit everything |
| `SCNLight` | `automaticallyAdjustsShadowProjection` | `autoShadowProjection` | not implemented this turn (shadow-quality tier, see skip list) — recorded here so whoever adds it does not re-derive the divergence |

## Skip list: keys read from the archive but not decoded, by class, with visual weight

Not decoding these is a real, named cut — not an oversight. Split by
whether the owner is the *authoring tool* (Xcode's Scene Editor: editor
state, bookkeeping) or the *renderer* (would visibly change the picture if
wired up).

**`SCNLight`** (measured on `gift.scn`'s five light instances: types
`ambient`, `omni`×2, `area`, `directional`×2):
- editor-only, no visual effect if skipped: `baked`, `version`,
  `shouldBakeIndirectLighting`, `shouldBakeDirectLighting`,
  `usesDeferredShadows`, `usesModulatedMode`, `shadowSampleCount2`,
  `scncolor`/`scnShadowColor` (private float4 duplicates of `color`/
  `shadowColor`, redundant with the nested-archive path already decoded).
- shadow-quality tier, real visual effect but only on shadow *softness/cost*,
  not on whether a shadow exists (`castsShadow`/`shadowColor`/`shadowRadius`
  are decoded): `shadowMapSize`, `shadowSampleCount`, `shadowBias`,
  `shadowCascadeCount`, `shadowCascadeSplittingFactor`, `orthographicScale`,
  `maximumShadowDistance`, `forcesBackFaceCasters`,
  `sampleDistributedShadowMaps`, `automaticallyAdjustsShadowProjection`
  (archived `autoShadowProjection`, see divergence table).
- area-light geometry, real visual effect, skipped because `gift`/`diamond`
  use `area` type but our decoder does not yet read it:
  `areaExtentsX`/`Y`/`Z` (public API exposes these as one `simd_float3
  areaExtents` — the archive splits them into three scalars, a second,
  smaller divergence worth folding into the table above once implemented),
  `areaPolygonVertices`, `drawsArea`, `doubleSided`, `areaType`. An area
  light without these falls back to a point-light approximation — visibly
  softer/harder than authored.
- probe/IES tier, not used by any of the four target files per the earlier
  per-file class survey (no `SCNLightTypeProbe`/`SCNLightTypeIES` instance
  found): `IESProfileURL`, `probeType`, `probeUpdateType`, `probeExtents`,
  `probeOffset`, `parallaxCorrectionEnabled`, `parallaxExtentsFactor`,
  `parallaxCenterOffset`, `sphericalHarmonicsCoefficients` (also `readonly`
  — computed, never authored, so there is nothing to decode regardless).

**`SCNCamera`** (measured on `gift.scn`'s one camera): decoded
`fieldOfView`, `zNear`, `zFar`, `usesOrthographicProjection`,
`orthographicScale`, `automaticallyAdjustsZRange`. Everything else in the
archive is post-processing the real device never had cause to reproduce
faithfully and that materially changes the look if half-wired: `wantsHDR`,
`bloomIntensity`/`bloomThreshold`/`bloomIteration`/`bloomIterationSpread`/
`bloomBlurRadius`, `wantsDepthOfField`/`focusDistance`/
`focalBlurSampleCount`/`fStop`/`apertureBladeCount`(archived
`bladeCount`)/`sensorHeight`(archived `sensorSize`), `motionBlurIntensity`,
`screenSpaceAmbientOcclusion*` (four keys), `wantsExposureAdaptation` and
its seven `exposureAdaptation*`/`minimumExposure`/`maximumExposure`/
`exposureOffset` companions, `grainIntensity`/`grainScale`/`grainIsColored`,
`colorFringeIntensity`/`colorFringeStrength`, `vignettingIntensity`/
`vignettingPower`, `contrast`/`saturation`/`whitePoint`/`averageGray`,
`whiteBalanceTemperature`/`whiteBalanceTint`, `focalLength`,
`projectionDirection`, `fillMode`, `categoryBitMask`. All of these are real
SceneKit render features (bloom, DOF, SSAO, exposure, film grain, vignette,
color grading) — skipping them means the port's picture is flatter and
sharper than Apple's own renderer would produce, every one of them a
legitimate deferred-implement, not a "doesn't matter."

**`SCNParticleSystem`**: decoded the emission/velocity/lifespan/size/color/
image/shape/blend/sort/lighting/gravity-coupling surface (see
`SCNParticleSystem.m`). Skipped, all with real per-particle visual effect:
`seed` (deterministic-vs-random look between runs), `particleMass`/
`particleMassVariation`, `particleBounce`/`particleBounceVariation`,
`particleFriction`/`particleFrictionVariation`, `particleCharge`/
`particleChargeVariation` (all four feed physics-field force response —
`gift.scn`'s particles are `affectedByPhysicsFields: true` against a
`SCNPhysicsRadialGravityField`, so an unset `particleMass` defaulting to 1
is an approximation, not a no-op), `particleIntensity`/
`particleIntensityVariation`, `particleDiesOnCollision`/
`physicsCollisionsEnabled`/`softParticlesEnabled`/`blackPassEnabled`,
`isLocal`, `birthLocation`, `renderingMode`, `writesToDepthBuffer`,
`fixedTimeStep`, `dampingFactor`, the `imageSequence*` family (sprite-sheet
animation — `gift.scn`'s `particleImage` decode showed a plain
`{"path":...}`, not an image-sequence configuration, so this tier is
confirmed inert for this file, not merely skipped), `birthDirection`
(archived as raw bytes the same shape as `emittingDirection`, not yet
wired).

**`SCNPhysicsField`**: decoded `strength`, `falloffExponent`,
`minimumDistance`, `active`, `exclusive`, `usesEllipsoidalExtent`, `scope`,
`categoryBitMask`. Skipped: `halfExtent`, `offset`, `direction` (all three
are `SCNVector3`, likely the same raw-bytes shape as node transforms —
not yet measured on the field object itself, only inferred from the header;
flagged here rather than assumed and left silently wrong).

**`SCNMaterial`**: decoded `name`, the full readonly `SCNMaterialProperty`
slot set (`diffuse`/`ambient`/`specular`/`normal`/`reflective`/`emission`/
`transparent`/`multiply`/`displacement`/`ambientOcclusion`/
`selfIllumination`/`metalness`/`roughness`), `lightingModelName`,
`doubleSided`, `transparency`, `shininess`, `blendMode`. Skipped, measured
present on `gift.scn`'s inert plane material and real on `coin.scn`'s PBR
meshes: `fresnelExponent`, `indexOfRefraction`, `transparencyMode`,
`cullMode`, `litPerPixel`, `fillMode`, `locksAmbientWithDiffuse`,
`avoidsOverLighting`, `colorBufferWriteMask`, `writesToDepthBuffer`,
`readsFromDepthBuffer`, `selfIlluminationOcclusion`. All real rendering
knobs; none block a mesh from appearing, all can make it look subtly wrong
(culling, depth test, transparency compositing mode).

## Visual-accuracy deficit list — first entry: `gift.scn`'s main light is an area light

This is the running list `check_releases`/the skip list above promised: not
"what's missing" but "what will look wrong, and why." First concrete entry,
not a hypothetical one.

`gift.scn`'s `"frontal"` light — its main light, per the macOS SceneKit
oracle dump — has `type = area`. The `SCNLightTypeArea` constant itself is
carried honestly: `SCNLight.type` reads the real archived string and answers
`"area"` truthfully. But the *behavior* an area light implies — a light with
physical extent, producing a soft-edged shadow and a falloff shaped by that
extent and by `areaPolygonVertices`/`drawsArea`, not the sharp single-point
falloff of an omni or directional light — is not implemented by this port's
renderer. `areaExtentsX/Y/Z`, `areaPolygonVertices` and `drawsArea` are on
the skip list above, decode-but-unused.

Net effect: `gift.scn` decodes completely and correctly — the type is read,
the value returned, nothing crashes or lies about what kind of light it is —
but the rendered scene's main light will look like whatever this port's
point/directional fallback produces, not the soft area-light SceneKit's own
renderer would draw. When the picture looks wrong, this is where to look
first: not a decode bug, a renderer gap, on the very first tier.

This is not a reason to withhold the constant. An application that asks
`SCNLight.type` and gets the true answer behaves correctly; one that gets a
false answer does not. The surface is carried honestly; the renderer's gap
is named honestly beside it, not hidden behind a truthful-looking property.

## `xmake f -y` without `-c` after an edit can silently not re-evaluate the package

`-y` alone, run again after changing an already-configured package's sources,
can hand back a cached "already satisfied" decision without re-checking the
package at all — a config log a few dozen lines long with no mention of the
package's name anywhere in it is the sign, not a green exit code by itself.
`-c` (full reconfigure) is what actually forces the package requirement to
be re-evaluated. Measured on this port: a config run right after splitting
`SCNLightTypeProbe` out of `SCNLightConstants10.m` produced a 46-line log
with zero mentions of `apple-backports` and exit 0 — looked done, proved
nothing. The same command with `-c` produced a real several-thousand-line
band rebuild and a freshly digested install path.

## `tools/release-split.lua` — the release-splitting check the build gate does not fully cover

`band()`/`band_ranges()` in `modules/apple/backports.lua` catch a symbol
whose introduced release does not match its object file's other symbols only
against the one release each already-existing band boundary happens to
check against — a registry's declared `introduced` version gets rounded up
to the nearest of those boundaries first. Two symbols declared for the same
rounded-up boundary can share a `.m`, link clean, and still be a full release
apart in truth. Measured on this port: `SCNLightTypeIES` and
`SCNLightTypeProbe` were both declared `introduced: "10.0"` in one object
file; `check_releases` and `band()` both accepted it and
`libSceneKitBackports.dylib` linked and installed with no complaint.
`tools/release-split.lua`, walking the real `~/.charon/dyld/*` cache ladder
symbol by symbol instead of by band boundary, found `SCNLightTypeProbe`
already exporting at 9.0 — the registry entry was wrong by a full release,
underneath a green gate. Run it before a band build, not instead of one: see
the script's own header for what it does and does not cover.

## `SCNParticlePropertyController.animation` is not a `CAAnimation` reference in the archive

Measured on `gift.scn`, confirmed by the real guest decode failing loudly before this was
fixed: the archive's `animation` key under a `SCNParticlePropertyController` is not a
`CAAnimation` object reference at all. It is a generic, engine-agnostic dictionary --
`{"class": "animation", "animation": {"keyframe": {...16 key/value pairs...}}}` -- that
Xcode's Scene Editor emits instead of relying on `CAAnimation`'s own `NSCoding`. Reconstructing
a real `CAKeyframeAnimation` from that dictionary shape is not implemented; `initWithCoder:`
now accepts either a real `CAAnimation` (kept) or a dictionary (silently kept nil, not
crashed). Effect: `SCNParticlePropertyController.animation` is `nil` for every controller
gift.scn/diamond.scn carry, so whichever particle property they meant to vary over life
does not vary -- named here as visual-accuracy deficit list item two, alongside the area
light. Do not extend `initWithCoder:` for this key from the four fields seen in one
`gift.scn` instance without re-checking a wider sample first (the dictionary format may
carry more animation kinds -- basic, spring -- than keyframe).

## `SCNPhysicsRadialGravityField` has no public header at all

Unlike every other class in this facts file, `SCNPhysicsRadialGravityField`
is not declared anywhere in `SceneKit.framework/Headers/*.h` in SDK 16.4.
Apple exposes it only indirectly, through `+[SCNPhysicsField
radialGravityField]`, which returns a plain `SCNPhysicsField *`-typed
pointer to a private concrete subclass — the same pattern the archive
depends on by naming the class directly (`$classname: "SCNPhysicsRadialGravityField"`,
confirmed by `plutil`/`plistlib` on `gift.scn`, `diamond.scn`, `star2.scn`,
`coin.scn`). Our port declares this class itself, in `CharonSCN.h`, since
there is no Apple header to import it from. The same will likely be true
for `SCNPhysicsVortexField` (needed only by `swirl.scn`, outside the current
four-file scope) and any other field subclass reached later.

## `gift.scn` decodes correctly on a real armv7 guest — measured, not just built

`SCNScene`, `SCNNode`, `SCNGeometry`, `SCNPlane`, `SCNLight`, `SCNCamera`,
`SCNMaterial`, `SCNMaterialProperty`, `SCNParticleSystem`,
`SCNParticlePropertyController`, `SCNPhysicsField`,
`SCNPhysicsRadialGravityField`, the `NSValue(SceneKitAdditions)` category,
and the shared `CharonSCNCoding` helper — the complete class set `gift.scn`
and `diamond.scn` need per the per-file class survey (`gift`/`diamond` share
an identical `$classname` set; neither uses `SCNGeometrySource`/
`SCNGeometryElement`, which are `star2`/`coin`-only).

A probe (`.agent-work/plan-and-analysis/gift-probe/`, scratch, not committed)
embeds the real `gift.scn` bytes, decodes them through the actual
`SCNScene sceneWithURL:options:error:` entry point on the emulated `iPhone4,1
6.1.3` armv7 guest, and printf/fflush's the node tree. Result: `pass`,
`failures=0`, tree matches the real macOS SceneKit oracle node-for-node,
including child order (`particles → particles 3 → particles 4 → particles 2`,
not ascending — could not reproduce by coincidence).

Getting there cost five real, guest-caught decode failures, each fixed before
moving on, none described as a finding without a fix:

1. `SCNNode`'s `particleSystem` key (singular) decodes to an `NSArray`, not a
   bare `SCNParticleSystem` — `NSKeyedUnarchiver` named the key, the expected
   class and the real one directly.
2. `SCNPlane` overrode `-initWithCoder:` without redeclaring
   `+supportsSecureCoding`, which Foundation refuses even though the
   superclass already returns `YES` for it.
3. `SCNParticlePropertyController.animation` is not a `CAAnimation` reference
   in the archive at all — Xcode's Scene Editor serializes it as a generic
   `{"class": "animation", "animation": {"keyframe": {...}}}` dictionary.
   Reconstructing a real animation from that shape is not implemented;
   `initWithCoder:` now keeps it `nil` rather than crash — visual-accuracy
   deficit list item two.
4. `decodeBoolForKey:` throws when the archive stores the property as a plain
   integer instead of a boolean-tagged plist value — measured on
   `castsShadow` (archived as `0`, an integer).
5. The archive does **not** encode BOOL-shaped properties uniformly: `hidden`
   really is a boolean-tagged value where `castsShadow` is an integer, in the
   same file. A blanket switch to `decodeIntegerForKey:` (item 4's first fix)
   broke `hidden` immediately — a second, separate guest-caught failure from
   generalizing off one measured sample instead of re-checking. Fixed with a
   `CharonSCNCoding.decodeBool:forKey:default:` that tries `decodeBoolForKey:`
   first and falls back to `decodeIntegerForKey:` on exception, rather than
   assuming either encoding.

**Honest remainder on the diff itself.** Every printed property whose value
differs from its class's init default (`particleLifeSpan=2` vs default `1`,
`particleVelocity=1.65` vs default `0`, five `SCNLight.type` strings across
five nodes including `"area"`, which no single default could produce) is
proven read from the archive — the value itself is the evidence. Three
properties instead print a value equal to their default:
`SCNParticleSystem.speedFactor` (`1`), `.stretchFactor` (`0`), and
`SCNCamera.fieldOfView` (`60`). For these three, the raw archive was
independently confirmed (via `plistlib`, not the probe) to carry the key
with that same value — `speedFactor: 1.0`, `stretchFactor: 0.0`,
`fov`/`yFov: 60.0` are genuinely present in the object dictionaries. That
proves the key exists in the file; it does not prove the decoder read it
rather than silently falling through to the same-valued default. Closing
that gap needs a value that differs from default on one of these three
specific keys, which `gift.scn` does not happen to provide. Do not spend a
dedicated run chasing it — the cost exceeds the value here.

**`diamond.scn` closed one of the three for free, the same run that was
already planned for the next tier.** `speedFactor` prints `0.85` on four of
its seven particle systems and `0.8502` on the fifth
(`particles_center`) — both away from the init default of `1`, and
distinguishable from each other, which no shared default could produce.
`speedFactor` is now proven read, the same way `particleLifeSpan`/
`particleVelocity`/`SCNLight.type` already were on `gift.scn`. `stretchFactor`
(`0` on all seven systems here too) and `SCNCamera.fieldOfView` (`60`) are
still open — check for them on `star2`/`coin`, whose PBR materials and real
meshes are more likely to carry a non-default value, rather than re-deriving
this paragraph or spending a dedicated run.
