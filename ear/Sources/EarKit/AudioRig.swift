import AVFAudio
import EarRing

/// Capture, ring and renderer as one thing that is built, started and torn
/// down together. Rebuilt whenever the input device or the speakers change.
public final class AudioRig {
    /// The fill the reader aims for. Both device blocks have to fit, with room
    /// for the clocks to wander.
    public static let targetLatency = 0.05

    public let renderer: SpatialRenderer
    public let capture: Capture?
    public let channels: Int
    public let sampleRate: Double
    private let ring: OpaquePointer

    /// Without an input the ring stays silent, but the renderer still runs, so
    /// the ping can check orientation before anything else is set up.
    public init(input: AudioDevice?, speakers: [Speaker]) throws {
        let capture = try input.map(Capture.init)
        let sampleRate = capture?.sampleRate ?? 48_000
        let channels = capture?.channels ?? (speakers.map(\.channel).max() ?? 12)

        guard let ring = ear_ring_create(
            UInt32(channels),
            UInt32(sampleRate * 0.5),
            UInt32(sampleRate * Self.targetLatency),
            sampleRate
        ) else { throw EarError.ringAllocation }

        self.ring = ring
        self.capture = capture
        self.channels = channels
        self.sampleRate = sampleRate
        self.renderer = SpatialRenderer(ring: ring, sampleRate: sampleRate, speakers: speakers)
    }

    deinit {
        stop()
        ear_ring_destroy(ring)
    }

    public func start() throws {
        try renderer.start()
        try capture?.start(into: ring)
    }

    public func stop() {
        capture?.stop()
        renderer.stop()
    }

    public func level(channel: Int) -> Float {
        ear_ring_level(ring, UInt32(channel - 1))
    }

    public var framesCaptured: UInt64 { ear_ring_written(ring) }
    public var underruns: Int { Int(ear_ring_underruns(ring)) }
    public var overruns: Int { Int(ear_ring_overruns(ring)) }
    public var primed: Bool { ear_ring_primed(ring) != 0 }

    public func ping(channel: Int) {
        ear_ring_ping(ring, UInt32(channel - 1))
    }
}
