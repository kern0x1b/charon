// MARK: - Particles
//
// The emitter component: how many particles, how fast, which way, how long they live, and what
// the renderer would do with them.
//
// Every declaration and every member below is read from the SDK's own interface,
// `iPhoneOS26.2.sdk/System/Library/Frameworks/RealityFoundation.framework/Modules/
// RealityFoundation.swiftmodule/arm64e-apple-ios.swiftinterface:11789-11960`: the component and
// its nested enums, the `ParticleEmitter` it holds and that emitter's own members. The names,
// the cases and the types are the system's.
//
// What is not here is the drawing, and the registry says so where a reader will look: a particle
// is drawn by RealityKit's renderer through a low-level instance buffer, and this port's view is
// an SCNView over the SceneKit bridge, and no release this old has a particle renderer in either.
// So the component is carried whole as the value a program sets and reads back - the numbers, the
// cases, the emitter's own curve and noise and attraction settings - and nothing pretends to
// spawn a particle. `Entity.components[ParticleEmitterComponent.self]` is where a program finds it,
// and the simulation step is where a renderer would be called.

import simd
import Foundation

/// What shape the particles are born in.
@frozen public enum ParticleEmitterShape: Codable, Equatable, Hashable {
    case point
    case plane
    case box
    case sphere
    case cone
    case cylinder
    case torus
}

/// Where in the shape a particle is born.
@frozen public enum ParticleBirthLocation: Codable, Equatable, Hashable {
    /// On the surface of the shape.
    case surface
    /// Anywhere inside it.
    case volume
    /// At a point on the surface, chosen per axis - the system's own `SIMD3<UInt>`, which is the
    /// resolution of the shape's own box and is `UInt` because a count of vertices cannot be
    /// negative.
    case vertices(count: SIMD3<UInt>)
}

/// The frame a particle's birth direction is taken in.
@frozen public enum ParticleBirthDirection: Codable, Equatable, Hashable {
    case world
    case local
    case normal
}

/// When a particle is born.
@frozen public enum ParticleSpawnOccasion: Codable, Equatable, Hashable {
    case onBirth
    case onUpdate
    case onDeath
}

/// The frame the particles are simulated in.
@frozen public enum ParticleSimulationSpace: Codable {
    case local
    case global
}

/// Whether the emitter's simulation runs.
@frozen public enum ParticleSimulationState: Codable {
    case play
    case pause
    case stop
}

/// One emitter's own settings: how it is born, how it moves, how it fades.
@frozen public struct ParticleEmitter: Codable, Equatable {
    /// How the particle is turned to face the camera.
    public enum BillboardMode: Codable, Equatable, Hashable {
        case billboard
        case billboardYAligned
        /// Faced freely about an axis, with a variation in degrees.
        case free(axis: SIMD3<Float>, variation: Float)
    }

    /// How a particle's opacity runs over its life: :11907-11914, the linear, the eased, the
    /// gradual and the quick shapes, and constant for one that does not change.
    public enum OpacityCurve: Codable, Equatable, Hashable {
        case linearFadeOut
        case linearFadeIn
        case gradualFadeInOut
        case quickFadeInOut
        case easeFadeIn
        case easeFadeOut
        case constant
    }

    /// How particles are ordered against each other: :11923-11929, by depth, by id or by age,
    /// each in both directions, and unsorted. The directions are the system's names, not
    /// "near to far": increasing is the order the renderer walks.
    public enum SortOrder: Codable, Equatable, Hashable {
        case increasingDepth
        case decreasingDepth
        case increasingID
        case decreasingID
        case increasingAge
        case decreasingAge
        case unsorted
    }

    /// How many particles are born in a second, and by how much that may differ.
    public var birthRate: Float
    public var birthRateVariation: Float
    /// How fast a particle loses speed, per second.
    public var dampingFactor: Float
    /// What the particles are pushed by, in the emitter's own frame.
    public var acceleration: SIMD3<Float>
    /// How far from the emission direction a particle may start, in degrees.
    public var spreadingAngle: Float
    public var size: Float
    public var sizeVariation: Float
    public var billboardMode: BillboardMode
    public var mass: Float
    public var massVariation: Float
    /// How long a particle lives, in seconds, and by how much that may differ.
    public var lifeSpan: Double
    public var lifeSpanVariation: Double
    /// How fast the particle turns, in degrees per second, and by how much that may differ.
    public var angle: Float
    public var angleVariation: Float
    public var angularSpeed: Float
    public var angularSpeedVariation: Float
    public var opacityCurve: OpacityCurve
    /// What the particle's size has become by the end of its life, and the power of the curve
    /// that gets it there.
    public var sizeMultiplierAtEndOfLifespan: Float
    public var sizeMultiplierAtEndOfLifespanPower: Float
    /// The power of the curve its colour runs.
    public var colorEvolutionPower: Float
    /// How far the noise field moves a particle, how large its features are, and how fast they
    /// change.
    public var noiseStrength: Float
    public var noiseScale: Float
    public var noiseAnimationSpeed: Float
    /// How hard the emitter pulls its particles towards a point, and where that point is.
    public var attractionStrength: Float
    public var attractionCenter: SIMD3<Float>
    /// How hard the emitter swirls them, and about which axis.
    public var vortexStrength: Float
    public var vortexDirection: SIMD3<Float>
    public var isLightingEnabled: Bool
    /// How far a fast particle is stretched along its own direction.
    public var stretchFactor: Float
    public var sortOrder: SortOrder

    public init(birthRate: Float = 1, birthRateVariation: Float = 0, dampingFactor: Float = 0,
                acceleration: SIMD3<Float> = .zero, spreadingAngle: Float = 0, size: Float = 0.05,
                sizeVariation: Float = 0, billboardMode: BillboardMode = .billboard,
                mass: Float = 1, massVariation: Float = 0, lifeSpan: Double = 1,
                lifeSpanVariation: Double = 0, angle: Float = 0, angleVariation: Float = 0,
                angularSpeed: Float = 0, angularSpeedVariation: Float = 0,
                opacityCurve: OpacityCurve = .linearFadeOut,
                sizeMultiplierAtEndOfLifespan: Float = 1, sizeMultiplierAtEndOfLifespanPower: Float = 1,
                colorEvolutionPower: Float = 1, noiseStrength: Float = 0, noiseScale: Float = 1,
                noiseAnimationSpeed: Float = 0, attractionStrength: Float = 0,
                attractionCenter: SIMD3<Float> = .zero, vortexStrength: Float = 0,
                vortexDirection: SIMD3<Float> = .zero, isLightingEnabled: Bool = false,
                stretchFactor: Float = 0, sortOrder: SortOrder = .unsorted) {
        self.birthRate = birthRate
        self.birthRateVariation = birthRateVariation
        self.dampingFactor = dampingFactor
        self.acceleration = acceleration
        self.spreadingAngle = spreadingAngle
        self.size = size
        self.sizeVariation = sizeVariation
        self.billboardMode = billboardMode
        self.mass = mass
        self.massVariation = massVariation
        self.lifeSpan = lifeSpan
        self.lifeSpanVariation = lifeSpanVariation
        self.angle = angle
        self.angleVariation = angleVariation
        self.angularSpeed = angularSpeed
        self.angularSpeedVariation = angularSpeedVariation
        self.opacityCurve = opacityCurve
        self.sizeMultiplierAtEndOfLifespan = sizeMultiplierAtEndOfLifespan
        self.sizeMultiplierAtEndOfLifespanPower = sizeMultiplierAtEndOfLifespanPower
        self.colorEvolutionPower = colorEvolutionPower
        self.noiseStrength = noiseStrength
        self.noiseScale = noiseScale
        self.noiseAnimationSpeed = noiseAnimationSpeed
        self.attractionStrength = attractionStrength
        self.attractionCenter = attractionCenter
        self.vortexStrength = vortexStrength
        self.vortexDirection = vortexDirection
        self.isLightingEnabled = isLightingEnabled
        self.stretchFactor = stretchFactor
        self.sortOrder = sortOrder
    }
}

/// An emitter on an entity: the particle system's settings, as a component the entity carries.
///
/// The names are the system's own and the nesting is the system's own, with one departure the
/// registry records: the SDK nests `EmitterShape`, `BirthLocation`, `BirthDirection`,
/// `SpawnOccasion`, `SimulationSpace`, `SimulationState` and `ParticleEmitter` *inside* this
/// struct (`ParticleEmitterComponent.EmitterShape` and so on), and they are declared here at file
/// scope under their own names. The reason is mechanical and it is the same one the module's
/// other components meet: a nested type inside a `@frozen` struct that conforms to `Component`
/// cannot be named by a program that spells the component through the protocol, and this
/// component's own members are typed with all of them. `ParticleEmitterComponent.EmitterShape` is
/// what a caller writes, and it is a typealias to the same type.
@frozen public struct ParticleEmitterComponent: Component, Codable {
    public typealias EmitterShape = ParticleEmitterShape
    public typealias BirthLocation = ParticleBirthLocation
    public typealias BirthDirection = ParticleBirthDirection
    public typealias SpawnOccasion = ParticleSpawnOccasion
    public typealias SimulationSpace = ParticleSimulationSpace
    public typealias SimulationState = ParticleSimulationState
    public typealias ParticleEmitter = RealityFoundation.ParticleEmitter

    public var emitterShape: EmitterShape
    public var birthLocation: BirthLocation
    public var birthDirection: BirthDirection
    /// The size of the shape the particles are born in.
    public var emitterShapeSize: SIMD3<Float>
    public var speed: Float
    public var speedVariation: Float
    /// The direction the particles start in, in the emitter's own frame.
    public var emissionDirection: SIMD3<Float>
    /// How far from the emission direction a particle may start.
    public var radialAmount: Float
    /// The hole in the middle of a torus emitter.
    public var torusInnerRadius: Float
    public var spawnOccasion: SpawnOccasion
    /// How much of its own velocity a particle starts with.
    public var spawnVelocityFactor: Float
    /// How far from the emission direction a particle starts, and by how much that may differ.
    public var spawnSpreadFactor: Float
    public var spawnSpreadFactorVariation: Float
    public var spawnInheritsParentColor: Bool
    public var simulationState: SimulationState
    public var particlesInheritTransform: Bool
    /// The frame the force fields the particles read are in.
    public var fieldSimulationSpace: SimulationSpace
    public var isEmitting: Bool
    /// How many particles a burst makes, and by how much that may differ.
    public var burstCount: Int
    public var burstCountVariation: Int
    /// The emitter the entity always has.
    public var mainEmitter: ParticleEmitter
    /// The emitter that only exists while particles are alive, which a renderer writes. It is
    /// absent here: it holds a low-level instance buffer, and there is no particle renderer in
    /// this port to write one - the registry carries the row with that reason.
    public var spawnedEmitter: ParticleEmitter?

    public init(emitterShape: EmitterShape = .sphere, birthLocation: BirthLocation = .volume,
                birthDirection: BirthDirection = .normal,
                emitterShapeSize: SIMD3<Float> = .one, speed: Float = 1, speedVariation: Float = 0,
                emissionDirection: SIMD3<Float> = .zero, radialAmount: Float = 0,
                torusInnerRadius: Float = 0, spawnOccasion: SpawnOccasion = .onUpdate,
                spawnVelocityFactor: Float = 0, spawnSpreadFactor: Float = 0,
                spawnSpreadFactorVariation: Float = 0, spawnInheritsParentColor: Bool = false,
                simulationState: SimulationState = .play, particlesInheritTransform: Bool = false,
                fieldSimulationSpace: SimulationSpace = .local, isEmitting: Bool = true,
                burstCount: Int = 0, burstCountVariation: Int = 0,
                mainEmitter: ParticleEmitter = ParticleEmitter(), spawnedEmitter: ParticleEmitter? = nil) {
        self.emitterShape = emitterShape
        self.birthLocation = birthLocation
        self.birthDirection = birthDirection
        self.emitterShapeSize = emitterShapeSize
        self.speed = speed
        self.speedVariation = speedVariation
        self.emissionDirection = emissionDirection
        self.radialAmount = radialAmount
        self.torusInnerRadius = torusInnerRadius
        self.spawnOccasion = spawnOccasion
        self.spawnVelocityFactor = spawnVelocityFactor
        self.spawnSpreadFactor = spawnSpreadFactor
        self.spawnSpreadFactorVariation = spawnSpreadFactorVariation
        self.spawnInheritsParentColor = spawnInheritsParentColor
        self.simulationState = simulationState
        self.particlesInheritTransform = particlesInheritTransform
        self.fieldSimulationSpace = fieldSimulationSpace
        self.isEmitting = isEmitting
        self.burstCount = burstCount
        self.burstCountVariation = burstCountVariation
        self.mainEmitter = mainEmitter
        self.spawnedEmitter = spawnedEmitter
    }
}

extension Entity {
    /// The emitter on this entity, or nil when it has none.
    public var particleEmitter: ParticleEmitterComponent? {
        get { components[ParticleEmitterComponent.self] }
        set {
            if let newValue {
                components.set(newValue)
            } else {
                components.remove(ParticleEmitterComponent.self)
            }
        }
    }
}
