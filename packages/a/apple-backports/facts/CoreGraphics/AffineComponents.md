# CGAffineTransformDecompose and CGAffineTransformMakeWithComponents, iOS 16

Introduced in iOS 16.0 (SDK 26.2 `CGAffineTransform.h`). The header gives the form: the transform is
scale * shear * rotation, with the translation last, and `CGAffineTransformComponents` holds `scale`, `horizontalShear`,
`rotation` and `translation`. The release's answers are measured on the host, not read off the header's matrix alone,
because the header does not say which of the two sign choices a flip takes, nor what a degenerate matrix answers.

Source: the host's CoreGraphics (macOS 27, SDK 26.2), through `tests/backports/host/affine-components`, which holds the
port's own source against it on 28 transforms, 84 checks.

## The matrix

With the matrix `[a b; c d]` acting on row vectors and the translation `(tx, ty)` last, the components give

    a = sx * cos t        b = sx * sin t
    c = sy * (sh * cos t - sin t)        d = sy * (sh * sin t + cos t)

so the first row is `sx` times the rotation's unit vector `u`, and the second row is `sy` times `sh * u + v`, `v` being
`u` turned a quarter. `MakeWithComponents` builds the matrix from these; `Decompose` inverts them.

## Decompose

- `length = hypot(a, b)`, `determinant = a*d - b*c`.
- If `length` is not zero: the flip is `determinant < 0` (a negative zero is not a flip). Then
  `sx = flip ? -length : length`, `sy = flip ? -determinant/length : determinant/length`, and
  `rotation = atan2(b, a)` less pi where the flip is. The sign of `sx` is the flip, `sy` is not negative for a
  transform that is not rank one, and the rotation is turned a half circle with the flip (so a flip in x gives
  rotation 0 and a flip in y gives -pi, the host's own signed zero and sign included).
- If `length` is zero (`a` and `b` both zero): the flip is `d < 0`, `sy = |d|`, `sx = 0`, and the rotation is zero or
  -pi with the flip. The first row says nothing here, so this is the only rule the host gives for it.
- `horizontalShear = sy != 0 ? (c*cos t + d*sin t) / sy : 0`.
- `translation = (tx, ty)`.

## Measured answers the rule rests on

| matrix | scale | shear | rotation |
| --- | --- | --- | --- |
| `(-2, 0, 0, 3)` | (-2, 3) | 0 | 0 |
| `(2, 0, 0, -3)` | (-2, 3) | 0 | -pi |
| `(-2, 0, 0, -3)` | (2, 3) | 0 | +pi |
| `(0, 1, 1, 0)` | (-1, 1) | 0 | -pi/2 |
| `(0, 1, -1, 0)` | (1, 1) | 0 | +pi/2 |
| `(0, 0, 0, -2)` | (0, 2) | 0 | -pi |
| `(0, 0, 1, -1)` | (0, 1) | -1 | -pi |
| `(1, 0, 0, 0)` | (1, 0) | 0 | 0 |
| `(-1, 0, 0, 0)` | (1, -0) | 0 | +pi |

## Where the port does not match the host

A singular transform with two non-zero rows, `(2, 2, 1, 1)`, is not in the battery. The host answers
`scale.height` of about 1e-16 and `horizontalShear` of about 1e16: a rounding artefact of its own arithmetic, which
the components form cannot state exactly. The port answers `scale.height` 0 and `horizontalShear` 0, so it does not
rebuild the second row of such a matrix. Recorded in `packages/a/apple-backports/registry/CoreGraphics/ios16.json`
as the effect of the row.

## Precision

The host's cosine and sine are rounded, so the host's zeros come back as about 1e-16. The battery accepts a relative
difference of 1e-12 (or the absolute difference for a value below 1); the largest measured difference is 2.4e-16.
On armv7 `CGFloat` is a float and the port's answers are float answers; the host test runs the arm64 double path.
