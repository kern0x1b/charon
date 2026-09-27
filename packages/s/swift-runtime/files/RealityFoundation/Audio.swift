// Spatial audio: a resource, a playback controller, and the attenuation and panning a listener
// hears them with.
//
// The engine is AVFAudio's: an `AVAudioEngine` with an `AVAudioEnvironmentNode` for the spatial
// work, one `AVAudioPlayerNode` per playing resource, and the environment node's own listener
// and source placement, which is what turns a position into a gain and a pan. The laws this
// module adds are the ones RealityKit documents and AVFAudio does not: which model a distance is
// attenuated by, and what a source out of range does.

#if canImport(AVFoundation)
import AVFoundation
import simd
import Foundation


// MARK: - The resource

/// A sound an entity plays: what it is heard from, how loud, how fast, and how the distance to
/// the listener changes it.
@MainActor
open class AudioResource {
    public enum InputMode: Hashable {
        /// One channel, placed nowhere: what a stereo pair's left and right are.
        case nonSpatial
        /// Everywhere at once, not placed in the world.
        case ambient
        /// At the entity's position in the world.
        case spatial
    }

    /// What a sound's level is measured against.
    public enum Calibration: Hashable {
        /// Decibels relative to the calibration, which is what a sound recorded at a known
        /// level is.
        case absolute(dBSPL: Double)
        /// Decibels relative to the device's own output, which is what a sound normalised to
        /// the system's volume is.
        case relative(dBSPL: Double)
    }

    /// What a resource's level is measured against, and against what its peak is.
    public struct Normalization: Hashable {
        public var isEnabled: Bool
        public init(isEnabled: Bool = false) { self.isEnabled = isEnabled }
    }

    /// Where the sound is heard from.
    public var inputMode: InputMode
    /// The level the sound is played at, before the listener's gain.
    public var gain: Double
    /// The speed it is played at, which changes its pitch.
    public var speed: Double
    /// What the distance is attenuated by.
    public var attenuationModel: AttenuationModel

    public init(inputMode: InputMode = .spatial, gain: Double = 0, speed: Double = 1,
                attenuationModel: AttenuationModel = AttenuationModel.default()) {
        self.inputMode = inputMode
        self.gain = gain
        self.speed = speed
        self.attenuationModel = attenuationModel
    }

    public static func == (lhs: AudioResource, rhs: AudioResource) -> Bool {
        lhs === rhs
    }

}

/// How the distance between a listener and a sound changes what the listener hears.
@frozen public struct AttenuationModel: Hashable {
    /// The law the gain follows with distance.
    public enum Kind: Hashable {
        /// The gain falls off linearly to nothing at the maximum distance.
        case linear
        /// The gain is the distance over the maximum, so a nearby source is loud and it falls
        /// away gently.
        case logarithmic
        /// The gain falls off with the square of the distance.
        case square
    }

    public var kind: Kind
    /// The distance at which the sound is inaudible.
    public var maximumDistance: Float

    public init(kind: Kind, maximumDistance: Float) {
        self.kind = kind
        self.maximumDistance = maximumDistance
    }

    /// The attenuation a sound in the world falls off with by default: logarithmic over a
    /// hundred metres.
    public static func `default`() -> AttenuationModel {
        AttenuationModel(kind: .logarithmic, maximumDistance: 100)
    }

    /// The gain a sound `distance` away is heard at, from one at the listener to none at the
    /// maximum distance. A distance beyond the maximum is inaudible, and a maximum of zero
    /// puts the sound at the listener whatever the distance.
    public func gain(atDistance distance: Float) -> Float {
        guard maximumDistance > 0 else { return 1 }
        guard distance < maximumDistance else { return 0 }
        let ratio = max(0, distance / maximumDistance)
        switch kind {
        case .linear: return 1 - ratio
        case .logarithmic: return 1 - ratio
        case .square: return 1 - ratio * ratio
        }
    }
}

/// A sound in a file, by name.
@MainActor
open class AudioFileResource: AudioResource {
    /// The file's name, without its extension.
    public let name: String
    /// How the file is read into memory.
    public struct LoadingStrategy: Hashable, Sendable {
        public var isForced: Bool
        public var shouldCache: Bool
        public init(isForced: Bool = false, shouldCache: Bool = false) {
            self.isForced = isForced
            self.shouldCache = shouldCache
        }
    }

    public var loadingStrategy: LoadingStrategy
    /// Whether the file plays again when it reaches its end.
    public var shouldLoop: Bool

    public init(name: String, shouldLoop: Bool = false,
                loadingStrategy: LoadingStrategy = LoadingStrategy()) {
        self.name = name
        self.shouldLoop = shouldLoop
        self.loadingStrategy = loadingStrategy
        super.init()
    }
}

// MARK: - Where a sound is heard from

/// The listener: where the scene is heard from.
@MainActor
public final class AudioListener {
    /// The position and orientation the environment node hears the world from.
    public var transform: Transform
    /// The volume the whole scene is heard at.
    public var gain: Double

    public init(transform: Transform = .identity, gain: Double = 0) {
        self.transform = transform
        self.gain = gain
    }
}

// MARK: - The controller

/// One sound playing on one entity.
@MainActor
public final class AudioPlaybackController {
    public typealias Decibel = Double

    /// The entity the sound is on, which the controller does not keep alive.
    public weak var entity: Entity?
    /// The sound being played.
    public let resource: AudioResource
    /// Called when the sound reaches its end, or is stopped.
    public var completionHandler: (() -> Void)?
    /// The speed the sound plays at, which changes its pitch.
    public var speed: Double {
        get { resource.speed }
        set { resource.speed = newValue; player?.rate = Float(newValue) }
    }
    /// The level the sound is heard at, before the attenuation.
    public var gain: Double {
        get { resource.gain }
        set { resource.gain = newValue; player?.volume = Float(pow(10, newValue / 20)) }
    }
    /// Where in the sound the playback is, in seconds.
    public var playbackPosition: TimeInterval {
        get {
            guard let player, let nodeTime = player.lastRenderTime,
                  let time = player.playerTime(forNodeTime: nodeTime) else { return 0 }
            return Double(time.sampleTime) / format.sampleRate
        }
        set {
            guard let player else { return }
            player.stop()
            let frame = AVAudioFramePosition(newValue * format.sampleRate)
            if let buffer = buffer, frame >= 0, Int(frame) < Int(buffer.frameLength) {
                // The SDK's player node has no seek, so a position is set by starting the
                // buffer at the frame; the controller's own position then reads the same frame.
                let slice = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(Int(buffer.frameLength) - Int(frame)))
                if let slice, let source = buffer.floatChannelData, let target = slice.floatChannelData {
                    let start = Int(frame)
                    slice.frameLength = AVAudioFrameCount(Int(buffer.frameLength) - start)
                    for channel in 0..<Int(buffer.format.channelCount) {
                        target[channel].assign(from: source[channel] + start, count: Int(slice.frameLength))
                    }
                    self.slice = slice
                    player.scheduleBuffer(slice, at: nil, options: options)
                }
            }
            player.play()
        }
    }

    /// The engine this controller plays through, and the node it plays on.
    let engine: AVAudioEngine
    let environment: AVAudioEnvironmentNode
    var player: AVAudioPlayerNode?
    /// The buffer the sound is, and the length it plays for.
    var buffer: AVAudioPCMBuffer?
    /// The format the graph runs at, which a position in seconds is read and written against.
    var format: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    /// The options the next schedule uses, which a looping sound keeps.
    var options: AVAudioPlayerNodeBufferOptions = []
    /// The buffer from the frame a seek stopped at, which is what plays after one.
    var slice: AVAudioPCMBuffer?
    var duration: TimeInterval = 0
    var isPlaying = false

    init(entity: Entity, resource: AudioResource, engine: AVAudioEngine, environment: AVAudioEnvironmentNode) {
        self.entity = entity
        self.resource = resource
        self.engine = engine
        self.environment = environment
    }

    /// Starts the sound, from the beginning.
    ///
    /// A sound is only scheduled when the node it would play on takes the same number of
    /// channels as the buffer holds. AVFAudio raises an Objective-C exception for a mismatch
    /// rather than answering, and this must not crash a caller, so a node that is not connected
    /// for the buffer's format plays nothing and says the controller is not playing.
    public func play() {
        guard let player, !isPlaying, let buffer = slice ?? buffer else { return }
        // `outputFormat` is a function of the bus here, so the node's own format is asked for
        // with the bus zero, which is the player's own.
        let nodeFormat = player.outputFormat(forBus: 0)
        guard nodeFormat.channelCount == buffer.format.channelCount else {
            isPlaying = false
            return
        }
        isPlaying = true
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: options)
        player.play()
    }

    /// Stops the sound, keeping its position.
    public func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Stops the sound and rewinds it.
    public func stop() {
        player?.stop()
        isPlaying = false
        completionHandler?()
    }

    /// Seeks to a point in the sound.
    public func seek(to time: TimeInterval) {
        playbackPosition = time
    }

    /// Fades the level to `newValue` over `duration` seconds.
    public func fade(to newValue: Decibel, duration: TimeInterval) {
        guard duration > 0, let player else {
            gain = newValue
            return
        }
        let from = gain
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            let elapsed = Date().timeIntervalSince(start)
            let progress = min(1, elapsed / duration)
            self?.gain = from + (newValue - from) * progress
            if progress >= 1 { timer.invalidate() }
        }
    }
}

// MARK: - The graph

/// The audio graph of a scene: one engine, one environment node, and a player per sound.
///
/// The engine is what AVFAudio's backports build on this release. The probe the audio audit ran
/// asks exactly that - whether an `AVAudioEngine` with an `AVAudioEnvironmentNode` builds,
/// connects, starts and renders offline - because everything here stands or falls with it.
@MainActor
public final class AudioEngine {
    /// The engine and the environment node, and the players a scene's sounds play on.
    public let engine = AVAudioEngine()
    public let environment = AVAudioEnvironmentNode()
    /// Where the scene is heard from.
    public let listener = AudioListener()
    private var controllers: [ObjectIdentifier: AudioPlaybackController] = [:]
    private var started = false

    public init() {
        engine.attach(environment)
    }

    /// The samples a resource is played from, and the format they are in. A caller that has a
    /// file reads it into a buffer of its own format; this is what a generated sound is.
    public static func __tone(hz: Float, seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let count = AVAudioFrameCount(seconds * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let channel = buffer.floatChannelData else { return nil }
        buffer.frameLength = count
        for frame in 0..<Int(count) {
            channel[0][frame] = Float(sin(2.0 * Double.pi * Double(hz) * Double(frame) / format.sampleRate))
        }
        return buffer
    }

    /// The format the graph runs at, which the engine needs before it is started.
    public var format: AVAudioFormat?

    /// Builds the graph for a format and starts it.
    ///
    /// The order is the engine's, not the reader's: manual rendering mode is set while the
    /// engine is still stopped, the nodes are connected after it, and only then is it started.
    /// Set after a start, or with a format already on the output, the engine refuses with
    /// `com.apple.coreaudio.avfaudio -80801` - measured on this host, 2026-09-27, before and
    /// after the order was changed.
    ///
    /// A device with no audio - the emulator, or a machine with no output - reports the failure
    /// rather than pretending to play.
    public func start(format: AVAudioFormat, offline: Bool = false,
                      maximumFrameCount: AVAudioFrameCount = 4096) throws {
        // Manual rendering mode is set first and while the engine is still stopped; the
        // connections come after it, and the start after that. Measured on the host, 2026-09-27:
        // the other order is refused with com.apple.coreaudio.avfaudio -80801, and this one
        // renders.
        if offline {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrameCount)
        }
        self.format = format
        engine.connect(environment, to: engine.mainMixerNode, format: format)
        try engine.start()
        started = true
    }

    /// The format the engine renders with once it is in manual rendering mode, which is the one a
    /// buffer has to be in for the engine to accept it.
    public var renderingFormat: AVAudioFormat { engine.manualRenderingFormat }

    /// Renders the graph with no output device in it, which is how the engine is checked
    /// without one, and answers the samples it produced.
    public func renderOffline(_ frames: AVAudioFrameCount) throws -> [Float] {
        var rendered: [Float] = []
        while rendered.count < Int(frames) {
            let wanted = AVAudioFrameCount(Int(frames) - rendered.count)
            guard let scratch = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                                 frameCapacity: max(wanted, 1)) else { break }
            let status = try engine.renderOffline(wanted, to: scratch)
            guard status == .success, scratch.frameLength > 0, let data = scratch.floatChannelData else { break }
            for frame in 0..<Int(scratch.frameLength) { rendered.append(data[0][frame]) }
        }
        return rendered
    }

    public func stop() {
        engine.stop()
        started = false
    }

    /// Plays a sound on an entity and hands back the controller.
    public func play(_ resource: AudioResource, on entity: Entity, buffer: AVAudioPCMBuffer) -> AudioPlaybackController {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        // The graph has one format, and a source is converted into it: the engine refuses a
        // connection whose format the destination does not take (com.apple.coreaudio.avfaudio
        // -10874), and a mono sound has to reach a stereo environment node somehow.
        let graphFormat = format ?? buffer.format
        let playable = __reConvert(buffer, to: graphFormat)
        if resource.inputMode != .nonSpatial {
            engine.connect(player, to: environment, format: playable.format)
        } else {
            engine.connect(player, to: engine.mainMixerNode, format: playable.format)
        }
        let controller = AudioPlaybackController(entity: entity, resource: resource,
                                               engine: engine, environment: environment)
        controller.player = player
        controller.buffer = playable
        controller.options = []
        controller.format = playable.format
        controller.duration = playable.frameLength > 0
            ? Double(playable.frameLength) / playable.format.sampleRate : 0
        controllers[ObjectIdentifier(controller)] = controller
        if let format {
            __place(controller, on: entity)
        }
        controller.play()
        return controller
    }

    /// The gains and positions a frame is heard with: the listener's, every source's, and what
    /// the environment node is given.
    ///
    /// The placement is a pure function of the two transforms and the model, so a caller - and a
    /// test - can ask what a sound is heard at without an engine.
    public func __place(_ controller: AudioPlaybackController, on entity: Entity) {
        guard let player = controller.player else { return }
        let source = entity.transformMatrix(relativeTo: nil)
        let here = __rePoint(source.columns.3)
        let there = __rePoint(listener.transform.matrix.columns.3)
        if controller.resource.inputMode != .nonSpatial {
            player.position = __rePoint3D(here)
        }
        let distance = simd_length(here - there)
        let attenuated = controller.resource.attenuationModel.gain(atDistance: distance)
        let decibels = controller.gain + Double(attenuated)
        player.volume = Float(pow(10.0, decibels / 20.0))
    }

    /// Puts the listener in the environment node, which is what the scene is heard from.
    public func __placeListener() {
        environment.position = __rePoint3D(__rePoint(listener.transform.matrix.columns.3))
    }

    /// The environment node's listener, the one this graph hands to the engine.
    public var listenerNode: AVAudioEnvironmentNode { environment }

    /// Whether the engine is running.
    public var isRunning: Bool { engine.isRunning }
}

@MainActor
private func __rePoint(_ vector: SIMD4<Float>) -> SIMD3<Float> {
    SIMD3<Float>(vector.x, vector.y, vector.z)
}

/// A buffer in the format the graph runs at: the same samples when the two agree, one channel
/// copied to each when the graph is wider, and the channels averaged when it is narrower.
@MainActor
private func __reConvert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer {
    guard let source = buffer.floatChannelData, buffer.format.channelCount != format.channelCount,
          let target = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
          let out = target.floatChannelData else { return buffer }
    target.frameLength = buffer.frameLength
    let from = Int(buffer.format.channelCount), to = Int(format.channelCount)
    for frame in 0..<Int(buffer.frameLength) {
        for channel in 0..<to {
            if from == 1 {
                out[channel][frame] = source[0][frame]
            } else {
                var total: Float = 0
                for read in 0..<from { total += source[read][frame] }
                out[channel][frame] = total / Float(from)
            }
        }
    }
    return target
}

/// The 3D point the audio engine places a node at, which is a C struct of three coordinates
/// here and is written with them, because there is no vector overload of its initialiser.
@MainActor
private func __rePoint3D(_ point: SIMD3<Float>) -> AVAudio3DPoint {
    AVAudio3DPoint(x: point.x, y: point.y, z: point.z)
}
#endif
