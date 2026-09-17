# UISpringTimingParameters

Introduced in iOS 10.0. A spring, given either as mass, stiffness and damping or
as a damping ratio, with an initial velocity.

Source: UIKit of the armv7s cache of iOS 10.3.4.

## Two forms, one flag

A private `implicitDuration` says which form the object is in. It is set by
`-setMass:`, `-setStiffness:` and `-setDamping:`, so the mass form has it and the
damping-ratio form does not, and everything that has to tell the two apart -
copying, archiving, the description - reads it.

| member | behaviour |
|---|---|
| `-init` | mass 3, stiffness 1000, damping 500, through the setters, so the mass form. |
| `-initWithMass:stiffness:damping:initialVelocity:` | the mass form. |
| `-initWithDampingRatio:initialVelocity:` | the ratio form. |
| `-initWithDampingRatio:` | the same with a zero velocity. |
| `-timingCurveType` | `UITimingCurveTypeSpring`. |
| `-springTimingParameters` | the receiver; `-cubicTimingParameters` is `nil`. |
| `-dampingRatio` | the stored ratio in the ratio form; `damping / (2 * sqrt(mass * stiffness))` in the mass form, and 0 rather than an infinity when that divisor is 0. |
| `-description` | `<%@ (%p) mass=%.3f, stiffness=%.3f, damping=%.3f, velocity=(%.3f,%.3f)>` for the mass form, `<%@ (%p) dampingRatio=%.3f, velocity=(%.3f,%.3f)>` for the other. |

The default spring, mass 3 against stiffness 1000 with damping 500, has a damping
ratio of about 4.56: it is heavily overdamped and does not overshoot.

## Archiving

| key | encoded with | decoded with |
|---|---|---|
| `implicitDuration` | `-encodeBool:forKey:` | `-decodeBoolForKey:` |
| `mass`, `stiffness`, `damping` | a scalar, only in the mass form | the same |
| `dampingRatio` | a scalar, only in the ratio form | the same |
| `velocity` | `-encodeCGVector:forKey:` | `-decodeCGVectorForKey:` |

The scalars are encoded at the width of a `CGFloat`: `-encodeFloat:forKey:` where
it is a float, as it is on every architecture this package is built for, and
`-encodeDouble:forKey:` where it is a double. Apple's own code is the same source
built for both, and reading the armv7s binary alone would have said float
everywhere; the host, where a `CGFloat` is a double, is what shows the other half.

Non-keyed coders raise `NSInvalidUnarchiveOperationException`:
`%@ only supports keyed coding.`

## What is not carried yet

`-settlingDuration` is private and answers how long the spring takes to come to
rest. It calls `+[UIView _durationOfSpringAnimationWithMass:stiffness:damping:velocity:]`,
which iOS 6 does not have, and whose own implementation is an empirical fit -
`-ln(0.001)` over the natural frequency in one branch, and a curve fitted with
the constants 0.3361, -0.0042, -0.0201 and -5.95061 in the other. Nothing in the
public API of this class reaches it. It is carried with
`UIViewPropertyAnimator`, which is what needs it.
