import AVFoundation
import CoreAudio
import EarKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppModel {
    // Geometry
    var octopusURL = "http://localhost:4000"
    private(set) var layout: Layout = .fallback
    private(set) var layoutFromOctopus = false
    private(set) var layoutError: String?

    // Listening
    var listener = Listener(position: Layout.fallback.listenerDefault) {
        didSet { pushListener() }
    }
    /// A slow, small turn of the head. Without it many people hear everything
    /// behind them: a generic HRTF alone does not settle front against back,
    /// movement does.
    var sway = false {
        didSet {
            if sway { headTracking = false }
            sway ? startSway() : stopSway()
        }
    }
    /// The real head, from AirPods. Better than the sway, because the movement
    /// is one's own.
    var headTracking = false {
        didSet {
            if headTracking { sway = false }
            headTracking ? startHeadTracking() : stopHeadTracking()
        }
    }
    var headTrackingInverted = false {
        didSet { head.inverted = headTrackingInverted }
    }
    private(set) var headState: HeadTracking.State = .waiting
    private(set) var headTurn = 0.0
    var reverb: Float = 0.15 {
        didSet { rig?.renderer.reverb = reverb }
    }
    var rolloff: Float = 0.6 {
        didSet { rig?.renderer.rolloff = rolloff }
    }
    var gain: Float = 1 {
        didSet { rig?.renderer.gain = gain }
    }

    // Audio
    private(set) var inputs: [AudioDevice] = []
    var selectedInputID: AudioObjectID?
    private(set) var engineError: String?
    private(set) var feedbackWarning: String?
    private(set) var levels: [Int: Float] = [:]
    private(set) var underruns = 0
    private(set) var overruns = 0
    private(set) var primed = false
    private(set) var pinging: Int?

    private var rig: AudioRig?
    private var meterTimer: Timer?
    private var pingTask: Task<Void, Never>?
    private let head = HeadTracking()
    private var swayTimer: Timer?
    private var swayPhase = 0.0
    private var swayOffset = 0.0
    private var lastBuild = Date.distantPast
    private var lastReport = Date.distantPast
    private let log = Logger(subsystem: "de.polychrome.ear", category: "app")

    var headTrackingAvailable: Bool { head.isAvailable }

    var selectedInput: AudioDevice? {
        inputs.first { $0.id == selectedInputID }
    }

    var rigDescription: String? {
        guard let rig else { return nil }
        let rate = String(format: "%.1f kHz", rig.sampleRate / 1000)
        return rig.capture == nil ? "Kein Eingang, nur Testton · \(rate)" : "\(rig.channels) Kanäle · \(rate)"
    }

    func boot() async {
        refreshDevices()
        selectedInputID = inputs.first { $0.name == Devices.loopbackName }?.id
        startMeters()
        await reloadLayout()
    }

    func refreshDevices() {
        inputs = Devices.inputs()
        if let id = selectedInputID, !inputs.contains(where: { $0.id == id }) {
            selectedInputID = nil
        }
    }

    func reloadLayout() async {
        let previousDefault = layout.listenerDefault
        do {
            guard let url = URL(string: octopusURL) else { throw URLError(.badURL) }
            // The first request of a fresh process can be slow enough to time
            // out on its own, so a single miss is not yet an answer.
            layout = try await load(from: url, attempts: 2)
            layoutFromOctopus = true
            layoutError = nil
            log.info("Geometrie von \(self.octopusURL, privacy: .public): \(self.layout.speakers.count) Lautsprecher")
        } catch {
            layout = .fallback
            layoutFromOctopus = false
            layoutError = error.localizedDescription
            log.error("Geometrie von \(self.octopusURL, privacy: .public) nicht geladen: \(error.localizedDescription, privacy: .public)")
        }
        if listener.position == previousDefault {
            listener.position = layout.listenerDefault
        }
        await rebuild()
    }

    private func load(from url: URL, attempts: Int) async throws -> Layout {
        var lastError: Error = URLError(.unknown)
        for attempt in 1...attempts {
            do { return try await Layout.load(from: url) } catch {
                lastError = error
                log.notice("Versuch \(attempt) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                if attempt < attempts { try? await Task.sleep(for: .milliseconds(400)) }
            }
        }
        throw lastError
    }

    func rebuild() async {
        pingTask?.cancel()
        pinging = nil
        rig = nil
        lastBuild = Date()

        let input = selectedInput
        feedbackWarning = nil
        if let input, input.name == Devices.defaultOutput()?.name {
            feedbackWarning = "Die Systemausgabe ist \(input.name). Stell die Ausgabe auf Kopfhörer, sonst hört die App sich selbst."
        }

        if input != nil, !(await microphoneAllowed()) {
            engineError = "Keine Mikrofon-Freigabe: Systemeinstellungen → Datenschutz → Mikrofon"
            return
        }

        do {
            let rig = try AudioRig(input: input, speakers: layout.speakers)
            rig.renderer.apply(listener: listener, reverb: reverb, rolloff: rolloff, gain: gain)
            rig.renderer.onConfigurationChange = { [weak self] in
                Task { @MainActor in self?.configurationChanged() }
            }
            try rig.start()
            self.rig = rig
            engineError = nil
        } catch {
            engineError = error.localizedDescription
            log.error("Engine nicht gestartet: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func configurationChanged() {
        // Starting an engine can itself post a change; only react to later ones.
        guard Date().timeIntervalSince(lastBuild) > 1 else { return }
        refreshDevices()
        Task { await rebuild() }
    }

    private func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    /// The listener as the renderer sees it: the chosen heading, plus whatever
    /// the head is doing — swaying on its own or turning for real.
    private func pushListener() {
        rig?.renderer.listener = Listener(
            position: listener.position,
            heading: listener.heading + swayOffset + headTurn
        )
    }

    private func startHeadTracking() {
        head.inverted = headTrackingInverted
        head.onStateChange = { [weak self] state in
            MainActor.assumeIsolated { self?.headState = state }
        }
        head.onTurn = { [weak self] turn in
            MainActor.assumeIsolated {
                guard let self, self.headTracking else { return }
                self.headTurn = turn
                self.pushListener()
            }
        }
        head.start()
        headState = head.state
        log.info("Headtracking an: \(self.head.state.text, privacy: .public)")
    }

    private func stopHeadTracking() {
        head.stop()
        headTurn = 0
        headState = head.state
        pushListener()
    }

    /// Takes the head's current direction as straight ahead.
    func recenterHead() {
        head.recenter()
        headTurn = 0
        pushListener()
    }

    private func startSway() {
        swayTimer?.invalidate()
        swayPhase = 0
        swayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.swayPhase += 2 * .pi * 0.25 / 30
                self.swayOffset = sin(self.swayPhase) * 7
                self.pushListener()
            }
        }
    }

    private func stopSway() {
        swayTimer?.invalidate()
        swayTimer = nil
        swayOffset = 0
        pushListener()
    }

    func resetListener() {
        listener = Listener(position: layout.listenerDefault, heading: 0)
    }

    /// One ping per speaker, clockwise from north.
    func pingAround() {
        pingTask?.cancel()
        let order = layout.speakers.sorted { $0.bearing < $1.bearing }.map(\.channel)
        pingTask = Task { [weak self] in
            for channel in order {
                guard let self, !Task.isCancelled else { return }
                self.pinging = channel
                self.rig?.ping(channel: channel)
                try? await Task.sleep(for: .milliseconds(550))
            }
            self?.pinging = nil
        }
    }

    /// One ping, from the panel that was tapped.
    func ping(channel: Int) {
        pingTask?.cancel()
        rig?.ping(channel: channel)
        pinging = channel
        pingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.pinging = nil
        }
    }

    private func startMeters() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readMeters() }
        }
    }

    private func readMeters() {
        guard let rig else {
            if !levels.isEmpty { levels = [:] }
            return
        }
        levels = Dictionary(uniqueKeysWithValues: layout.speakers.map { ($0.channel, rig.level(channel: $0.channel)) })
        underruns = rig.underruns
        overruns = rig.overruns
        primed = rig.primed
        report(rig)
    }

    /// A line every five seconds, so the log says what the meters show.
    private func report(_ rig: AudioRig) {
        guard Date().timeIntervalSince(lastReport) > 5 else { return }
        lastReport = Date()
        let loudest = levels.max { $0.value < $1.value }
        let peak = String(format: "%.3f", loudest?.value ?? 0)
        let failure = rig.capture?.renderFailure.map { " Aufnahmefehler \($0.status) x\($0.count)" } ?? ""
        let state = rig.primed ? "laeuft" : "fuellt sich"
        let line = "Eingang \(rig.channels) Kanaele, \(rig.framesCaptured) Bilder, Puffer \(state), Aussetzer \(rig.underruns), Spruenge \(rig.overruns), lautester Kanal \(loudest?.key ?? 0) bei \(peak)\(failure)"
        log.info("\(line, privacy: .public)")
    }
}
