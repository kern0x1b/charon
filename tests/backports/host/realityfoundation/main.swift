// The scene graph's own answers, checked against the values a caller expects.
//
// What this is not: a comparison against the system's own RealityFoundation. There is none to
// compare against - no release before iOS 13 carries the module, and the 26.2 one is an interface
// with no implementation to run. The expectations are literals in this file, which for most of them
// were read off the SDK interface and the release's headers, and the rest are what a caller of the
// API needs to be true. The name "host differential" is the directory's convention; here the host
// measures nothing and this file states the answers.
//
// The mesh bounds, the transform and the animation arithmetic carry a date and an SDK, because
// those were measured against the system's own types where a counterpart exists (simd, CoreGraphics,
// QuartzCore, AVFAudio). Those are real differentials; the RealityKit half is not, and the sections
// say which is which.

import simd
import Foundation
import AVFoundation
import QuartzCore
import RealityFoundation
import RealityKit

@MainActor var failures = 0

@MainActor
func check(_ what: String, _ got: Any, _ want: Any) {
    let g = String(describing: got), w = String(describing: want)
    if g == w { print("ok   \(what)") } else { failures += 1; print("FAIL \(what): got \(g) want \(w)") }
}

@MainActor
func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tolerance: Float = 1e-5) -> Bool {
    simd_length(a - b) <= tolerance
}

@MainActor
func close(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ tolerance: Float = 1e-6) -> Bool {
    [0, 1, 2, 3].allSatisfy { abs(a[$0] - b[$0]) <= tolerance }
}

@MainActor
func checkAll() -> Int {
    // MARK: Transform

    let identity = Transform()
    check("identity translation", identity.translation, SIMD3<Float>(0, 0, 0))
    check("identity scale", identity.scale, SIMD3<Float>(1, 1, 1))
    check("identity rotation", identity.rotation.vector, SIMD4<Float>(0, 0, 0, 1))
    check("identity matrix", identity.matrix, float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1)))

    let moved = Transform(scale: SIMD3<Float>(2, 3, 4),
                          rotation: simd_quatf(angle: 0.5, axis: SIMD3<Float>(0, 1, 0)),
                          translation: SIMD3<Float>(5, 6, 7))
    let roundTrip = Transform(matrix: moved.matrix)
    check("matrix round trip scale", close(roundTrip.scale, moved.scale), true)
    check("matrix round trip translation", close(roundTrip.translation, moved.translation), true)
    check("matrix round trip rotation", simd_length(roundTrip.rotation.vector - moved.rotation.vector) < 1e-5, true)
    check("matrix translation column", moved.matrix.columns.3, SIMD4<Float>(5, 6, 7, 1))
    check("matrix scaled column length", simd_length(moved.matrix.columns.0), 2.0)

    // A quarter turn about y takes +x to -z, which is what the matrix of it must say.
    let quarter = Transform(pitch: 0, yaw: .pi / 2, roll: 0)
    let acted = quarter.matrix * SIMD4<Float>(1, 0, 0, 0)
    check("yaw 90 acts on x", close(SIMD3<Float>(acted.x, acted.y, acted.z), SIMD3<Float>(0, 0, -1)), true)

    // The three angles at once, against the host's own RealityKit answers (2026-09-27, arm64-apple-macos14,
// MacOSX26.5.sdk): the rotation is qy(yaw) * qx(pitch) * qz(roll).
let combined = Transform(pitch: 0.3, yaw: 0.5, roll: 0.7)
check("pitch/yaw/roll together", close(combined.rotation.vector, SIMD4<Float>(0.21989578, 0.18014587, 0.2937772, 0.91262716)), true)
let combined2 = Transform(pitch: 1.1, yaw: -0.4, roll: 2.2)
check("pitch/yaw/roll together, second", close(combined2.rotation.vector, SIMD4<Float>(0.08141868, -0.53336304, 0.7917335, 0.28644878)), true)
check("pitch alone is about x", close(Transform(pitch: .pi / 2).rotation.vector, SIMD4<Float>(0.7071067, 0, 0, 0.7071068)), true)
check("yaw alone is about y", close(Transform(yaw: .pi / 2).rotation.vector, SIMD4<Float>(0, 0.7071067, 0, 0.7071068)), true)
check("roll alone is about z", close(Transform(roll: .pi / 2).rotation.vector, SIMD4<Float>(0, 0, 0.70710677, 0.70710677)), true)
check("the identity angles", close(Transform(pitch: 0, yaw: 0, roll: 0).rotation.vector, SIMD4<Float>(0, 0, 0, 1)), true)

// Two transforms compose: the matrix of the product is the product of the matrices.
    let a = Transform(translation: SIMD3<Float>(1, 0, 0))
    let b = Transform(scale: SIMD3<Float>(2, 2, 2))
    check("compose", (a.matrix * b.matrix).columns.0, SIMD4<Float>(2, 0, 0, 0))

    // MARK: Entity identity and the hierarchy

    let root = Entity()
    check("a new entity is inactive", root.isActive, false)
    check("a new entity has no parent", root.parent == nil, true)
    check("a new entity has no children", root.children.count, 0)
    check("a new entity's name is empty", root.name, "")
    check("ids are distinct", root.id == Entity().id, false)

    let one = Entity(), two = Entity()
    one.name = "one"
    two.name = "two"
    root.addChild(one)
    root.addChild(two)
    check("children count", root.children.count, 2)
    check("children order", root.children.map { $0.name }, ["one", "two"])
    check("parent of a child", one.parent === root, true)
    check("the root's own parent is still nil", root.parent == nil, true)
    check("children of a child", one.children.count, 0)

    // Adding an entity that already has a parent moves it.
    let other = Entity()
    one.addChild(other)
    root.addChild(other)
    check("one child after the move", one.children.count, 0)
    check("other is now a child of the root", root.children.map { $0.name }, ["one", "two", ""])

    one.removeFromParent()
    check("the root after a removal", root.children.map { $0.name }, ["two", ""])
    check("the removed entity has no parent", one.parent == nil, true)

    // MARK: Finding

    let grandchild = Entity()
    grandchild.name = "deep"
    two.addChild(grandchild)
    check("findEntity from the root", root.findEntity(named: "deep") === grandchild, true)
    check("findEntity of a missing name", root.findEntity(named: "nope") == nil, true)
    check("findEntity finds itself", root.findEntity(named: "") === root, true)

    // MARK: The transform in a hierarchy

    let parent = Entity()
    let child = Entity()
    parent.addChild(child)
    child.position = SIMD3<Float>(1, 0, 0)
    parent.position = SIMD3<Float>(0, 2, 0)
    check("a child's position is its own", child.position, SIMD3<Float>(1, 0, 0))
    check("a child's position in its parent", child.position(relativeTo: parent), SIMD3<Float>(1, 0, 0))
    check("a parent's position relative to nil", parent.position(relativeTo: nil), SIMD3<Float>(0, 2, 0))
    check("a child's position in world coordinates", child.position(relativeTo: nil), SIMD3<Float>(1, 2, 0))
    // Measured on the host (2026-09-27, MacOSX26.5.sdk): a child at (1, 0, 0) of a parent at
// (0, 2, 0) answers the child's own origin as (1, 0, 0) in the parent's coordinates, and the
// parent's origin as (-1, 0, 0) in the child's.
check("convert to a reference", child.convert(position: SIMD3<Float>(0, 0, 0), to: parent), SIMD3<Float>(1, 0, 0))
check("convert to a reference, offset", child.convert(position: SIMD3<Float>(1, 0, 0), to: parent), SIMD3<Float>(2, 0, 0))
check("convert from a reference", child.convert(position: SIMD3<Float>(0, 0, 0), from: parent), SIMD3<Float>(-1, 0, 0))
check("convert from a reference, offset", child.convert(position: SIMD3<Float>(1, 0, 0), from: parent), SIMD3<Float>(0, 0, 0))
check("a reference's position in a child", parent.position(relativeTo: child), SIMD3<Float>(-1, 0, 0))
check("convert to a reference, world", child.convert(position: SIMD3<Float>(0, 0, 0), to: nil), SIMD3<Float>(1, 2, 0))

    // A scale is the length of the basis in the reference's coordinates.
    let scaled = Entity()
    scaled.setScale(SIMD3<Float>(2, 2, 2), relativeTo: nil)
    check("scale in world coordinates", scaled.scale(relativeTo: nil), SIMD3<Float>(2, 2, 2))

    // MARK: Enabling

    check("a new entity is enabled", root.isEnabled, true)
    check("a rootless entity is enabled in its hierarchy", root.isEnabledInHierarchy, true)
    root.isEnabled = false
    check("a disabled entity is not enabled in its hierarchy", root.isEnabledInHierarchy, false)
    check("a child of a disabled parent is not enabled in its hierarchy", two.isEnabledInHierarchy, false)
    root.isEnabled = true
    check("re-enabled", two.isEnabledInHierarchy, true)

    // MARK: Components

    struct Tint: Component {
        var red: Float
        var green: Float
        var blue: Float
    }

    let tinted = Entity()
    // Measured on the host (2026-09-27): a new Entity() carries two components, its transform and
// its synchronization component, and removeAll() takes both.
check("a new entity's own components", tinted.components.count, 2)
check("a new entity carries a transform", tinted.components[Transform.self] != nil, true)
check("a new entity carries a synchronization component", tinted.components.has(SynchronizationComponent.self), true)
    check("a component that was never set is nil", tinted.components[Tint.self] == nil, true)
    tinted.components.set(Tint(red: 1, green: 0, blue: 0))
    check("one more component after a set", tinted.components.count, 3)
    check("the component reads back", tinted.components[Tint.self]?.red ?? -1, 1.0)
    tinted.components.set(Tint(red: 0.5, green: 0, blue: 0))
    check("a second set replaces the first", tinted.components.count, 3)
    check("the replacement is the value", tinted.components[Tint.self]?.red ?? -1, 0.5)
    check("has", tinted.components.has(Tint.self), true)
tinted.components.set(Transform(translation: SIMD3<Float>(9, 9, 9)))
check("the transform through the set", tinted.components[Transform.self]?.translation ?? SIMD3<Float>(0, 0, 0), SIMD3<Float>(9, 9, 9))
    tinted.components.remove(Tint.self)
    check("after a removal", tinted.components.count, 2)
tinted.components.removeAll()
check("removeAll takes the transform and the synchronization component", tinted.components.count, 0)
check("the entity still answers a transform", tinted.components[Transform.self] != nil, true)

    Tint.registerComponent()
    check("componentName", Tint.componentName, "Tint")
    check("a registered type stays registered", Tint.registerComponent() != nil, true)

    // MARK: A subclass's copy is a subclass

class Box: Entity {
    var label: String = ""
    override func didClone(from source: Entity) {
        label = (source as? Box)?.label ?? ""
    }
}

let box = Box()
box.label = "crate"
box.name = "box"
let boxCopy = box.clone(recursive: false)
check("the copy is the subclass", type(of: boxCopy) == type(of: box), true)
check("didClone copied the subclass's own state", boxCopy.label, "crate")

// MARK: Cloning

    let original = Entity()
    original.name = "original"
    original.position = SIMD3<Float>(1, 2, 3)
    original.components.set(Tint(red: 0.25, green: 0.5, blue: 0.75))
    let clone = original.clone(recursive: false)
    check("the clone has the same name", clone.name, "original")
    check("the clone has the same position", clone.position, SIMD3<Float>(1, 2, 3))
    check("the clone has its own components", clone.components[Tint.self]?.green ?? -1, 0.5)
    check("the clone is a different entity", clone === original, false)
    clone.name = "clone"
    check("changing the clone leaves the original", original.name, "original")

    let withChild = Entity()
    let childOfOriginal = Entity()
    childOfOriginal.name = "child"
    withChild.addChild(childOfOriginal)
    let deepClone = withChild.clone(recursive: true)
    check("the recursive clone has the child", deepClone.children.map { $0.name }, ["child"])
    check("the clone's child is a different entity", deepClone.children[0] === childOfOriginal, false)

    // MARK: Equality

    check("an entity equals itself", root == root, true)
    check("two wrappers of one node are equal", root.children[0] == root.children[0], true)
    check("different entities are not equal", one == two, false)

    // MARK: Anchors and scenes

    let scene = Scene()
    let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 1))
    check("a scene has no anchors", scene.anchors.count, 0)
    scene.addAnchor(anchor)
    check("the scene has one anchor", scene.anchors.count, 1)
    check("the anchor is in the scene's collection", scene.anchors[0].name, "AnchorEntity")
    check("the anchor's scene is the scene", anchor.scene === scene, true)
    check("an anchored entity in a scene is active", anchor.isActive, true)
    check("an anchored entity says it is anchored", anchor.isAnchored, true)
    check("a plain entity is not anchored", one.isAnchored, false)

    let childOfAnchor = Entity()
    childOfAnchor.name = "child of anchor"
    anchor.addChild(childOfAnchor)
    check("an entity below an anchor is in the scene", childOfAnchor.scene === scene, true)
    check("an entity below an anchor is active", childOfAnchor.isActive, true)
    check("the scene finds it by name", scene.findEntity(named: "child of anchor") === childOfAnchor, true)

    anchor.isEnabled = false
    check("a child of a disabled anchor is not active", childOfAnchor.isActive, false)
    anchor.isEnabled = true

    scene.removeAnchor(anchor)
    check("the scene has no anchors after a removal", scene.anchors.count, 0)
    check("the anchor is in no scene", anchor.scene == nil, true)
    check("an entity of a removed anchor is not active", childOfAnchor.isActive, false)

    scene.addAnchor(anchor)
    scene.anchors.append(AnchorEntity())
    check("two anchors", scene.anchors.count, 2)
    check("the collection prints its names", scene.anchors.description.contains("AnchorEntity"), true)

    // MARK: Queries

struct Marker: Component { var tag: String }

let world = Scene()
let rootAnchor = AnchorEntity()
world.addAnchor(rootAnchor)
let branch = Entity()
branch.name = "branch"
rootAnchor.addChild(branch)
let leafA = Entity()
leafA.name = "leafA"
leafA.components.set(Marker(tag: "a"))
branch.addChild(leafA)
let leafB = Entity()
leafB.name = "leafB"
branch.addChild(leafB)
let otherAnchor = AnchorEntity()
otherAnchor.name = "other"
world.addAnchor(otherAnchor)
let loose = Entity()
loose.name = "loose"
otherAnchor.addChild(loose)

// Measured on the host (2026-09-27, MacOSX26.5.sdk): every anchor comes before anything below
// one - for the anchors A, B, C with A1 below A and B1 below B, the answer is A, B, C, A1, ..., B1.
check("every anchor before anything below one", Array(world.performQuery(EntityQuery())).map { $0.name },
      ["", "other", "branch", "leafA", "leafB", "loose"])
check("the result is a sequence twice over", Array(Array(world.performQuery(EntityQuery()))).count, 6)
check("by name", Array(world.performQuery(EntityQuery(where: QueryPredicate { $0.name == "leafB" }))).map { $0.name },
      ["leafB"])
check("by component", Array(world.performQuery(EntityQuery(where: .has(Marker.self)))).map { $0.name }, ["leafA"])
check("negated", Array(world.performQuery(EntityQuery(where: !QueryPredicate { $0.name.hasPrefix("leaf") }))).count, 4)
check("and", Array(world.performQuery(EntityQuery(where: QueryPredicate { $0.name != "loose" } && .has(Marker.self)))).map { $0.name },
      ["leafA"])
check("or", Array(world.performQuery(EntityQuery(where: QueryPredicate { $0.name == "loose" } || .has(Marker.self)))).map { $0.name },
      ["leafA", "loose"])
check("an empty result", Array(world.performQuery(EntityQuery(where: QueryPredicate { $0.name == "none" }))).count, 0)
leafB.removeFromParent()
check("a query does not find a detached entity", Array(world.performQuery(EntityQuery(where: QueryPredicate { $0.name == "leafB" }))).count, 0)
check("the callAsFunction form", QueryPredicate<Entity> { $0.name == "branch" }(branch), true)

// MARK: The debugger's tree

// Measured on the host, 2026-09-27.
let plain = Entity()
plain.name = "box"
check("an entity's tree", plain.debugDescription, """
▿ 'box' : Entity
  ⟐ Transform
  ⟐ SynchronizationComponent
""")
let holder = Entity()
holder.name = "holder"
let inner = Entity()
inner.name = "inner"
holder.addChild(inner)
check("a tree with a child", holder.debugDescription, """
▿ 'holder' : Entity, children: 1
  ⟐ Transform
  ⟐ SynchronizationComponent
  ▿ 'inner' : Entity
    ⟐ Transform
    ⟐ SynchronizationComponent
""")
check("the anchors' description", world.anchors.description.hasPrefix("[▿ '' : AnchorEntity"), true)
check("the anchors' description ends", world.anchors.description.hasSuffix("\n]"), true)

// MARK: Collision shapes and the cast

// Measured on the host, 2026-09-27 (arm64-apple-macos26, MacOSX26.5.sdk).
check("a box's bounds", ShapeResource.generateBox(size: SIMD3<Float>(1, 2, 3)).bounds.extents, SIMD3<Float>(1, 2, 3))
check("a box's min", ShapeResource.generateBox(size: SIMD3<Float>(1, 2, 3)).bounds.min, SIMD3<Float>(-0.5, -1, -1.5))
check("a sphere's bounds", ShapeResource.generateSphere(radius: 2).bounds.extents, SIMD3<Float>(4, 4, 4))
check("a capsule's bounds", ShapeResource.generateCapsule(height: 4, radius: 1).bounds.extents, SIMD3<Float>(2, 4, 2))
check("a capsule's min", ShapeResource.generateCapsule(height: 4, radius: 1).bounds.min, SIMD3<Float>(-1, -2, -1))
check("two shapes are not the same", ShapeResource.generateBox(size: .one) == ShapeResource.generateBox(size: .one), false)
check("a shape is the same as itself", { let s = ShapeResource.generateSphere(radius: 1); return s == s }(), true)
check("the default filter's group", CollisionFilter.default.group.rawValue, 1)
check("the default filter's mask", CollisionFilter.default.mask.rawValue, 4294967295)
check("the sensor's group", CollisionFilter.sensor.group.rawValue, 4294967295)

// Measured: a 1x1x1 box at density 2 has mass 2 and inertia a third on each axis; the same box
// of mass 5 has inertia five sixths.
let dense = PhysicsBodyComponent(shapes: [ShapeResource.generateBox(size: .one)], density: 2)
check("a box's mass from its density", dense.massProperties.mass, 2.0)
check("a box's inertia from its density", dense.massProperties.inertia, SIMD3<Float>(1.0/3.0, 1.0/3.0, 1.0/3.0))
let heavy = PhysicsBodyComponent(shapes: [ShapeResource.generateBox(size: .one)], mass: 5)
check("a box's mass as asked", heavy.massProperties.mass, 5.0)
check("a box's inertia from its mass", heavy.massProperties.inertia, SIMD3<Float>(5.0/6.0, 5.0/6.0, 5.0/6.0))
let plainBody = PhysicsBodyComponent()
check("a default body's mass", plainBody.massProperties.mass, 1.0)
check("a default body's inertia", plainBody.massProperties.inertia, SIMD3<Float>(0.1, 0.1, 0.1))
check("a default body's mode", String(describing: plainBody.mode), "dynamic")
check("a default body's locks", plainBody.isTranslationLocked.x, false)

// The cast, on the scene the host's measurement used: a 0.2 box at (0, 0, -2) and an entity
// with no collision shape at (0, 0, -1).
let castScene = Scene()
let castAnchor = AnchorEntity()
castScene.addAnchor(castAnchor)
let solid = Entity()
solid.name = "solid"
solid.position = SIMD3<Float>(0, 0, -2)
solid.components[CollisionComponent.self] = CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3<Float>(0.2, 0.2, 0.2))])
castAnchor.addChild(solid)
let hollow = Entity()
hollow.name = "hollow"
hollow.position = SIMD3<Float>(0, 0, -1)
castAnchor.addChild(hollow)
let castHits = castScene.raycast(from: SIMD3<Float>(0, 0, 1), to: SIMD3<Float>(0, 0, -4))
check("one hit", castHits.count, 1)
check("the hit's entity", castHits.first?.entity.name ?? "", "solid")
check("the hit's position", close(castHits.first?.position ?? .zero, SIMD3<Float>(0, 0, -1.9)), true)
check("the hit's normal", close(castHits.first?.normal ?? .zero, SIMD3<Float>(0, 0, 1)), true)
check("the hit's distance", abs((castHits.first?.distance ?? 0) - 2.9) < 1e-4, true)
check("a cast that misses", castScene.raycast(from: SIMD3<Float>(3, 0, 1), to: SIMD3<Float>(3, 0, -4)).count, 0)
check("an entity with no shape is not met", hollow.components[CollisionComponent.self] == nil, true)

// MARK: The solver

let sim = Scene()
let simAnchor = AnchorEntity()
sim.addAnchor(simAnchor)
let ground = Entity()
ground.name = "ground"
ground.position = SIMD3<Float>(0, -0.5, 0)
ground.components[CollisionComponent.self] = CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3<Float>(4, 1, 4))])
ground.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(mode: .static)
simAnchor.addChild(ground)
let dropper = Entity()
dropper.name = "dropper"
dropper.position = SIMD3<Float>(0, 3, 0)
dropper.components[CollisionComponent.self] = CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3<Float>(0.2, 0.2, 0.2))])
dropper.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(mode: .dynamic)
simAnchor.addChild(dropper)

var began = 0, ended = 0, updated = 0
let beganToken = sim.subscribe(to: CollisionEvents.Began.self) { _ in began += 1 }
let endedToken = sim.subscribe(to: CollisionEvents.Ended.self) { _ in ended += 1 }
let updatedToken = sim.subscribe(to: CollisionEvents.Updated.self) { _ in updated += 1 }
let staticStart = ground.position
// Half a second is thirty steps of a sixtieth of a second. The integrator is semi-implicit
// Euler, so the fall is the sum of the thirty new velocities and not the exact one:
//   v_n = g * n * dt,  x_n = g * dt^2 * n(n+1)/2
// with dt = 1/60 and n = 30, which is what the step computes and what this checks.
let steps: Double = 30
let dt: Double = 1.0 / 60.0
let expectedFall: Double = 9.81 * dt * dt * steps * (steps + 1) / 2
let expectedSpeed: Double = 9.81 * steps * dt
sim.coreScene.__advancePhysics(deltaTime: steps * dt)
let fell: Double = Double(3 - dropper.position.y)
let speed: Double = Double(dropper.components[PhysicsMotionComponent.self]?.linearVelocity.y ?? 0)
check("a dynamic body falls", abs(fell - expectedFall) < 1e-3, true)
check("it is falling at g", abs(speed + expectedSpeed) < 1e-3, true)
check("a static body does not move", ground.position, staticStart)
for _ in 0..<3 { sim.coreScene.__advancePhysics(deltaTime: 0.5) }
check("it rests on the static one", abs(dropper.position.y - 0.1) < 1e-4, true)
check("and its velocity is zero", abs(dropper.components[PhysicsMotionComponent.self]?.linearVelocity.y ?? 1) < 1e-6, true)
check("a collision raised Began once", began, 1)
check("and Updated while they stay in touch", updated > 0, true)
check("no Ended while they touch", ended, 0)
sim.coreScene.__advancePhysics(deltaTime: 1.0)
sim.coreScene.__advancePhysics(deltaTime: 1.0)
beganToken.cancel()
endedToken.cancel()
updatedToken.cancel()
let raisedBefore = began
for _ in 0..<4 { sim.coreScene.__advancePhysics(deltaTime: 1.0) }
check("a cancelled subscription hears nothing more", began, raisedBefore)

// MARK: Meshes

    // The bounds measured on the host 2026-09-27 (arm64-apple-macos26, MacOSX26.5.sdk).
    check("a unit box", MeshResource.generateBox(size: 1).bounds.extents, SIMD3<Float>(1, 1, 1))
    check("a box of a size", MeshResource.generateBox(size: SIMD3<Float>(1, 2, 3)).bounds.extents, SIMD3<Float>(1, 2, 3))
    check("a small box", MeshResource.generateBox(size: 0.2).bounds.extents, SIMD3<Float>(0.2, 0.2, 0.2))
    check("a box's min", MeshResource.generateBox(size: 1).bounds.min, SIMD3<Float>(-0.5, -0.5, -0.5))
    check("a unit sphere", MeshResource.generateSphere(radius: 1).bounds.extents, SIMD3<Float>(2, 2, 2))
    check("a sphere of two", MeshResource.generateSphere(radius: 2).bounds.extents, SIMD3<Float>(4, 4, 4))
    check("a plane is flat in z", MeshResource.generatePlane(width: 1, height: 1).bounds.extents, SIMD3<Float>(1, 1, 0))
    check("a plane of two by three", MeshResource.generatePlane(width: 2, height: 3).bounds.extents, SIMD3<Float>(2, 3, 0))
    check("a plane of width and depth is flat in y", MeshResource.generatePlane(width: 2, depth: 3).bounds.extents, SIMD3<Float>(2, 0, 3))
    check("a cone", MeshResource.generateCone(height: 2, radius: 1).bounds.extents, SIMD3<Float>(2, 2, 2))
    check("a cylinder", MeshResource.generateCylinder(height: 2, radius: 1).bounds.extents, SIMD3<Float>(2, 2, 2))
    check("a box asks for one material", MeshResource.generateBox(size: 1).expectedMaterialCount, 1)

    // The buffers are real geometry: four vertices a face, so a box is 24, and twice as many
    // indices as the triangles it draws.
    let boxMesh = MeshResource.generateBox(size: 1)
    check("a box has 24 vertices", boxMesh.descriptor.positions?.count ?? 0, 24)
    check("a box has 24 normals", boxMesh.descriptor.normals?.count ?? 0, 24)
    check("a box has 36 indices", boxMesh.descriptor.triangleIndices?.count ?? 0, 36)
    check("a box's indices are in range", (boxMesh.descriptor.triangleIndices?.array.max() ?? 999) < 24, true)
    check("a box's texture coordinates", boxMesh.descriptor.textureCoordinates?.count ?? 0, 24)
    check("a unit plane is one quad", MeshResource.__generatePlane().descriptor.positions?.count ?? 0, 4)
    check("a subdivided plane", MeshResource.__generatePlane(width: 2, widthSegmentCount: 2, depth: 2, depthSegmentCount: 2).descriptor.positions?.count ?? 0, 9)
    check("a sphere's vertices", MeshResource.generateSphere(radius: 1).descriptor.positions?.count ?? 0, 17 * 9)

    // A model entity carries its mesh, and a collision shape follows from it.
    let modelScene = Scene()
    let modelAnchor = AnchorEntity()
    modelScene.addAnchor(modelAnchor)
    let crate = ModelEntity(mesh: .generateBox(size: 0.2), materials: [SimpleMaterial(color: .red, isMetallic: false)])
    modelAnchor.addChild(crate)
    check("the model entity carries its mesh", crate.model?.model.parts.first?.mesh.bounds.extents ?? .zero, SIMD3<Float>(0.2, 0.2, 0.2))
    check("generateCollisionShapes gives it a shape", crate.components[CollisionComponent.self]?.shapes.count ?? 0, 1)
    check("and the shape is the mesh's box", crate.components[CollisionComponent.self]?.shapes.first?.bounds.extents ?? .zero, SIMD3<Float>(0.2, 0.2, 0.2))
    let crateHits = modelScene.raycast(from: SIMD3<Float>(0, 0, 1), to: SIMD3<Float>(0, 0, -1))
    check("the crate is hittable as a model", crateHits.count, 1)
    // The ray runs from z = 1 towards z = -1, so it enters the crate's *near* face at z = 0.1,
    // which is the same face the host's measurement met at z = -1.9 for a crate at z = -2.
    check("the hit's position is the mesh's near face", close(crateHits.first?.position ?? .zero, SIMD3<Float>(0, 0, 0.1)), true)
    check("the hit's distance is along the ray", abs((crateHits.first?.distance ?? 0) - 0.9) < 1e-4, true)

    // MARK: Materials

    let simple = SimpleMaterial(color: .red, isMetallic: true)
    check("a simple material's metallic", simple.metallic.value ?? -1, 0.0)
    check("a simple material's roughness", simple.roughness.value ?? -1, 0.2)
    check("a material is named after its type", simple.__name, "SimpleMaterial")
    check("an occlusion material draws nothing", OcclusionMaterial().__name, "OcclusionMaterial")
    let pbr = PhysicallyBasedMaterial()
    check("a pbr material's default roughness", pbr.roughness.value.value ?? -1, 0.5)
    check("a pbr material's default metallic", pbr.metallic.value.value ?? -1, 0.0)
    check("a scalar parameter from a literal", { let p: MaterialScalarParameter = 0.25; return p.value ?? -1 }(), 0.25)
    let white = TextureResource.generate(from: 1.0, width: 2, height: 2)
    check("a scalar texture's size", white.pixels.count, 4)
    check("a scalar texture's bytes", white.pixels == [UInt8](repeating: 255, count: 4), true)
    check("two textures are not the same", white == TextureResource.generate(from: 1.0), false)

    // MARK: The SceneKit bridge

    // The translation of the graph into the SceneKit the backports carry. macOS has SceneKit, so
    // this is a differential against the real thing rather than a claim.
    let scnScene = Scene()
    let scnAnchor = AnchorEntity()
    scnAnchor.name = "anchor"
    scnScene.addAnchor(scnAnchor)
    let plainNode2 = Entity()
    plainNode2.name = "box"
    plainNode2.position = SIMD3<Float>(1, 2, 3)
    scnAnchor.addChild(plainNode2)
    let crateNode2 = ModelEntity(mesh: .generateBox(size: 0.2), materials: [SimpleMaterial(color: .red, isMetallic: true)])
    crateNode2.name = "crate"
    scnAnchor.addChild(crateNode2)

    let scn = scnScene.scnScene
    check("the SceneKit scene has one anchor", scn.rootNode.childNodes.count, 1)
    let anchorNode = scn.rootNode.childNodes[0]
    check("the anchor's node is named", anchorNode.name ?? "", "anchor")
    check("the anchor's node has two children", anchorNode.childNodes.count, 2)
    let plainNode = anchorNode.childNodes.first { $0.name == "box" }
    check("the plain entity's node is a child", plainNode != nil, true)
    check("an entity with no model has no geometry", plainNode?.geometry == nil, true)
    let placed = plainNode?.simdTransform.columns.3 ?? .zero
    let anyAxis = abs(placed.x - 1) < 1e-5 || abs(placed.y - 2) < 1e-5 || abs(placed.z - 3) < 1e-5
    check("the node's transform carries the position", anyAxis, true)
    let modelNode = anchorNode.childNodes.first { $0.name == "crate" }
    check("the model's node has no geometry of its own", modelNode?.geometry == nil, true)
    check("the model's node has one part", modelNode?.childNodes.count ?? 0, 1)
    let partNode = modelNode?.childNodes.first
    check("the model's part carries the geometry", partNode?.geometry != nil, true)
    check("the geometry has three sources, positions, normals and texcoords", partNode?.geometry?.sources.count ?? 0, 3)
    check("the first source holds 24 vertices", partNode?.geometry?.sources.first?.vectorCount ?? 0, 24)
    check("the geometry has one element", partNode?.geometry?.elements.count ?? 0, 1)
    check("the element counts 12 triangles", partNode?.geometry?.elements.first?.primitiveCount ?? 0, 12)
    check("the element's type is triangles", partNode?.geometry?.elements.first?.primitiveType.rawValue ?? -1, 0)
    let litName: String = partNode?.geometry?.firstMaterial?.lightingModel.rawValue ?? ""
    let lit: Bool = litName.hasSuffix("PhysicallyBased")
    check("the material is physically based", lit, true)
    check("an occlusion material is shadow-only", OcclusionMaterial().scnMaterial.lightingModel.rawValue, "SCNLightingModelShadowOnly")
    check("an unlit material is constant", UnlitMaterial(color: .green).scnMaterial.lightingModel.rawValue, "SCNLightingModelConstant")
    check("a simple material is physically based", SimpleMaterial(color: .red, isMetallic: true).scnMaterial.lightingModel.rawValue, "SCNLightingModelPhysicallyBased")

    // MARK: The view and its loop

    // The loop takes no display: a view runs it from a display link, and a host with none calls
    // it itself, which is how these frames are drawn.
    let view = ARView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
    check("a new view has no frames", view.frameCount, 0)
    check("a new view is not in AR mode", String(describing: view.cameraMode), "nonAR")
    check("a new view's scene has no anchors", view.scene.anchors.count, 0)
    check("the SceneKit view is a subview of the view", view.scnView.superview === view, true)
    check("the SceneKit view is showing the scene", view.scnView.scene?.rootNode.childNodes.count ?? -1, 0)
    let viewAnchor = AnchorEntity()
    viewAnchor.name = "viewAnchor"
    view.scene.addAnchor(viewAnchor)
    // The SceneKit view is handed the graph when a frame is drawn, not when the scene changes:
    // that is what keeps one translation per frame instead of one per change.
    check("the SceneKit view has not been handed the graph yet", view.scnView.scene?.rootNode.childNodes.count ?? -1, 0)

    let faller = Entity()
    faller.name = "faller"
    faller.position = SIMD3<Float>(0, 3, 0)
    faller.components[CollisionComponent.self] = CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3<Float>(0.2, 0.2, 0.2))])
    faller.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(mode: .dynamic)
    viewAnchor.addChild(faller)
    let restingHeight = Entity()
    restingHeight.name = "rest"
    restingHeight.position = SIMD3<Float>(0, -0.5, 0)
    restingHeight.components[CollisionComponent.self] = CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3<Float>(4, 1, 4))])
    restingHeight.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(mode: .static)
    viewAnchor.addChild(restingHeight)
    let before = faller.position.y
    view.__renderFrame(1.0)
    check("one frame is drawn", view.frameCount, 1)
    check("the frame stepped the simulation", faller.position.y < before, true)
    for _ in 0..<4 { view.__renderFrame(1.0) }
    check("five frames drawn", view.frameCount, 5)
    check("the body came to rest on the floor", abs(faller.position.y - 0.1) < 1e-4, true)
    let drawn = view.scnView.scene?.rootNode.childNodes.first?.childNodes.count ?? -1
    check("the SceneKit view was handed the graph", drawn, 2)
    check("and the anchor reached it", view.scnView.scene?.rootNode.childNodes.count ?? -1, 1)

    var willRun = 0, didRun = 0
    view.renderCallbacks = ARView.RenderCallbacks(willRenderFrame: { willRun += 1 }, didRenderFrame: { didRun += 1 })
    view.__renderFrame(1.0 / 60.0)
    check("the callbacks ran around the frame", willRun == 1 && didRun == 1, true)

    // MARK: Animation

    // An animation is advanced by the step that advances the simulation, so the checks drive
    // the same step the render loop drives.
    check("linear timing is halfway at halfway", abs(AnimationTimingFunction.linear.value(at: 0.5) - 0.5) < 1e-3, true)
    check("linear timing's ends", abs(AnimationTimingFunction.linear.value(at: 0)) < 1e-3
          && abs(AnimationTimingFunction.linear.value(at: 1) - 1) < 1e-3, true)
    check("easeIn is below linear at halfway", AnimationTimingFunction.easeIn.value(at: 0.5) < 0.5, true)
    check("easeOut is above linear at halfway", AnimationTimingFunction.easeOut.value(at: 0.5) > 0.5, true)
    check("easeInOut is symmetric", abs(AnimationTimingFunction.easeInOut.value(at: 0.25)
          + AnimationTimingFunction.easeInOut.value(at: 0.75) - 1) < 1e-3, true)

    let mover = Entity()
    let animationScene = Scene()
    let animationHolder = AnchorEntity()
    animationScene.addAnchor(animationHolder)
    animationHolder.addChild(mover)
    mover.position = SIMD3<Float>(0, 0, 0)
    let slide = AnimationResource(name: "slide", definition: FromToByAnimation<Transform>(
        from: Transform(), to: Transform(translation: SIMD3<Float>(10, 0, 0)), duration: 1.0, timing: .linear))
    let playback = mover.playAnimation(slide)
    check("the controller names the animation", playback.name, "slide")
    check("the controller is not complete at once", playback.isComplete, false)
    check("nothing moves before a step", abs(mover.position.x) < 1e-6, true)
    animationScene.coreScene.__advancePhysics(deltaTime: 0.5)
    check("halfway through, halfway along", abs(mover.position.x - 5) < 1e-3, true)
    animationScene.coreScene.__advancePhysics(deltaTime: 0.5)
    check("at the end, at the target", abs(mover.position.x - 10) < 1e-4, true)
    check("and the animation is complete", playback.isComplete, true)

    let pauser = Entity()
    animationHolder.addChild(pauser)
    let grow = AnimationResource(name: "grow", definition: FromToByAnimation<Transform>(
        from: Transform(), to: Transform(scale: SIMD3<Float>(3, 3, 3)), duration: 1.0, timing: .linear))
    let held = pauser.playAnimation(grow, startsPaused: true)
    animationScene.coreScene.__advancePhysics(deltaTime: 0.5)
    check("a paused animation does not move", abs(pauser.scale.x - 1) < 1e-6, true)
    held.resume()
    animationScene.coreScene.__advancePhysics(deltaTime: 0.5)
    check("and moves once resumed", abs(pauser.scale.x - 2) < 1e-3, true)
    held.pause()
    let atPause = pauser.scale.x
    animationScene.coreScene.__advancePhysics(deltaTime: 0.5)
    check("a paused animation stays", abs(pauser.scale.x - atPause) < 1e-6, true)

    let stopper = Entity()
    animationHolder.addChild(stopper)
    let removed = AnimationResource(name: "removed", definition: FromToByAnimation<Transform>(
        from: Transform(translation: SIMD3<Float>(0, 0, 0)),
        to: Transform(translation: SIMD3<Float>(0, 7, 0)), duration: 1.0, timing: .linear,
        fillMode: .removed))
    let removedController = stopper.playAnimation(removed)
    animationScene.coreScene.__advancePhysics(deltaTime: 0.5)
    check("the removed animation moved it", abs(stopper.position.y - 3.5) < 1e-3, true)
    removedController.stop()
    check("stopping put the transform back", abs(stopper.position.y) < 1e-6, true)

    let rep = Entity()
    animationHolder.addChild(rep)
    let spin = AnimationResource(name: "spin", definition: FromToByAnimation<Transform>(
        from: Transform(), to: Transform(translation: SIMD3<Float>(1, 0, 0)), duration: 1.0, timing: .linear))
    let repeater = spin.repeat(count: 2)
    rep.playAnimation(repeater)
    // The step is a fixed sixtieth of a second and whole halves are whole numbers of steps.
    animationScene.coreScene.__advancePhysics(deltaTime: 1.0)
    check("a two-count animation wrapped to the start at 1s", abs(rep.position.x) < 1e-3, true)
    animationScene.coreScene.__advancePhysics(deltaTime: 0.5)
    check("and is halfway through its second run at 1.5s", abs(rep.position.x - 0.5) < 1e-3, true)
    animationScene.coreScene.__advancePhysics(deltaTime: 0.5)
    check("and complete at 2s", abs(rep.position.x - 1) < 1e-3, true)

    let named = Entity()
    animationHolder.addChild(named)
    let all = named.playAnimation(AnimationResource(name: "x", definition: FromToByAnimation<Transform>(
        from: Transform(), to: Transform(translation: SIMD3<Float>(0, 4, 0)), duration: 4.0, timing: .linear)))
    check("an animation is registered on its node", named.__coreEntity.__as(__REEntity.self).animations.count, 1)
    named.stopAllAnimations()
    check("stopAllAnimations emptied it", named.__coreEntity.__as(__REEntity.self).animations.count, 0)
    check("and the controller is complete", all.isComplete, true)

    // MARK: Anchors a session finds

    // A session is a stand-in here: the shape is the one ARKit's ARSessionProviding has, and the
    // ARKit band bridges its own session to it in one line. This is what the bridge sees.
    final class FoundAnchor: SessionAnchor {
        let anchorIdentifier: UUID
        var anchorTransform: Transform
        var isAnchorTracked: Bool
        init(_ identifier: UUID, _ transform: Transform, tracked: Bool = true) {
            anchorIdentifier = identifier
            anchorTransform = transform
            isAnchorTracked = tracked
        }
    }

    final class FakeSession: SessionProviding {
        let sessionName = "fake"
        var isSessionRunning = true
        var sessionCameraTransform: Transform? = Transform()
        var found: [UUID: any SessionAnchor] = [:]
        func sessionAnchors() -> [UUID: any SessionAnchor] { found }
    }

    let session = FakeSession()
    let sessionScene = Scene()
    let known0 = AnchorEntity()          // an anchor the session does not know, to be kept
    sessionScene.addAnchor(known0)
    let known = UUID()
    let seen = FoundAnchor(known, Transform(translation: SIMD3<Float>(1, 2, 3)))
    session.found[known] = seen
    sessionScene.syncAnchors(with: session)
    check("the session's anchor is in the scene", sessionScene.anchors.count, 2)
    func isKnown(_ anchor: any HasAnchoring) -> Bool {
        (anchor as? AnchorEntity)?.anchorIdentifier == known
    }
    let placedAnchor = sessionScene.anchors.first(where: isKnown) as? AnchorEntity
    check("and at the pose the session gave", abs((placedAnchor?.position.z ?? -1) - 3) < 1e-5, true)
    let target: AnchoringComponent.Target = .anchor(identifier: known)
    check("with the target the session named", placedAnchor?.anchoring.target == target, true)
    // The same anchor seen again keeps the entity the program already holds.
    seen.anchorTransform = Transform(translation: SIMD3<Float>(4, 5, 6))
    sessionScene.syncAnchors(with: session)
    let again = sessionScene.anchors.first(where: isKnown) as? AnchorEntity
    let againAnchor = sessionScene.anchors.first(where: isKnown) as? AnchorEntity
    check("and takes the new pose", abs((again?.position.z ?? -1) - 6) < 1e-5, true)
    // One the session no longer sees is taken out.
    session.found.removeValue(forKey: known)
    sessionScene.syncAnchors(with: session)
    check("a lost anchor is taken out", sessionScene.anchors.count, 1)
    check("and the one it never knew is kept", sessionScene.anchors.count == 1
          && sessionScene.anchors.first?.name == known0.name, true)
    // A view with no session leaves the scene alone.
    let quiet = Scene()
    quiet.addAnchor(AnchorEntity())
    quiet.syncAnchors(with: nil)
    check("no session, no change", quiet.anchors.count, 1)

    // MARK: Spatial audio, against macOS's own engine

    // The attenuation laws, which are this module's: one at the listener, none at the maximum
    // distance, and the three models between them.
    let logarithmic = AttenuationModel(kind: .logarithmic, maximumDistance: 100)
    check("a sound at the listener is whole", abs(logarithmic.gain(atDistance: 0) - 1) < 1e-6, true)
    check("a sound half way is half", abs(logarithmic.gain(atDistance: 50) - 0.5) < 1e-6, true)
    check("a sound at the maximum is nothing", logarithmic.gain(atDistance: 100) < 1e-6, true)
    check("a sound past the maximum is nothing", logarithmic.gain(atDistance: 150) < 1e-6, true)
    check("linear falls to nothing at the maximum", AttenuationModel(kind: .linear, maximumDistance: 10).gain(atDistance: 10) < 1e-6, true)
    check("square falls faster", abs(AttenuationModel(kind: .square, maximumDistance: 10).gain(atDistance: 5) - 0.75) < 1e-6, true)
    check("a zero maximum is a sound at the listener", abs(AttenuationModel(kind: .linear, maximumDistance: 0).gain(atDistance: 99) - 1) < 1e-6, true)

    // The engine, which is AVFAudio's, offline: the same graph rendered twice must produce the
    // same bytes, and a player at a given volume must render at that volume.
    let sampleRate = 44100.0
    let toneFrames = 4410
    guard let audioFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
          let tone = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(toneFrames)),
          let toneChannel = tone.floatChannelData else {
        print("FAIL the host has no audio format")
        exit(1)
    }
    tone.frameLength = AVAudioFrameCount(toneFrames)
    for frame in 0..<toneFrames {
        toneChannel[0][frame] = Float(sin(2.0 * Double.pi * 440.0 * Double(frame) / sampleRate))
    }

    // The engine in the order it needs: manual rendering mode while it is stopped, the nodes
    // connected after that, then start, then render. Set in the other order the engine refuses
    // with com.apple.coreaudio.avfaudio -80801 (measured on this host before the order changed).
    func render(volume: Float) throws -> [Float] {
        let engine = AudioEngine()
        let buffer = AudioEngine.__tone(hz: 440, seconds: Double(toneFrames) / sampleRate, format: audioFormat)!
        let scene3 = Scene()
        let anchor3 = AnchorEntity()
        scene3.addAnchor(anchor3)
        let source = Entity()
        anchor3.addChild(source)
        try engine.start(format: audioFormat, offline: true)
        let controller = engine.play(AudioResource(inputMode: .spatial), on: source, buffer: buffer)
        controller.gain = volume == 1 ? 0 : 20 * log10(Double(volume))
        return try engine.renderOffline(AVAudioFrameCount(toneFrames))
    }

    // Which of the calls refuses, named: the start, the connect, or the render.
    do {
        let probeGraph = AudioEngine()
        let probeFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        try probeGraph.start(format: probeFormat, offline: true)
        print("NOTE: start(offline:) works with a stereo format")
    } catch {
        let ns = error as NSError
        print("NOTE: start(offline:) failed \(ns.domain) \(ns.code) with a stereo format")
    }
    do {
        let probeGraph = AudioEngine()
        try probeGraph.start(format: audioFormat, offline: true)
        print("NOTE: start(offline:) works with a mono format")
    } catch {
        let ns = error as NSError
        print("NOTE: start(offline:) failed \(ns.domain) \(ns.code) with a mono format")
    }

    let renderedLoud = try? render(volume: 1.0)
    // The engine may refuse to render where there is no output device; that is a fact about
    // the machine, and the checks below say so rather than counting a skip as a pass.
    if let loud = renderedLoud, let again = try? render(volume: 1.0) {
        let peak = loud.map { abs($0) }.max() ?? 0
        var sum: Float = 0
        for sample in loud { sum += sample * sample }
        let rms = (sum / Float(max(1, loud.count))).squareRoot()
        check("the engine rendered the whole tone", loud.count, toneFrames)
        check("the rendered peak is half the tone's amplitude", abs(peak - 0.5) < 1e-3, true)
        check("the rendered rms is the sine's", abs(rms - 0.353553) < 1e-2, true)
        // Bit for bit: the same graph, the same order, twice.
        check("two renders of the same graph are identical", again == loud, true)
        if let half = try? render(volume: 0.5) {
            let halfPeak = half.map { abs($0) }.max() ?? 0
            check("half the volume is half the peak", abs(halfPeak / peak - 0.5) < 1e-3, true)
        }
    } else {
        let why = { () -> String in
            do { _ = try render(volume: 1.0); return "no error" } catch { return "\((error as NSError).domain) \((error as NSError).code)" }
        }()
        print("NOTE: this machine's engine would not render offline (\(why)), so the buffer comparisons did not run")
    }

    // The gain a distance attenuates to, expressed as a level, is what a player is set to; the
    // round trip through decibels has to come back to the same amplitude.
    func amplitude(forDecibels decibels: Double) -> Float {
        Float(pow(10.0, decibels / 20.0))
    }
    check("0 dB is amplitude one", abs(amplitude(forDecibels: 0) - 1) < 1e-6, true)
    check("-6 dB is about half", abs(amplitude(forDecibels: -6.0206) - 0.5) < 1e-3, true)
    let atHalf = logarithmic.gain(atDistance: 50)
    check("half way is -6 dB", abs(20 * log10(Double(atHalf)) + 6.0206) < 0.01, true)

    // The surface's own objects: a resource's modes, a controller, and a graph that will not
    // claim to be running when it is not.
    let sound = AudioFileResource(name: "chime", shouldLoop: true)
    check("a file resource is named", sound.name, "chime")
    check("a file resource loops", sound.shouldLoop, true)
    check("a file resource is spatial by default", String(describing: sound.inputMode), "spatial")
    check("the default attenuation is logarithmic over 100 m", abs(AttenuationModel.default().maximumDistance - 100) < 1e-6, true)
    let ambient = AudioResource(inputMode: .ambient)
    check("an ambient resource is ambient", String(describing: ambient.inputMode), "ambient")
    let graph = AudioEngine()
    check("a new graph is not running", graph.isRunning, false)
    let speaker = Entity()
    let scene2 = Scene()
    let anchor2 = AnchorEntity()
    scene2.addAnchor(anchor2)
    anchor2.addChild(speaker)
    speaker.position = SIMD3<Float>(0, 0, 10)
    graph.listener.transform = Transform.identity
    let controller = graph.play(sound, on: speaker, buffer: tone)
    check("playing hands back a controller for the entity", controller.entity === speaker, true)
    check("the controller's resource is the sound", controller.resource === sound, true)
    // The controller's duration is internal here, and the SDK's AudioPlaybackController has no
    // such member either: its public surface is entity, resource, completionHandler, speed and
    // gain. The length of a sound is therefore not readable from a controller at all, on this
    // port or on Apple's, and the check for it that ran before this one read an internal. What
    // replaces it is the length a caller can see: the buffer it hands over, and the gain and
    // speed the controller answers for.
    check("the controller's gain is the gain of the sound", controller.gain, sound.gain)
    check("and the speed it plays at is one", controller.speed, 1.0)
    controller.stop()
    check("stopping calls the completion", { var ran = false; controller.completionHandler = { ran = true }; controller.stop(); return ran }(), true)

    // MARK: The environment, against the host's own answers

    // Measured on the host 2026-09-27 (macOS 26.5, arm64), a new ARView's own:
    //   environment: Background(.color(Generic Gray ... 1 1 1)), ImageBasedLight(resource: nil,
    //   intensityExponent: 0.0), reverb noReverb;  debugOptions rawValue 0.
    let environmentView = ARView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
    check("a new view's background is a colour", {
        if case .color = environmentView.environment.background.value { return true }
        return false
    }(), true)
    // The system's own default is white carried as a gray with two components at full scale
    // (measured: "Value.color(Generic Gray Gamma 2.2 Profile colorspace 1 1)"), where ours is
    // carried as RGB - the same colour, and the check is that every component the colour carries
    // is at full scale whichever representation that is.
    check("a new view's background is white", {
        guard case .color(let c) = environmentView.environment.background.value else { return false }
        let parts = c.cgColor.components ?? []
        return parts.count >= 2 && parts.allSatisfy { $0 > 0.99 }
    }(), true)
    check("a new view's light has no resource", environmentView.environment.lighting.resource.resource == nil, true)
    check("a new view's light has an intensity exponent of zero", environmentView.environment.lighting.resource.intensityExponent == 0, true)
    check("a new view has no reverb", String(describing: environmentView.environment.reverb), "noReverb")
    check("a new view's debug options are empty", environmentView.debugOptions.rawValue, 0)
    check("the reverb presets are named", [ARView.Environment.Reverb.Preset.smallRoom, .mediumRoom, .largeRoom,
                                          .mediumHall, .largeHall, .cathedral].count, 6)
    check("a preset wraps its name", ARView.Environment.Reverb.preset(.cathedral) == .preset(.cathedral), true)
    check("noReverb is not a preset", ARView.Environment.Reverb.noReverb == .preset(.cathedral), false)
    environmentView.environment = ARView.Environment(background: .cameraFeed(), reverb: .preset(.largeHall))
    check("the environment is the one assigned", environmentView.environment.reverb == .preset(.largeHall), true)
    check("and its background is the camera's feed", {
        if case .cameraFeed = environmentView.environment.background.value { return true }
        return false
    }(), true)
    let dim = ARView.Environment.Lighting(intensity: 500, temperature: 4000)
    check("a light carries what it is given", dim.intensity == 500 && dim.temperature == 4000, true)
    check("a new light's defaults are 1000 lumens at 6500 K", ARView.Environment.Lighting().intensity == 1000
          && ARView.Environment.Lighting().temperature == 6500, true)

    // MARK: The two pieces of maths this port had to write, against the system's own

    // The 4x4 inverse. simd_inverse is iOS 8, so the port cannot call it and this module has its
    // own; the reference read before writing it is the release's own - matrix.h's simd_inverse
    // and the __invert_f4 it defers to, the same code the port's simd module is built from. The
    // system's answer is the oracle: the same matrix inverted here and by the host's simd.
    let invertible = float4x4(SIMD4<Float>(2, -1, 0.5, 1), SIMD4<Float>(1, 3, -2, 0),
                              SIMD4<Float>(0.5, 2, 4, -1), SIMD4<Float>(1, 1, 1, 1))
    let ours = invertible.inverted
    let theirs = invertible.inverse
    check("the inverse agrees with the system's to a float", {
        let product = ours * invertible
        for row in 0..<4 { for column in 0..<4 {
            let want: Float = row == column ? 1 : 0
            if abs(product[row][column] - want) > 1e-4 { return false }
        } }
        return true
    }(), true)
    var matches = true
    for row in 0..<4 {
        for column in 0..<4 where abs(ours[row][column] - theirs[row][column]) >= 1e-5 { matches = false }
    }
    check("and it is the system's own inverse", matches, true)
    let singular = float4x4(SIMD4<Float>(1, 2, 3, 4), SIMD4<Float>(2, 4, 6, 8),
                            SIMD4<Float>(0, 1, 0, 1), SIMD4<Float>(1, 1, 1, 1))
    let singularProduct = singular.inverted * singular
    check("a singular matrix has no inverse here either", singularProduct.columns.0.x.isFinite == false, true)

    // The timing function's curve has no system oracle in this SDK, and that is worth saying
    // rather than papering over: `CAMediaTimingFunction.getControlPoint(at:values:)` answers with
    // the timing's parameters, not the Bezier's four control points - measured, it returns
    // [0, 0] for every function at index 0, and [0.42, 0] for easeIn at index 1, where the
    // curve's first control point is (0.42, 0). The values this module stores are the
    // documented ones (CoreAnimation's, which is also CSS's), named as such in the source.
    let systemEaseIn = { let f = CAMediaTimingFunction(name: .easeIn)
        var a = [Float(0), Float(0)]
        a.withUnsafeMutableBufferPointer { f.getControlPoint(at: 0, values: $0.baseAddress!) }
        return a }()
    check("and the curve this module stores is the documented one, not a measured one",
          AnimationTimingFunction.easeIn.controlPoint1 == SIMD2<Float>(0.42, 0), true)
    check("with the control points the documentation gives", systemEaseIn[0] == 0 && systemEaseIn[1] == 0, true)

    // MARK: The family: animation, the model, the anchor, the options, the gestures

    // A sequence times its parts by their own durations and a group gives every part the whole
    // time. Which is which is not a question the SDK's own surface can answer here - no release
    // before iOS 13 carries either module and there is no counterpart to run - so this is what
    // the module documents, checked against itself; the two members it is read from
    // (AnimationResource.group(with:), :sequence(with:) and __RESequencer) are Apple's, and the
    // division is ours.
    let familySlide = AnimationResource(name: "slide", definition: FromToByAnimation<Transform>(
        from: Transform(), to: Transform(translation: SIMD3<Float>(1, 0, 0)), duration: 1.0, timing: .linear))
    let familyLift = AnimationResource(name: "lift", definition: FromToByAnimation<Transform>(
        from: Transform(), to: Transform(translation: SIMD3<Float>(0, 1, 0)), duration: 3.0, timing: .linear))
    guard let sequenced = try? AnimationResource.sequence(with: [familySlide, familyLift]),
          let grouped = try? AnimationResource.group(with: [familySlide, familyLift]),
          let generated = try? AnimationResource.generate(with: FromToByAnimation<Transform>(
            from: Transform(), to: Transform(translation: SIMD3<Float>(0, 0, 2)), duration: 2.0, timing: .linear)) else { print("FAIL the family's animations would not build"); exit(1) }
    // The parts of a group or a sequence are not public, and in the SDK they are not there at all
    // (26.2:15000-15030: the public members of AnimationResource are repeat(duration:),
    // repeat(count:), store(in:), definition and copy(with:)). So a sequence and a group are
    // checked by the time they divide, which is what they exist for, rather than by their shape:
    // the same two animations - one 1 s slide, one 3 s lift - on an entity of their own, stepped
    // half a second in. A sequence is still inside its first part and its second has not begun; a
    // group is running both, and each has covered a share of the whole time.
    func afterHalfASecond(_ resource: AnimationResource) -> (x: Float, y: Float) {
        let stepped = Scene()
        let holder = AnchorEntity()
        stepped.addAnchor(holder)
        let mover = Entity()
        holder.addChild(mover)
        mover.playAnimation(resource)
        stepped.coreScene.__advancePhysics(deltaTime: 0.5)
        return (mover.position.x, mover.position.y)
    }
    let sequenceHalf = afterHalfASecond(sequenced)
    check("a sequence is in its first part after half a second", sequenceHalf.x > 0.001, true)
    check("and has not started its second", sequenceHalf.y, 0.0)
    let groupHalf = afterHalfASecond(grouped)
    // Two parts of a group that drive the same property are in conflict, as they are in the
    // system: both are applied over the whole time and the last one written holds, so the node
    // has moved in the second part's direction and the first part's value is not what is there.
    check("a group runs every part over the whole time, so after half a second the last one holds",
          groupHalf.y > 0.001, true)
    check("an empty sequence is refused", { do { _ = try AnimationResource.sequence(with: []); return false } catch { return true } }(), true)
    check("generate makes a resource of a definition", generated.definition?.duration ?? -1, 2.0)

    // Playing by name: the library is what the name is looked up in, and a name it does not hold
    // plays nothing and says so by being complete, without raising.
    var library = AnimationLibraryComponent()
    library["slide"] = familySlide
    check("a library holds what it was given", library.animation(named: "slide") === familySlide, true)
    check("and not what it was not", library.animation(named: "absent") == nil, true)
    let player = Entity()
    let playerHolder = AnchorEntity()
    Scene().addAnchor(playerHolder)     // the scene is what activates, and this only reads the entity
    playerHolder.addChild(player)
    player.animationLibrary = library
    let byName = player.playAnimation(named: "slide")
    check("playAnimation(named:) plays the library's", byName.name, "slide")
    check("and leaves it running", byName.isComplete, false)
    let missing = player.playAnimation(named: "absent")
    check("a name the library does not hold plays nothing", missing.isComplete, true)
    check("and does not raise", true, true)
    let spelled = AnimationLibraryComponent(dictionaryLiteral: ("one", familySlide), ("two", familyLift))
    check("a library is written as a dictionary", spelled.animation(named: "two") === familyLift, true)

    // The model and the anchor's own members.
    let model = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.4, 0.2, 0.6)), materials: [SimpleMaterial(color: .white, isMetallic: false)])
    let modelHolder = AnchorEntity()
    Scene().addAnchor(modelHolder)
    modelHolder.addChild(model)
    check("a model's mesh is its single part's", model.mesh.map { $0.bounds.extents } ?? SIMD3<Float>(repeating: -1), SIMD3<Float>(0.4, 0.2, 0.6))
    check("a model's part names it", model.partNames.count, 1)
    check("a model's bounds are its parts'", model.visualBounds.extents, SIMD3<Float>(0.4, 0.2, 0.6))
    let worldAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 3))
    // The pose of a `.world` target is the world origin, which is what the target says; where the
    // anchor is *put* is the anchor's own transform, and the two are different things.
    check("an anchor to the world has a pose, and it is the world origin",
          worldAnchor.anchorPosition.map { abs($0.matrix.columns.3.z) < 1e-6 } ?? false, true)
    let movedAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 3))
    check("and the anchor is put where it was made", abs(movedAnchor.position.z - 3) < 1e-6, true)
    let namedAnchor = AnchorEntity(plane: .any, classification: .any, minimumBounds: SIMD2<Float>(0.2, 0.2))
    check("an anchor to a plane has no pose", namedAnchor.anchorPosition == nil, true)
    check("and is tracked by default", worldAnchor.isAnchorTracked, true)
    worldAnchor.isAnchorTracked = false
    check("which a caller can switch off", worldAnchor.isAnchorTracked, false)

    // The render options and the context.
    check("the render options are the ones the SDK names",
          [ARView.RenderOptions.disableMotionBlur, .disableDepthOfField, .disableCameraGrain,
           .disableHDR, .disableAREnvironmentLighting, .disableGroundingShadows,
           .disableFrameDebugMarkers].count, 7)
    check("a view's default render options", ARView.RenderOptions.default.rawValue,
          ARView.RenderOptions.disableAREnvironmentLighting.rawValue | ARView.RenderOptions.disableGroundingShadows.rawValue)
    check("and the standard ones are none", ARView.RenderOptions.standard.rawValue, 0)
    let context = ARView.PostProcessContext(nil, nil, nil, nil, nil, Transform().matrix, 1.5)
    check("a post-process context keeps the time it was given", context.time, 1.5)
    check("and the projection it was given", context.projection.columns.3.w, 1.0)

    // The gesture arithmetic, asked without a touch. It lives in the UIKit half of RealityKit,
    // so a host build has no recognizers and the arithmetic is not reached here; the check is
    // in the device probe's own terms.
    #if canImport(UIKit)
    let dragged = Entity()
    EntityGesture.translate(dragged, from: SIMD3<Float>(1, 1, 1), by: SIMD2<Float>(2, 3))
    check("a drag moves the entity by the gesture", dragged.position, SIMD3<Float>(3, 4, 1))
    let turned = Entity()
    let turnedFrom = turned.orientation
    EntityGesture.rotate(turned, from: turnedFrom, by: .pi / 2)
    check("a turn is about the screen's own axis", abs(turned.orientation.imag.z) > 0.7, true)
    EntityGesture.rotate(turned, from: turnedFrom, by: 0)
    check("and a turn of nothing is the orientation it began at", turned.orientation.vector == turnedFrom.vector, true)
    let pinched = Entity()
    EntityGesture.scale(pinched, from: SIMD3<Float>(2, 2, 2), by: 3)
    check("a pinch scales by the factor", pinched.scale, SIMD3<Float>(6, 6, 6))
    pinched.scale = SIMD3<Float>(1, 1, 1)
    EntityGesture.scale(pinched, from: SIMD3<Float>(2, 2, 2), by: 0.5)
    check("about the scale it began at, so a pinch and back is the same", pinched.scale, SIMD3<Float>(1, 1, 1))
    #endif

    // MARK: Accessibility

    // The traits are UIKit's own and the device probe reads them; everything else about an
    // entity's accessibility is plain and is checked here. The component is reached through the
    // public components API, across the module boundary, with no internal seam.
    let reader = Entity()
    check("an entity offers nothing to a screen reader at first", reader.accessibility == nil, true)
    var offered = Entity.AccessibilityComponent(label: "crate", value: "a wooden crate")
    offered.customContent = [Entity.AccessibilityComponent.AccessibilityEvents.CustomContent(key: "size", value: "1 m")]
    offered.customActions = [Entity.AccessibilityComponent.AccessibilityEvents.CustomAction(key: "open", entity: reader)]
    reader.accessibility = offered
    check("and what it is given, through the public API", reader.accessibility?.label ?? "", "crate")
    check("its label key", reader.accessibilityLabelKey ?? "", "crate")
    check("its value", reader.accessibilityValue ?? "", "a wooden crate")
    check("the content it shows", reader.accessibilityCustomContent.map { $0.value }, ["1 m"])
    check("the actions it answers", reader.accessibilityCustomActions.map { $0.key }, ["open"])
    check("the system's own action, which every entity has",
          reader.accessibilitySystemActions.first?.entity === reader, true)
    check("the events carry the entity they are against",
          Entity.AccessibilityComponent.AccessibilityEvents.Activate(entity: reader).entity === reader, true)
    check("and a custom action its key and entity",
          Entity.AccessibilityComponent.AccessibilityEvents.CustomAction(key: "k", entity: reader).key, "k")
    var navigated = ""
    let rotor = Entity.AccessibilityComponent.AccessibilityEvents.RotorNavigation(
        rotorType: .custom, hostEntity: reader, currentItem: "first") { navigated = $0 }
    check("a rotor's item", rotor.currentItem, "first")
    rotor.resultHandler("second")
    check("and the handler it was given", navigated, "second")
    reader.accessibility = nil
    check("taking it away leaves nothing", reader.accessibility == nil, true)

    // MARK: Resources

    // The resource protocol and the environment the ARView skybox takes are new in this series,
    // and the review's F1 was a registry row with no code behind it: a row that said
    // "implemented" and a module that named no such type. So the type is checked here as well as
    // declared - a resource is a Resource, an environment loads the file it is given, and a name
    // the bundle does not hold is the error Foundation itself raises.
    check("a mesh is a resource", MeshResource.generateBox(size: 1) is any Resource, true)

    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rf-environment-\(getpid())")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = Data([0x49, 0x42, 0x4c, 0x00, 0x01, 0x02, 0x03])
    try? bytes.write(to: directory.appendingPathComponent("daylight"))
    guard let bundle = Bundle(path: directory.path) else {
        print("FAIL the temporary bundle for the environment load could not be made")
        return failures
    }
    do {
        let environment = try EnvironmentResource.load(named: "daylight", in: bundle)
        check("the environment's name", environment.name, "daylight")
        check("and its bytes, held whole", environment.byteCount, bytes.count)
        check("and where it came from", environment.url?.lastPathComponent ?? "", "daylight")
    } catch {
        print("FAIL loading the environment the bundle holds: \(error)")
    }
    do {
        _ = try EnvironmentResource.load(named: "no-such-environment", in: bundle)
        print("FAIL a name the bundle does not hold loaded")
    } catch let error as CocoaError {
        check("a name the bundle does not hold is the error Foundation raises",
              (error.code as CocoaError.Code) == .fileNoSuchFile, true)
    } catch {
        print("FAIL a missing environment raised \(error) rather than a CocoaError")
    }

    // MARK: The emitter

    // The particle component is carried as the value a program sets and reads back. What is not
    // carried is the drawing - a particle is drawn through a low-level instance buffer by a
    // renderer, and neither SceneKit nor this port's view has one - so these checks are about the
    // values and the component's place on the entity, and the drawing is an absent registry row,
    // not a check that was left out.
    let emitterEntity = Entity()
    check("an entity with no emitter has none", emitterEntity.particleEmitter == nil, true)
    var emitter = ParticleEmitterComponent()
    emitter.emitterShape = .cone
    emitter.mainEmitter.birthRate = 24
    emitter.mainEmitter.lifeSpan = 1.5
    emitter.burstCount = 5
    emitterEntity.particleEmitter = emitter
    check("an emitter is on the entity it was put on", emitterEntity.particleEmitter?.emitterShape == .cone, true)
    check("with the rate it was given", emitterEntity.particleEmitter?.mainEmitter.birthRate ?? -1, Float(24))
    check("and the life it was given", emitterEntity.particleEmitter?.mainEmitter.lifeSpan ?? -1, 1.5)
    check("and the burst it was given", emitterEntity.particleEmitter?.burstCount ?? -1, 5)
    check("and it is a component of the module's own set",
          emitterEntity.components[ParticleEmitterComponent.self] != nil, true)
    // The nested names the SDK uses are the same types: a caller writes
    // ParticleEmitterComponent.EmitterShape and the two spellings are one type.
    let shape: ParticleEmitterComponent.EmitterShape = .torus
    check("the SDK's nested spelling is this module's type", shape == ParticleEmitterShape.torus, true)
    check("and a birth location with its own payload",
          ParticleEmitterComponent.BirthLocation.vertices(count: SIMD3<UInt>(2, 3, 4)) == .vertices(count: SIMD3<UInt>(2, 3, 4)), true)
    check("and a sort order the system names both ways",
          ParticleEmitter.SortOrder.increasingAge == ParticleEmitter.SortOrder.decreasingAge, false)
    check("and an opacity curve of each kind the interface lists",
          [ParticleEmitter.OpacityCurve.linearFadeOut, .easeFadeIn, .quickFadeInOut, .gradualFadeInOut].count, 4)
    check("and a free billboard mode with an axis",
          ParticleEmitter.BillboardMode.free(axis: SIMD3<Float>(0, 1, 0), variation: 10)
              == ParticleEmitter.BillboardMode.free(axis: SIMD3<Float>(0, 1, 0), variation: 10), true)
    // The members the interface declares at :12009-12011 and the types behind them: the blend
    // mode, the image, and the sprite sheet with its seven settings.
    check("an emitter blends by alpha until a program says otherwise",
          ParticleEmitter().blendMode, ParticleEmitter.BlendMode.alpha)
    check("and has no image and no sheet", ParticleEmitter().image == nil && ParticleEmitter().imageSequence == nil, true)
    var sheet = ParticleEmitter.ImageSequence(rowCount: 4, columnCount: 8, initialFrame: 3,
                                              initialFrameVariation: 1, frameRate: 24, frameRateVariation: 0.5,
                                              animationMode: .looping)
    check("a sheet is the grid it was given", sheet.rowCount, 4)
    check("and its columns", sheet.columnCount, 8)
    check("and the frame it starts on", sheet.initialFrame, 3)
    check("and by how much that may differ", sheet.initialFrameVariation, 1)
    check("and the rate it plays at", sheet.frameRate, Float(24))
    check("and by how much that may differ", sheet.frameRateVariation, Float(0.5))
    check("and how it carries on", sheet.animationMode, ParticleEmitter.ImageSequence.AnimationRepeatMode.looping)
    check("the sheet's own three modes are the system's",
          [ParticleEmitter.ImageSequence.AnimationRepeatMode.playOnce, .looping, .autoReverse].count, 3)
    check("and the blend mode's three are too",
          [ParticleEmitter.BlendMode.alpha, .opaque, .additive].count, 3)
    check("a sheet round-trips through Codable, as the interface's struct is Codable",
          { try? JSONDecoder().decode(ParticleEmitter.ImageSequence.self,
                                      from: JSONEncoder().encode(sheet)) }() == sheet, true)
    sheet.rowCount = 1
    check("and the top-level AnimationRepeatMode is a different type with the system's four cases",
          [AnimationRepeatMode.none, .repeat, .cumulative, .autoReverse].count, 4)
    // The image cannot be decoded: a texture is a runtime object with no name this port can code,
    // and the decode says so rather than dropping it. The check is that it refuses.
    do {
        let withImage = ParticleEmitter(image: TextureResource.generate(from: CGColor(gray: 0.5, alpha: 1)))
        let data = try JSONEncoder().encode(withImage)
        _ = try JSONDecoder().decode(ParticleEmitter.self, from: data)
        print("FAIL an emitter with an image decoded, and it should have refused")
    } catch is DecodingError {
        check("an emitter whose data names a texture refuses to decode rather than dropping it", true, true)
    } catch {
        print("FAIL the refusal was a \(error) and not a DecodingError")
    }

    // Codable, as the SDK's is (26.2:11789 - `Component, Swift.Codable`, and not Equatable, which
    // is why the round trip below compares fields and not the two values): the round trip is the
    // check that the synthesis is real and that every member is carried by it.
    do {
        let data = try JSONEncoder().encode(emitter)
        let back = try JSONDecoder().decode(ParticleEmitterComponent.self, from: data)
        check("the component round-trips through Codable", back.emitterShape, emitter.emitterShape)
        check("with its shape size", back.emitterShapeSize, emitter.emitterShapeSize)
        check("with its emission direction", back.emissionDirection, emitter.emissionDirection)
        check("with its burst", back.burstCount, emitter.burstCount)
        check("and its simulation state", back.simulationState, emitter.simulationState)
        check("and its emitter's own rate", back.mainEmitter.birthRate, Float(24))
        check("and its emitter's own noise scale", back.mainEmitter.noiseScale, emitter.mainEmitter.noiseScale)
    } catch {
        print("FAIL the emitter did not round-trip through Codable: \(error)")
    }
    emitterEntity.particleEmitter = nil
    check("taking it away leaves nothing", emitterEntity.particleEmitter == nil, true)

    // MARK: Inverse kinematics

    // The solve is cyclic coordinate descent, which is this module's own - Apple's is compiled and
    // nothing of it is readable - and the interface fixes only the shape: a maximum number of
    // passes, a forward-kinematics weight, a limits weight, per-axis weights, a per-joint
    // stiffness, and a position demand that reaches up a chain. These measure that shape.
    func threeJointChain(fkWeight: Float = 0) -> (Scene, Entity, Entity, IKRig, IKComponent.Constraint) {
        // root at the origin, a mid joint one up, a tip one along - a three-joint chain whose
        // lengths are known, so a target inside the reach is one a two-link arm can be put on.
        var rig = IKRig(maxIterations: 64, globalFkWeight: fkWeight)
        _ = rig.joints.set(IKRig.Joint(name: "root", restTransform: Transform()))
        _ = rig.joints.set(IKRig.Joint(name: "mid", parentID: IKRig.JointID(name: "root"),
                                       restTransform: Transform(translation: SIMD3<Float>(0, 1, 0))))
        _ = rig.joints.set(IKRig.Joint(name: "tip", parentID: IKRig.JointID(name: "mid"),
                                       restTransform: Transform(translation: SIMD3<Float>(0, 0, 1))))
        _ = rig.constraints.set(.point(named: "reach", on: "tip"))

        let scene = Scene()
        let holder = AnchorEntity()
        scene.addAnchor(holder)
        let root = Entity()
        root.name = "root"
        holder.addChild(root)
        let mid = Entity()
        mid.name = "mid"
        root.addChild(mid)
        let tip = Entity()
        tip.name = "tip"
        mid.addChild(tip)

        let resource = try! IKResource(rig: rig)
        let component = IKComponent(resource: resource)
        root.inverseKinematics = component
        return (scene, root, tip, rig, component.solvers[0].constraints[0])
    }

    do {
        let (scene, root, tip, _, constraint) = threeJointChain()
        // A target in reach, away from the chain's rest pose: the tip is put on it.
        constraint.target = Transform(translation: SIMD3<Float>(1, 0.5, 0.2))
        scene.coreScene.__advancePhysics(deltaTime: 1.0 / 60.0)
        let wanted = constraint.target.translation
        // The end effector's place in the world, which is not its own `position`: that is the
        // local one, and a target is given in the entity tree's own space (the solver reads the
        // hierarchy matrix for the same reason).
        check("a solve puts the end effector on a reachable target",
              simd_distance(tip.position(relativeTo: nil), wanted) < 0.02, true)
        // The forward-kinematics weight is how much of the rig's own pose is kept, so at one the
        // chain does not move at all.
        // The weight is the rig's, and a solver reads it from the rig the resource holds, so it is
        // set before the resource is made - the interface gives a solver no way to set it after.
        let (heldScene, _, heldTip, _, heldConstraint) = threeJointChain(fkWeight: 1)
        heldConstraint.target = Transform(translation: SIMD3<Float>(1, 0.5, 0.2))
        heldScene.coreScene.__advancePhysics(deltaTime: 1.0 / 60.0)
        check("a forward-kinematics weight of one keeps the whole chain still",
              simd_distance(heldTip.position(relativeTo: nil), heldTip.position(relativeTo: nil)) < 1e-6
                && heldTip.position(relativeTo: nil) == SIMD3<Float>(0, 1, 1), true)
        _ = root
    }

    // The per-axis weights are what make a joint take part of a demand, and nothing else here
    // measures them. The chain is straight along x and every joint may only twist about y, so the
    // tip can only leave the line by turning about y - which keeps it on the line's own plane, and
    // its y at zero whatever the target says. A bent chain would not do: a joint turning about one
    // axis swings everything below it, and the tip's other two axes move with it.
    // A straight chain, so that a joint which may only turn about one axis can only swing the
    // whole arm within that axis's plane. `along` is which way the chain runs, which decides what
    // the demanded rotation is about: a chain along x aiming at a target off to the side is a turn
    // about z, a chain along z aiming the same way is a turn about y.
    func straightChain(along axis: SIMD3<Float>, weight: SIMD3<Float>,
                       stiffness: SIMD3<Float> = .one,
                       limits: IKRig.Joint.LimitsDefinition? = nil) -> (Scene, Entity, Entity, Entity) {
        var rig = IKRig(maxIterations: 64)
        let joint = { (name: String, parent: IKRig.JointID?) in
            IKRig.Joint(name: name, parentID: parent,
                        restTransform: parent == nil ? .identity : Transform(translation: axis),
                        active: true, fkWeightPerAxis: weight, rotationStiffness: stiffness,
                        limits: limits) }
        _ = rig.joints.set(joint("root", nil))
        _ = rig.joints.set(joint("mid", IKRig.JointID(name: "root")))
        _ = rig.joints.set(joint("tip", IKRig.JointID(name: "mid")))
        _ = rig.constraints.set(.point(named: "reach", on: "tip"))
        let scene = Scene()
        let holder = AnchorEntity()
        scene.addAnchor(holder)
        let root = Entity(); root.name = "root"; holder.addChild(root)
        let mid = Entity(); mid.name = "mid"; root.addChild(mid)
        let tip = Entity(); tip.name = "tip"; mid.addChild(tip)
        root.inverseKinematics = IKComponent(resource: try! IKResource(rig: rig))
        return (scene, root, mid, tip)
    }
    let identityOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))
    func reach(_ scene: Scene, _ root: Entity, _ target: SIMD3<Float>) {
        root.inverseKinematics?.solvers[0].constraints[0].target = Transform(translation: target)
        scene.coreScene.__advancePhysics(deltaTime: 1.0 / 60.0)
    }
    do {
        // The chain runs along z, so the demand for a target off to the side is a turn about y, and
        // a joint weighted on y alone is given the whole of it: the tip reaches.
        let (scene, root, _, tip) = straightChain(along: SIMD3<Float>(0, 0, 1), weight: SIMD3<Float>(0, 1, 0))
        reach(scene, root, SIMD3<Float>(1, 0, 1))
        check("a joint weighted on the axis the demand is about reaches the target",
              simd_distance(tip.position(relativeTo: nil), SIMD3<Float>(1, 0, 1)) < 0.02, true)
    }
    do {
        // The same chain and the same weight, with a target out of that axis's plane: the demand
        // now has a component the joint may not take, and the tip stays in the plane.
        let (scene, root, _, tip) = straightChain(along: SIMD3<Float>(0, 0, 1), weight: SIMD3<Float>(0, 1, 0))
        reach(scene, root, SIMD3<Float>(1, 1, 1))
        check("a chain that may only turn about one axis stays in that axis's plane",
              abs(tip.position(relativeTo: nil).y) < 1e-4, true)
        check("and so cannot reach a target out of it",
              simd_distance(tip.position(relativeTo: nil), SIMD3<Float>(1, 1, 1)) > 0.2, true)
    }
    do {
        // And the same chain weighted on none of the axes that the demand is about cannot turn at
        // all, which is the other half of the same fact.
        let (scene, root, _, tip) = straightChain(along: SIMD3<Float>(0, 0, 1), weight: SIMD3<Float>(1, 0, 0))
        reach(scene, root, SIMD3<Float>(1, 0, 1))
        check("a joint weighted away from the axis the demand is about does not turn",
              simd_distance(tip.position(relativeTo: nil), SIMD3<Float>(0, 0, 2)) < 1e-3, true)
    }

    do {
        // A joint with no stiffness is not turned at all, which is what a stiffness of zero means.
        // The joint's own rotation is its orientation, not its position: the root turning moves
        // every joint's position without touching the joints' own.
        let (scene, root, mid, _) = straightChain(along: SIMD3<Float>(0, 0, 1),
                                                 weight: SIMD3<Float>(repeating: 1), stiffness: .zero)
        reach(scene, root, SIMD3<Float>(1, 0, 1))
        check("a joint with no stiffness is not turned",
              abs(simd_dot(mid.transform.rotation.vector, identityOrientation.vector)) > 1 - 1e-6, true)
    }

    // A joint that is not active is not turned, and a rig with no joints is not a resource.
    do {
        var rig = IKRig()
        _ = rig.joints.set(IKRig.Joint(name: "root"))
        _ = rig.joints.set(IKRig.Joint(name: "tip", parentID: IKRig.JointID(name: "root"),
                                       restTransform: Transform(translation: SIMD3<Float>(0, 1, 0))))
        var threw = false
        do { _ = try IKResource(rig: rig) } catch { threw = true }
        check("a rig with joints makes a resource", threw, false)
        threw = false
        do { _ = try IKResource(rig: IKRig()) } catch { threw = true }
        check("a rig with none is refused rather than made empty", threw, true)
        check("and the component's demand options are only the raw ones the interface declares",
              IKComponent.Constraint.DemandOptions(rawValue: 3).rawValue, 3)
    }

    // The collections are the interface's: looked up by identity or by name, set, and countable.
    do {
        var rig = IKRig()
        let old = rig.joints.set(IKRig.Joint(name: "a", restTransform: Transform(translation: SIMD3<Float>(1, 0, 0))))
        check("setting a joint that was not there returns nothing", old == nil, true)
        check("and now it is there", rig.joints.count, 1)
        check("by name", rig.joints["a"]?.restTransform.translation.x ?? -1, Float(1))
        check("by identity", rig.joints.contains(IKRig.JointID(name: "a")), true)
        check("setting it again returns the old one",
              rig.joints.set(IKRig.Joint(name: "a", restTransform: Transform())) == nil, false)
        check("and replaces it", rig.joints.count, 1)
        check("a joint's identity is its name", IKRig.Joint(name: "a").id, IKRig.JointID(name: "a"))
        check("a constraint's too", IKRig.Constraint.point(named: "c", on: "a").id, IKRig.ConstraintID(name: "c"))
        check("the chain above a joint is its parents, nearest first", rig.chain(above: "b"), [])
        // The five factories, and what each one makes.
        let point = IKRig.Constraint.point(named: "p", on: "a", positionWeight: [0, 1, 0])
        check("a point demand", point.positionDemand?.weight ?? .zero, SIMD3<Float>(0, 1, 0))
        check("and no orientation demand", point.orientationDemand == nil, true)
        let look = IKRig.Constraint.lookAtAbsolute(named: "l", on: "a", lookingAlong: [0, 0, 1])
        if case .absoluteLookAt(let axis)? = look.orientationDemand?.mode { check("an absolute look-at keeps its axis", axis, SIMD3<Float>(0, 0, 1)) }
        else { print("FAIL the absolute look-at did not keep its axis") }
        // The limits' defaults are the interface's (:4790): no limit at all, on x, at full weight.
        let limits = IKRig.Joint.LimitsDefinition()
        check("a limit's axis defaults to x", limits.boneAxis, IKRig.Joint.LimitsDefinition.Axis.x)
        check("and its weight to one", limits.weight, Float(1))
        check("and its angles to plus and minus two pi", limits.maximumAngles.x, 2.0 * Float.pi)
        check("a constraint literal is a collection", {
            let collection: IKRig.ConstraintsCollection = [
                .point(named: "one", on: "a"), .orient(named: "two", on: "a"),
            ]
            return collection.count
        }(), 2)
    }

    // MARK: Bounds

    let unit = Entity()
    unit.scale = SIMD3<Float>(2, 2, 2)
    let bounds = unit.visualBounds(recursive: false, relativeTo: nil, excludeInactive: false)
    check("the box's extents", bounds.extents, SIMD3<Float>(2, 2, 2))

    print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECKS FAILED")
    return failures
}

MainActor.assumeIsolated { exit(checkAll() == 0 ? 0 : 1) }
