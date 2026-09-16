import AVFAudio
import EarRing

/// The playback side: one mono source per speaker, each placed where its panel
/// stands, rendered binaurally for headphones.
public final class SpatialRenderer {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private var sources: [Int: AVAudioSourceNode] = [:]
    private let ring: OpaquePointer
    private let sampleRate: Double

    /// Called on an arbitrary thread when the output hardware changes
    /// underneath the engine — headphones plugged, default device switched.
    public var onConfigurationChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    public init(ring: OpaquePointer, sampleRate: Double, speakers: [Speaker]) {
        self.ring = ring
        self.sampleRate = sampleRate

        engine.attach(environment)
        let output = engine.outputNode.outputFormat(forBus: 0)
        let stereo = AVAudioFormat(standardFormatWithSampleRate: output.sampleRate > 0 ? output.sampleRate : sampleRate, channels: 2)
        engine.connect(environment, to: engine.mainMixerNode, format: stereo)

        environment.outputType = .headphones
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 2
        environment.distanceAttenuationParameters.maximumDistance = 40
        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.largeHall2)
        environment.reverbParameters.level = 0

        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        for speaker in speakers {
            let source = makeSource(channel: speaker.channel, format: mono)
            engine.attach(source)
            engine.connect(source, to: environment, format: mono)
            source.renderingAlgorithm = .HRTFHQ
            source.sourceMode = .pointSource
            source.position = Geometry.avPoint(speaker.point)
            sources[speaker.channel] = source
        }

        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.onConfigurationChange?()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        engine.stop()
    }

    private func makeSource(channel: Int, format: AVAudioFormat) -> AVAudioSourceNode {
        let ring = ring
        let index = UInt32(channel - 1)
        return AVAudioSourceNode(format: format) { _, _, frames, buffers in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            if let data = list[0].mData?.assumingMemoryBound(to: Float.self) {
                ear_ring_read(ring, index, data, frames)
            }
            return noErr
        }
    }

    public func start() throws {
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.stop()
    }

    public func place(_ speakers: [Speaker]) {
        for speaker in speakers {
            sources[speaker.channel]?.position = Geometry.avPoint(speaker.point)
        }
    }

    public var listener: Listener = Listener(position: WorldPoint(x: 0, y: 0, z: 1.6)) {
        didSet {
            environment.listenerPosition = Geometry.avPoint(listener.position)
            environment.listenerVectorOrientation = Geometry.avOrientation(heading: listener.heading)
        }
    }

    /// 0 dry … 1 all hall.
    public var reverb: Float = 0.15 {
        didSet { for source in sources.values { source.reverbBlend = reverb } }
    }

    /// How fast sound falls with distance, beyond the 2 m reference.
    public var rolloff: Float = 0.6 {
        didSet { environment.distanceAttenuationParameters.rolloffFactor = rolloff }
    }

    public var gain: Float = 1 {
        didSet { engine.mainMixerNode.outputVolume = gain }
    }

    /// Pushes every setting to the nodes, for a renderer that was just built.
    public func apply(listener: Listener, reverb: Float, rolloff: Float, gain: Float) {
        self.listener = listener
        self.reverb = reverb
        self.rolloff = rolloff
        self.gain = gain
    }
}
