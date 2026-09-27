// The gestures an entity answers: it can be moved, turned and scaled by a touch.
//
// The SDK's own recognizers are `UIGestureRecognizer` subclasses that ask the renderer where
// the touch landed; these are the same three, driving the entity's own transform, so that a
// program's answer does not depend on a renderer being present to hit-test the touch.

#if canImport(UIKit)
import UIKit
import simd
import RealityFoundation

/// A gesture that acts on one entity.
@MainActor
public protocol EntityGestureRecognizer: AnyObject {
    /// The entity the gesture moves.
    var entity: Entity { get }
    /// The recognizer itself, which a caller adds to a view and takes away again.
    var recognizer: UIGestureRecognizer { get }
}

/// Moves an entity under the touch.
@MainActor
open class EntityTranslationGestureRecognizer: UIPanGestureRecognizer, EntityGestureRecognizer {
    public let entity: Entity
    /// Where the entity was when the gesture began, which every change is measured from.
    public private(set) var initialPosition: SIMD3<Float>

    public init(entity: any HasCollision) {
        self.entity = (entity as? Entity) ?? AnchorEntity()
        initialPosition = self.entity.position
        super.init(target: nil, action: nil)
    }

    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialPosition = entity.position
        translation = .zero
    }

    /// How far the entity has been dragged, in the view's own units.
    public private(set) var translation: CGPoint = .zero

    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        translation = touch.location(in: nil)
        entity.position = initialPosition + SIMD3<Float>(x: Float(translation.x),
                                                          y: Float(translation.y),
                                                          z: 0)
    }

    public var recognizer: UIGestureRecognizer { self }
}

/// Turns an entity under a two-finger rotation.
@MainActor
open class EntityRotationGestureRecognizer: UIRotationGestureRecognizer, EntityGestureRecognizer {
    public let entity: Entity
    /// The orientation the entity had when the gesture began.
    public private(set) var initialOrientation: simd_quatf

    public init(entity: any HasCollision) {
        self.entity = (entity as? Entity) ?? AnchorEntity()
        initialOrientation = self.entity.orientation
        super.init(target: nil, action: nil)
    }

    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialOrientation = entity.orientation
    }

    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // The recognizer's own rotation is about z, which is the screen's axis; the entity is
        // turned about the axis the gesture is read on, which is the camera's.
        entity.orientation = simd_quatf(angle: Float(rotation), axis: SIMD3<Float>(0, 0, 1)) * initialOrientation
    }

    public var recognizer: UIGestureRecognizer { self }
}

/// Scales an entity under a pinch.
@MainActor
open class EntityScaleGestureRecognizer: UIPinchGestureRecognizer, EntityGestureRecognizer {
    public let entity: Entity
    /// The scale the entity had when the gesture began.
    public private(set) var initialScale: SIMD3<Float>

    public init(entity: any HasCollision) {
        self.entity = (entity as? Entity) ?? AnchorEntity()
        initialScale = self.entity.scale
        super.init(target: nil, action: nil)
    }

    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialScale = entity.scale
    }

    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let factor = Float(scale)
        entity.scale = initialScale * SIMD3<Float>(repeating: factor)
    }

    public var recognizer: UIGestureRecognizer { self }
}
#endif
