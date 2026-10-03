# ARKit's 276 missing rows, and what each one is waiting for

Generated from `corpus/ledger-2026-10-03/ARKit.tsv` -- its `missing` rows, 276 of them -- by classifying
each row by its owner class and applying one rule. The rule is the one `Pose.md` states: **a value is
carried when it was measured from something real, and owed when there is nothing to measure it from.**
A row's owner decides which of the two it is, so this is a routing list and not a judgement about any
one row.

Three buckets, and what each one needs before it can be written:

| bucket | rows | what it waits for |
| --- | --- | --- |
| a pose | 27 | an estimate of a body. The tracker here is visual-inertial and estimates a *device* pose; nothing in this workspace turns a frame into a human body. See `Pose.md`. |
| a class or function not carried | 13 | the class itself, decided one whole class at a time. |
| a member of a class this tree does not carry | 236 | the class. A member row cannot be written before its owner exists, or it is a method on nothing. |

The third bucket is the bulk of the work and the least interesting to enumerate: it is the 48 owners
below, and the rule for each is the same -- decide the class, then its members come with it.

## Bucket 1: waiting on a pose -- 27 rows

- `ARSkeleton3D` - 7 row(s)
- `ARSkeleton` - 6 row(s)
- `ARBodyAnchor` - 5 row(s)
- `ARSkeleton2D` - 5 row(s)
- `ARBody2D` - 4 row(s)

## Bucket 2: a class or function not carried -- 13 rows - 13 rows

- `ARAppClipCodeAnchor` - 1 row(s)
- `ARCoachingOverlayView` - 1 row(s)
- `ARCollaborationData` - 1 row(s)
- `ARGeoAnchor` - 1 row(s)
- `ARGeoTrackingConfiguration` - 1 row(s)
- `ARGeoTrackingStatus` - 1 row(s)
- `ARGeometryElement` - 1 row(s)
- `ARGeometrySource` - 1 row(s)
- `ARMatteGenerator` - 1 row(s)
- `ARParticipantAnchor` - 1 row(s)
- `ARPlaneExtent` - 1 row(s)
- `ARSkeletonDefinition` - 1 row(s)
- `ARSkeletonJointNameForRecognizedPointKey()` - 1 row(s)

## Bucket 3: a member of a class this tree does not carry -- 236 rows - 236 rows

- `ARWorldTrackingConfiguration` - 16 row(s)
- `ARGeoTrackingConfiguration` - 14 row(s)
- `ARConfiguration` - 13 row(s)
- `ARReferenceObject` - 13 row(s)
- `ARFaceGeometry` - 9 row(s)
- `ARGeoAnchor` - 9 row(s)
- `ARSkeletonDefinition` - 9 row(s)
- `ARGeometrySource` - 8 row(s)
- `ARBodyTrackingConfiguration` - 7 row(s)
- `ARCoachingOverlayView` - 7 row(s)
- `ARFaceAnchor` - 7 row(s)
- `ARGeometryElement` - 7 row(s)
- `ARFaceTrackingConfiguration` - 6 row(s)
- `ARMeshGeometry` - 6 row(s)
- `ARAppClipCodeAnchor` - 5 row(s)
- `ARGeoTrackingStatus` - 5 row(s)
- `ARImageTrackingConfiguration` - 5 row(s)
- `ARMatteGenerator` - 5 row(s)
- `ARSCNFaceGeometry` - 5 row(s)
- `ARSKView` - 5 row(s)
- `ARSKViewDelegate` - 5 row(s)
- `ARVideoFormat` - 5 row(s)
- `AREnvironmentProbeAnchor` - 4 row(s)
- `ARObjectScanningConfiguration` - 4 row(s)
- `ARCoachingOverlayViewDelegate` - 3 row(s)
- `ARCollaborationData` - 3 row(s)
- `ARDirectionalLightEstimate` - 3 row(s)
- `ARMeshAnchor` - 3 row(s)
- `ARObjectAnchor` - 3 row(s)
- `AROrientationTrackingConfiguration` - 3 row(s)
- `ARPlaneAnchor` - 3 row(s)
- `ARPlaneExtent` - 3 row(s)
- `ARAnchor` - 2 row(s)
- `ARCamera` - 2 row(s)
- `ARDepthData` - 2 row(s)
- `ARFrame` - 2 row(s)
- `ARHitTestResult` - 2 row(s)
- `ARImageAnchor` - 2 row(s)
- `ARLightEstimate` - 2 row(s)
- `ARParticipantAnchor` - 2 row(s)
- `ARPlaneGeometry` - 2 row(s)
- `ARPointCloud` - 2 row(s)
- `ARRaycastQuery` - 2 row(s)
- `ARRaycastResult` - 2 row(s)
- `ARReferenceImage` - 2 row(s)
- `ARTrackedRaycast` - 2 row(s)
- `ARWorldMap` - 2 row(s)
- `ARPositionalTrackingConfiguration` - 1 row(s)
- `ARSession` - 1 row(s)
- `ARTrackable` - 1 row(s)

