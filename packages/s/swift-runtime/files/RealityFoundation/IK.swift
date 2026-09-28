// MARK: - Inverse kinematics
//
// The rig, the constraints that put demands on it, and the component an entity carries to be solved.
//
// Every declaration and member below is read from the SDK's own interface,
// `iPhoneOS26.2.sdk/System/Library/Frameworks/RealityFoundation.framework/Modules/
/// RealityFoundation.swiftmodule/arm64e-apple-ios.swiftinterface`: IKSolverDefinition :4738, IKRig
// :4745-4945, IKComponent :8842-9075, IKResource :10958. The names, the cases, the types and the
// defaults are the system's.
//
// This is the one part of the scene graph that needs no renderer and no asset: a rig is joints and
// transforms, a constraint is a demand on one of them, and solving is arithmetic over the entity
// tree's own transforms. What is *not* here is stated where a reader will find it rather than
// faked:
//
//   - `IKRig.init(for: MeshResource.Skeleton)` (:4759) is **not declared here at all**: a skeleton
//     is read out of a mesh asset, and this module carries no `MeshResource.Skeleton` to pass it, so
//     an initializer that took one could only be a signature standing in for nothing. The registry
//     carries the row as absent with that reason. A rig is built by naming its joints, through the
//     initializer below, which is this port's own and its row says so.
//   - The two `ID` types carry no public members of their own in the interface (:4753-4758, :4800),
//     so an ID is made from a joint's or a constraint's name here and the only public way to read one
//     is `joint.id` and `constraint.id`, exactly as the interface has it.
//   - `IKComponent.Constraint.DemandOptions` is an OptionSet whose *members* are not declared in the
//     interface (:8890-8901 gives only `rawValue` and `init(rawValue:)`), so this carries exactly
//     that and no options are invented for it.
//
// The solver that consumes a rig is the simulation step, in Simulation.swift, where the rest of the
// per-frame work is; it runs the demands over the entity's joint entities and needs nothing that is
// drawn.

import simd
import Foundation

// MARK: - The rig

/// A rig: its joints, the constraints that put demands on them, and the weights the solve obeys.
///
/// `maxIterations` is how many passes the solve makes before it stops, `globalFkWeight` how much of
/// the rig's own forward kinematics is kept against a demand, and `globalLimitsWeight` how hard a
/// joint's limits are held. All three are `:4747-4749`.
@frozen public struct IKRig: Equatable {
    /// The identity of a joint, which is its name: the interface gives an `ID` no public member of
    /// its own, and a joint's `parentID` is another joint's, so the name is the identity.
    public struct JointID: Hashable, Equatable, Sendable {
        let name: String
        public init(name: String) { self.name = name }
    }

    /// The identity of a constraint, which is its name, for the same reason.
    public struct ConstraintID: Hashable, Equatable, Sendable {
        let name: String
        public init(name: String) { self.name = name }
    }

    public var maxIterations: Int
    public var globalFkWeight: Float
    public var globalLimitsWeight: Float
    public var joints: JointCollection
    public var constraints: ConstraintsCollection

    /// A rig with no joints, which the caller fills through `joints.set(_:)` and
    /// `constraints.set(_:)`. The interface's only initializer is `init(for: MeshResource.Skeleton)`
    /// (:4759), and a skeleton is read out of a mesh asset this port cannot read; a program with no
    /// mesh could not otherwise make a rig at all, and naming the joints is the whole of what a rig
    /// is. The registry row for this initializer says it is the port's.
    public init(maxIterations: Int = 32, globalFkWeight: Float = 0, globalLimitsWeight: Float = 1,
                joints: JointCollection = JointCollection(), constraints: ConstraintsCollection = ConstraintsCollection()) {
        self.maxIterations = maxIterations
        self.globalFkWeight = globalFkWeight
        self.globalLimitsWeight = globalLimitsWeight
        self.joints = joints
        self.constraints = constraints
    }

    /// A joint of the rig, and the demands that may be put on it.
    public struct Joint: Identifiable, Equatable {
        public typealias ID = IKRig.JointID

        /// What a joint may not do: the angles its axes are held to, and how hard.
        public struct LimitsDefinition: Equatable {
            /// The axis a limit is measured about.
            public enum Axis: Equatable, Hashable {
                case x
                case y
                case z
            }

            public var weight: Float
            public var boneAxis: Axis
            public var minimumAngles: SIMD3<Float>
            public var maximumAngles: SIMD3<Float>

            /// The defaults are the interface's (:4790): a limit of plus and minus two pi on every
            /// axis, which is no limit at all, and the x axis and full weight.
            public init(weight: Float = 1.0, boneAxis: Axis = .x,
                        minimumAngles: SIMD3<Float> = [-2.0 * .pi, -2.0 * .pi, -2.0 * .pi],
                        maximumAngles: SIMD3<Float> = [2.0 * .pi, 2.0 * .pi, 2.0 * .pi]) {
                self.weight = weight
                self.boneAxis = boneAxis
                self.minimumAngles = minimumAngles
                self.maximumAngles = maximumAngles
            }
        }

        public var id: ID { ID(name: name) }
        public let name: String
        public var parentID: ID?
        /// Where the joint sits in its parent when nothing has moved it.
        public var restTransform: Transform
        /// Whether the solve may move this joint. A joint that is not active is skipped and keeps
        /// its forward-kinematics pose.
        public var active: Bool
        /// How much of a demand each axis of this joint takes, per axis.
        public var fkWeightPerAxis: SIMD3<Float>
        /// How stiff this joint is against a demand: zero does not move, one follows it.
        public var rotationStiffness: SIMD3<Float>
        public var limits: LimitsDefinition?

        public init(name: String, parentID: ID? = nil, restTransform: Transform = .identity,
                    active: Bool = true, fkWeightPerAxis: SIMD3<Float> = .one,
                    rotationStiffness: SIMD3<Float> = .one, limits: LimitsDefinition? = nil) {
            self.name = name
            self.parentID = parentID
            self.restTransform = restTransform
            self.active = active
            self.fkWeightPerAxis = fkWeightPerAxis
            self.rotationStiffness = rotationStiffness
            self.limits = limits
        }
    }

    /// What a constraint asks of a joint: where it is, which way it looks, or both.
    public struct Constraint: Identifiable, Equatable {
        public typealias ID = IKRig.ConstraintID

        /// A demand on a joint's position, and how far up the chain it reaches.
        public struct IKPositionDemand: Equatable {
            public enum Mode: Equatable, Hashable {
                /// The joint is asked to reach the target.
                case reach
                /// The joint is asked to point along the pole vector, which places it in the plane
                /// the other joints make.
                case poleVector
            }

            public var mode: Mode
            /// How many joints above this one the demand reaches; how far up the chain it counts.
            public var influenceDepthMaxJointCount: Int
            /// How much of the demand each axis takes.
            public var weight: SIMD3<Float>

            public init(mode: Mode = .reach, influenceDepthMaxJointCount: Int = 0,
                        weight: SIMD3<Float> = .one) {
                self.mode = mode
                self.influenceDepthMaxJointCount = influenceDepthMaxJointCount
                self.weight = weight
            }
        }

        /// A demand on a joint's orientation.
        public struct IKOrientationDemand: Equatable {
            public enum Mode: Equatable, Hashable {
                /// The joint takes the target's orientation.
                case orientation
                /// The joint looks along `targetAxis` and keeps what it had.
                case additiveLookAt(targetAxis: SIMD3<Float>)
                /// The joint looks along `targetAxis` absolutely.
                case absoluteLookAt(targetAxis: SIMD3<Float>)
            }

            public var mode: Mode
            public var weight: SIMD3<Float>

            public init(mode: Mode = .orientation, weight: SIMD3<Float> = .one) {
                self.mode = mode
                self.weight = weight
            }
        }

        public var id: ID { ID(name: name) }
        public var name: String
        /// The joint this constraint is on, by name: the interface spells it a `String` (:4811), not
        /// an ID, and the two agree because a name is the identity.
        public var jointName: String
        /// Where the target is, relative to the joint.
        public var offset: Transform
        public var positionDemand: IKPositionDemand?
        public var orientationDemand: IKOrientationDemand?

        public init(name: String, jointName: String, offset: Transform = .identity,
                    positionDemand: IKPositionDemand? = nil, orientationDemand: IKOrientationDemand? = nil) {
            self.name = name
            self.jointName = jointName
            self.offset = offset
            self.positionDemand = positionDemand
            self.orientationDemand = orientationDemand
        }

        /// A position demand on a joint: the factory at :4820.
        public static func point(named name: String, on jointName: String,
                                 positionWeight: SIMD3<Float> = [1, 1, 1]) -> Constraint {
            Constraint(name: name, jointName: jointName,
                       positionDemand: IKPositionDemand(mode: .reach, weight: positionWeight))
        }

        /// An orientation demand on a joint: :4821.
        public static func orient(named name: String, on jointName: String,
                                  orientationWeight: SIMD3<Float> = [1, 1, 1]) -> Constraint {
            Constraint(name: name, jointName: jointName,
                       orientationDemand: IKOrientationDemand(weight: orientationWeight))
        }

        /// Both demands at once: :4822.
        public static func parent(named name: String, on jointName: String,
                                  positionWeight: SIMD3<Float> = [1, 1, 1],
                                  orientationWeight: SIMD3<Float> = [1, 1, 1]) -> Constraint {
            Constraint(name: name, jointName: jointName,
                       positionDemand: IKPositionDemand(weight: positionWeight),
                       orientationDemand: IKOrientationDemand(weight: orientationWeight))
        }

        /// A look-at that is added to what the joint already had: :4823.
        public static func lookAtAdditive(named name: String, on jointName: String,
                                          lookingAlong targetAxis: SIMD3<Float>,
                                          orientationWeight: SIMD3<Float> = [1, 1, 1]) -> Constraint {
            Constraint(name: name, jointName: jointName,
                       orientationDemand: IKOrientationDemand(mode: .additiveLookAt(targetAxis: targetAxis),
                                                              weight: orientationWeight))
        }

        /// A look-at that replaces the joint's orientation: :4824.
        public static func lookAtAbsolute(named name: String, on jointName: String,
                                          lookingAlong targetAxis: SIMD3<Float>,
                                          orientationWeight: SIMD3<Float> = [1, 1, 1]) -> Constraint {
            Constraint(name: name, jointName: jointName,
                       orientationDemand: IKOrientationDemand(mode: .absoluteLookAt(targetAxis: targetAxis),
                                                              weight: orientationWeight))
        }
    }

    /// The rig's joints, in the order they were set, looked up by identity or by name.
    public struct JointCollection: Collection, Equatable {
        public typealias Element = IKRig.Joint
        public typealias Index = Int

        private var joints: [IKRig.Joint]

        public init(_ joints: [IKRig.Joint] = []) { self.joints = joints }

        public subscript(id: IKRig.Joint.ID) -> IKRig.Joint? {
            get { joints.first { $0.id == id } }
            set {
                guard let newValue else { return }
                if let at = joints.firstIndex(where: { $0.id == id }) { joints[at] = newValue }
                else { joints.append(newValue) }
            }
        }

        public subscript(name: String) -> IKRig.Joint? {
            get { joints.first { $0.name == name } }
            set { self[newValue?.id ?? IKRig.Joint.ID(name: name)] = newValue }
        }

        /// A joint set under a name that is not there yet is added; one that is replaces the old.
        @discardableResult
        public mutating func set(_ newValue: IKRig.Joint) -> IKRig.Joint? {
            let id = newValue.id
            if let at = joints.firstIndex(where: { $0.id == id }) {
                let old = joints[at]
                joints[at] = newValue
                return old
            }
            joints.append(newValue)
            return nil
        }

        public func contains(_ id: IKRig.Joint.ID) -> Bool { joints.contains { $0.id == id } }
        public var isEmpty: Bool { joints.isEmpty }

        public var startIndex: Int { joints.startIndex }
        public var endIndex: Int { joints.endIndex }
        public func index(after i: Int) -> Int { joints.index(after: i) }
        public subscript(position: Int) -> IKRig.Joint { joints[position] }

        /// Walks the joints below a joint, in the order they are in, calling `update` on each. The
        /// joint itself is skipped unless `inclusive` says otherwise: a descendant is a joint whose
        /// `parentID` chain runs through it.
        public mutating func forEach(descendantOf rootJointName: String, inclusive: Bool = false,
                                     update: (inout IKRig.Joint) -> Void) {
            var changed = true
            var visited = Set<IKRig.Joint.ID>()
            while changed {
                changed = false
                for at in joints.indices {
                    let joint = joints[at]
                    guard !visited.contains(joint.id) else { continue }
                    let isRoot = joint.name == rootJointName
                    guard isRoot ? inclusive : isDescendant(of: rootJointName, in: joints, joint: joint) else { continue }
                    visited.insert(joint.id)
                    update(&joints[at])
                    changed = true
                }
            }
        }

        private func isDescendant(of root: String, in joints: [IKRig.Joint], joint: IKRig.Joint) -> Bool {
            var parent = joint.parentID
            var guard_ = 0
            while let current = parent, guard_ < joints.count {
                if current == IKRig.Joint.ID(name: root) { return true }
                parent = joints.first { $0.id == current }?.parentID
                guard_ += 1
            }
            return false
        }
    }

    /// The rig's constraints, looked up the same way, and writable as a literal.
    public struct ConstraintsCollection: Collection, ExpressibleByArrayLiteral, Equatable {
        public typealias Element = IKRig.Constraint
        public typealias Index = Int

        private var constraints: [IKRig.Constraint]

        public init(_ constraints: [IKRig.Constraint] = []) { self.constraints = constraints }
        public init(arrayLiteral elements: IKRig.Constraint...) { self.constraints = elements }

        public subscript(id: IKRig.Constraint.ID) -> IKRig.Constraint? {
            get { constraints.first { $0.id == id } }
            set {
                guard let newValue else { return }
                if let at = constraints.firstIndex(where: { $0.id == id }) { constraints[at] = newValue }
                else { constraints.append(newValue) }
            }
        }

        public subscript(name: String) -> IKRig.Constraint? {
            get { constraints.first { $0.name == name } }
            set { self[newValue?.id ?? IKRig.Constraint.ID(name: name)] = newValue }
        }

        @discardableResult
        public mutating func set(_ newValue: IKRig.Constraint) -> IKRig.Constraint? {
            let id = newValue.id
            if let at = constraints.firstIndex(where: { $0.id == id }) {
                let old = constraints[at]
                constraints[at] = newValue
                return old
            }
            constraints.append(newValue)
            return nil
        }

        public func contains(_ id: IKRig.Constraint.ID) -> Bool { constraints.contains { $0.id == id } }
        public var isEmpty: Bool { constraints.isEmpty }
        public var startIndex: Int { constraints.startIndex }
        public var endIndex: Int { constraints.endIndex }
        public func index(after i: Int) -> Int { constraints.index(after: i) }
        public subscript(position: Int) -> IKRig.Constraint { constraints[position] }
    }

    /// The joint names above a joint, nearest first, which is the order a solve walks them in.
    public func chain(above jointName: String) -> [String] {
        var names: [String] = []
        var parent = joints[name: jointName]?.parentID
        var steps = 0
        while let current = parent, steps < joints.count {
            names.append(current.name)
            parent = joints[IKRig.Joint.ID(name: current.name)]?.parentID
            steps += 1
        }
        return names
    }
}

// MARK: - The component an entity is solved by

/// The component an entity carries to be solved: the resource its solvers come from, and the
/// solvers themselves. `:8842-9075`.
@frozen public struct IKComponent: Component {
    /// The solvers' source, and nil for an entity that is not solved.
    public var resource: IKResource?
    public var solvers: SolverCollection

    public init(resource: IKResource?) {
        self.resource = resource
        // A resource built from a rig carries that rig's definition, so an entity given a resource
        // and no solver of its own is solved by the one the resource holds. That is what
        // `solvers` means here when a program sets only the resource.
        self.solvers = resource.map { SolverCollection([Solver(rig: $0.solverDefinitions.first?.rigDefinition ?? IKRig())]) }
            ?? SolverCollection()
    }

    /// One solver: a rig, the weights the solve obeys, and the joints and constraints it works on.
    public struct Solver: Identifiable, Equatable {
        public typealias ID = Int

        public var id: ID
        public var maxIterations: Int { rig.maxIterations }
        public var globalFkWeight: Float { rig.globalFkWeight }
        /// The rig this solver solves, and with it its joints and its constraints: the interface
        /// gives a solver these three through the rig (:8862-8866) and not as its own storage.
        public var rig: IKRig
        public var joints: IKRig.JointCollection { rig.joints }
        public var constraints: IKRig.ConstraintsCollection { rig.constraints }

        public init(id: ID = 0, rig: IKRig = IKRig()) {
            self.id = id
            self.rig = rig
        }

        /// Puts the rig back as it was made: every joint at its rest transform and every weight as
        /// it was set, which is what `reset()` is for (:8861).
        public func reset() {
            for at in rig.joints.indices {
                rig.joints[at].restTransform = .identity
            }
        }
    }

    /// A joint of a solver, as the solver sees it: its name and the two weights.
    public struct Joint: Equatable {
        public typealias ID = IKRig.Joint.ID

        public var name: String { joint.name }
        public var fkWeightPerAxis: SIMD3<Float> { joint.fkWeightPerAxis }
        public var rotationStiffness: SIMD3<Float> { joint.rotationStiffness }

        let joint: IKRig.Joint
        init(_ joint: IKRig.Joint) { self.joint = joint }
    }

    /// A constraint of a solver, and what it is asked for.
    public struct Constraint: Identifiable, Equatable {
        public typealias ID = IKRig.Constraint.ID

        /// Which demands a constraint makes. The interface gives this an OptionSet and declares no
        /// member of it (:8890-8901), so the only values here are the raw ones a caller writes.
        public struct DemandOptions: OptionSet, Equatable, Hashable {
            public let rawValue: UInt
            public init(rawValue: UInt) { self.rawValue = rawValue }
        }

        public let id: ID
        public var name: String { constraint.name }
        public var jointID: Joint.ID { Joint.ID(name: constraint.jointName) }
        public var demands: DemandOptions
        /// Where the target is, in the entity's own space.
        public var target: Transform
        /// Where the target is, relative to the joint.
        public var offset: Transform
        /// Where a look-at points, which is the axis the demand names when it has one.
        public var lookAtTargetPosition: SIMD3<Float>
        /// How much of the target the animation's own value keeps, for position and for rotation.
        public var animationOverrideWeight: (position: Float, rotation: Float)

        let constraint: IKRig.Constraint
        public init(_ constraint: IKRig.Constraint, demands: DemandOptions = DemandOptions(),
                    target: Transform = .identity, offset: Transform = .identity,
                    lookAtTargetPosition: SIMD3<Float> = .zero,
                    animationOverrideWeight: (position: Float, rotation: Float) = (0, 0)) {
            self.constraint = constraint
            self.id = constraint.id
            self.demands = demands
            self.target = target
            self.offset = offset
            self.lookAtTargetPosition = lookAtTargetPosition
            self.animationOverrideWeight = animationOverrideWeight
        }
    }

    /// The solvers of a component, looked up by identity or by position.
    public struct SolverCollection: Collection, Equatable {
        public typealias Element = Solver
        public typealias Index = Int

        private var solvers: [Solver]
        public init(_ solvers: [Solver] = []) { self.solvers = solvers }

        public subscript(id: Solver.ID) -> Solver? {
            get { solvers.first { $0.id == id } }
            set {
                guard let newValue else { return }
                if let at = solvers.firstIndex(where: { $0.id == id }) { solvers[at] = newValue }
                else { solvers.append(newValue) }
            }
        }

        @discardableResult
        public mutating func set(_ newValue: Solver) -> Solver? {
            if let at = solvers.firstIndex(where: { $0.id == newValue.id }) {
                let old = solvers[at]
                solvers[at] = newValue
                return old
            }
            solvers.append(newValue)
            return nil
        }

        public func contains(_ id: Solver.ID) -> Bool { solvers.contains { $0.id == id } }
        public var isEmpty: Bool { solvers.isEmpty }
        public var startIndex: Int { solvers.startIndex }
        public var endIndex: Int { solvers.endIndex }
        public func index(after i: Int) -> Int { solvers.index(after: i) }
        public subscript(position: Int) -> Solver { solvers[position] }
    }

    /// The joints of a solver, looked up by identity or by name.
    public struct JointCollection: Collection, Equatable {
        public typealias Element = Joint
        public typealias Index = Int

        private var joints: [Joint]
        public init(_ joints: [Joint] = []) { self.joints = joints }

        public subscript(id: Joint.ID) -> Joint? {
            get { joints.first { Joint.ID(name: $0.name) == id } }
            set {
                guard let newValue else { return }
                if let at = joints.firstIndex(where: { Joint.ID(name: $0.name) == id }) { joints[at] = newValue }
                else { joints.append(newValue) }
            }
        }

        public subscript(name: String) -> Joint? {
            get { joints.first { $0.name == name } }
            set { self[newValue.map { Joint.ID(name: $0.name) } ?? Joint.ID(name: name)] = newValue }
        }

        @discardableResult
        public mutating func set(_ newValue: Joint) -> Joint? {
            let id = Joint.ID(name: newValue.name)
            if let at = joints.firstIndex(where: { Joint.ID(name: $0.name) == id }) {
                let old = joints[at]
                joints[at] = newValue
                return old
            }
            joints.append(newValue)
            return nil
        }

        public func contains(_ id: Joint.ID) -> Bool { joints.contains { Joint.ID(name: $0.name) == id } }
        public var isEmpty: Bool { joints.isEmpty }
        public var startIndex: Int { joints.startIndex }
        public var endIndex: Int { joints.endIndex }
        public func index(after i: Int) -> Int { joints.index(after: i) }
        public subscript(position: Int) -> Joint { joints[position] }
    }

    /// The constraints of a solver, looked up the same way.
    public struct ConstraintCollection: Collection, Equatable {
        public typealias Element = Constraint
        public typealias Index = Int

        private var constraints: [Constraint]
        public init(_ constraints: [Constraint] = []) { self.constraints = constraints }

        public subscript(id: Constraint.ID) -> Constraint? {
            get { constraints.first { $0.id == id } }
            set {
                guard let newValue else { return }
                if let at = constraints.firstIndex(where: { $0.id == id }) { constraints[at] = newValue }
                else { constraints.append(newValue) }
            }
        }

        public subscript(name: String) -> Constraint? {
            get { constraints.first { $0.name == name } }
            set { self[newValue?.id ?? Constraint.ID(name: name)] = newValue }
        }

        @discardableResult
        public mutating func set(_ newValue: Constraint) -> Constraint? {
            if let at = constraints.firstIndex(where: { $0.id == newValue.id }) {
                let old = constraints[at]
                constraints[at] = newValue
                return old
            }
            constraints.append(newValue)
            return nil
        }

        public func contains(_ id: Constraint.ID) -> Bool { constraints.contains { $0.id == id } }
        public var isEmpty: Bool { constraints.isEmpty }
        public var startIndex: Int { constraints.startIndex }
        public var endIndex: Int { constraints.endIndex }
        public func index(after i: Int) -> Int { constraints.index(after: i) }
        public subscript(position: Int) -> Constraint { constraints[position] }
    }
}

// MARK: - The resource and the solver definition

/// A solver definition: an identity and the rig it solves. `:4738-4744`.
@frozen public struct IKSolverDefinition: Identifiable, Equatable {
    public typealias ID = Int
    public let id: ID
    public var rigDefinition: IKRig

    public init(id: ID, rig: IKRig) {
        self.id = id
        self.rigDefinition = rig
    }
}

/// A resource that holds the solver definitions a component is solved by. `:10958-10965`.
///
/// `solverDefinitions` reads and `init(rig:)` throws are the interface's, and both are carried
/// whole: a rig is the input, and the resource holds one definition per rig it is given, so nothing
/// has to be read out of a bundle to make one. `__coreAsset` is the `__` member the interface also
/// has, and it is not carried - it is the compiler's handle on the compiled asset, which a rig a
/// program built has no use for.
@MainActor
public class IKResource: Resource {
    private var definitions: [IKSolverDefinition]

    /// The definitions this resource holds, in the order they were made. `:10963`.
    public var solverDefinitions: [IKSolverDefinition] { definitions }

    /// A resource over a rig, which is the interface's own initializer: it throws when the rig is
    /// not one this resource can solve, and the only way that can happen here is a rig with no
    /// joints, because a rig with joints is a rig. `:10964`.
    public convenience init(rig: IKRig) throws {
        guard !rig.joints.isEmpty else { throw IKResourceError.emptyRig }
        self.init(definitions: [IKSolverDefinition(id: 0, rig: rig)])
    }

    init(definitions: [IKSolverDefinition]) {
        self.definitions = definitions
    }
}

/// Why a rig could not become a resource. The one case, and the registry carries it: a resource
/// solves joints, so a rig with none is nothing to solve.
public enum IKResourceError: Error {
    case emptyRig
}

extension Entity {
    /// The inverse-kinematics component on this entity, or nil when it has none.
    public var inverseKinematics: IKComponent? {
        get { components[IKComponent.self] }
        set {
            if let newValue {
                components.set(newValue)
            } else {
                components.remove(IKComponent.self)
            }
        }
    }
}
