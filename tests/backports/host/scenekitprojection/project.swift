// The port's SCNSceneRenderer.projectPoint / unprojectPoint, against macOS SceneKit's own.
//
// The backports carry neither (measured 2026-09-28: `grep -rn projectPoint packages/a/apple-backports/`
// is empty, while the SDK's SCNSceneRenderer.h:129-142 declares both), so this states the
// arithmetic the port is given and checks it against the system's answers for the same camera and
// the same points. The port's implementation is the same arithmetic in Objective-C; what is checked
// here is the arithmetic, and the device holds the Objective-C to it.
//
// The header (SCNSceneRenderer.h:129-136) is what the shape comes from: projectPoint takes a world
// point and answers in the point-of-view's viewport, with z 0 at the near plane and 1 at the far one.

import Foundation
import SceneKit
import simd

// MARK: The arithmetic the port uses

/// world -> viewport, with z 0 at the near plane and 1 at the far one.
func project(point world: SIMD3<Float>, camera: SCNNode, viewport: CGSize) -> SIMD3<Float> {
    let cameraMatrix = simd_float4x4(camera.worldTransform)
    let eye = cameraMatrix.inverse * simd_float4(world.x, world.y, world.z, 1)
    let cam = SCNCamera()
    let halfFov = Float(cam.fieldOfView) * .pi / 360        // SceneKit's fieldOfView is in degrees, full angle
    let tanHalf = tan(halfFov)
    let aspect = Float(viewport.width / max(viewport.height, 1))
    // SceneKit looks down -z from the camera, so the depth is negative in front of it.
    let depth = max(-eye.z, 1e-6)
    let ndcX = (eye.x / depth) / (tanHalf * aspect)
    let ndcY = (eye.y / depth) / tanHalf
    let near = Float(cam.zNear), far = Float(cam.zFar)
    let z = (depth - near) / max(far - near, 1e-6)
    return SIMD3<Float>((ndcX + 1) / 2 * Float(viewport.width),
                        (1 - ndcY) / 2 * Float(viewport.height),
                        z)
}

/// viewport -> world, the inverse of the above.
func unproject(point screen: SIMD3<Float>, camera: SCNNode, viewport: CGSize) -> SIMD3<Float> {
    let cam = SCNCamera()
    let halfFov = Float(cam.fieldOfView) * .pi / 360
    let tanHalf = tan(halfFov)
    let aspect = Float(viewport.width / max(viewport.height, 1))
    let ndcX = Float(screen.x) / Float(viewport.width) * 2 - 1
    let ndcY = 1 - Float(screen.y) / Float(viewport.height) * 2
    let near = Float(cam.zNear), far = Float(cam.zFar)
    let depth = near + Float(screen.z) * (far - near)
    let eye = SIMD3<Float>(ndcX * tanHalf * aspect * depth, ndcY * tanHalf * depth, -depth)
    let world = simd_float4x4(camera.worldTransform) * simd_float4(eye.x, eye.y, eye.z, 1)
    return SIMD3<Float>(world.x, world.y, world.z)
}

// MARK: The case

let viewport = CGSize(width: 800, height: 600)
let view = SCNView(frame: CGRect(origin: .zero, size: viewport))
let camera = SCNNode()
let cam = SCNCamera()
cam.fieldOfView = 60
cam.zNear = 1
cam.zFar = 1000
camera.camera = cam
camera.position = SCNVector3(CGFloat(0), CGFloat(0), CGFloat(10))
camera.eulerAngles = SCNVector3(CGFloat(0), CGFloat(0), CGFloat(0))
view.pointOfView = camera
view.scene = SCNScene()
view.layout()

// Points in front of the camera, spread across the viewport and in depth, including the near and far
// planes where the header says z is exactly 0 and 1.
let points: [SIMD3<Float>] = [
    SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(-1, -1, 0),
    SIMD3<Float>(0, 0, -9), SIMD3<Float>(0, 0, -9.999), SIMD3<Float>(0, 0, -990), SIMD3<Float>(3, -2, -5),
]
var worst = 0.0
for point in points {
    let ours = project(point: point, camera: camera, viewport: viewport)
    let theirs = view.projectPoint(SCNVector3(CGFloat(point.x), CGFloat(point.y), CGFloat(point.z)))
    // This SceneKit spells an SCNVector3's components CGFloat; the arithmetic above is Float, so
    // the two are converted where they meet rather than by widening a tolerance.
    let delta = simd_distance(ours, SIMD3<Float>(Float(theirs.x), Float(theirs.y), Float(theirs.z)))
    worst = max(worst, Double(delta))
    let mark = delta < 0.01 ? "ok  " : "DIFF"
    print("\(mark) point (\(point.x), \(point.y), \(point.z)) ours (\(ours.x), \(ours.y), \(ours.z)) theirs (\(theirs.x), \(theirs.y), \(theirs.z)) delta \(delta)")
    let back = unproject(point: SIMD3<Float>(Float(theirs.x), Float(theirs.y), Float(theirs.z)),
                         camera: camera, viewport: viewport)
    let round = simd_distance(back, point)
    worst = max(worst, Double(round))
    print("\(round < 0.01 ? "ok  " : "DIFF") unproject -> (\(back.x), \(back.y), \(back.z)) round trip \(round)")
}
print("worst delta \(worst)")
print(worst < 0.01 ? "scenekitprojection: OK - the port's projection is the system's" : "scenekitprojection: FAILED - the port's projection is not the system's")
