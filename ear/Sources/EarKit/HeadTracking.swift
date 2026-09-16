import CoreMotion
import Foundation

/// The head of whoever is listening, as the AirPods report it.
///
/// Works with headphones that carry motion sensors: AirPods Pro (both
/// generations), AirPods 3, AirPods Max, Beats Fit Pro. Only the turn around
/// the vertical axis is used — nodding and tilting have no meaning for a ring
/// of speakers standing on the ground.
public final class HeadTracking {
    public enum State: Equatable {
        case unavailable
        case denied
        case waiting
        case tracking

        public var text: String {
            switch self {
            case .unavailable: "Keine Kopfhörer mit Bewegungssensor"
            case .denied: "Keine Freigabe für Bewegungsdaten"
            case .waiting: "Warte auf die Kopfhörer"
            case .tracking: "Kopf wird verfolgt"
            }
        }
    }

    private let manager = CMHeadphoneMotionManager()
    private var reference: Double?

    /// Degrees the head has turned since the last recentre, clockwise positive.
    public var onTurn: ((Double) -> Void)?
    public private(set) var state: State = .waiting
    public var onStateChange: ((State) -> Void)?

    /// Turning the head right should turn the listener right. CoreMotion counts
    /// yaw the other way round, counter-clockwise from above.
    public var inverted = false

    public init() {}

    public var isAvailable: Bool { manager.isDeviceMotionAvailable }

    public func start() {
        guard manager.isDeviceMotionAvailable else { return set(.unavailable) }
        if CMHeadphoneMotionManager.authorizationStatus() == .denied { return set(.denied) }

        reference = nil
        set(.waiting)
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if error != nil { return self.set(.denied) }
            guard let motion else { return }

            let yaw = motion.attitude.yaw
            let reference = self.reference ?? yaw
            self.reference = reference

            var turn = (yaw - reference) * 180 / .pi
            turn = turn.truncatingRemainder(dividingBy: 360)
            if turn > 180 { turn -= 360 }
            if turn <= -180 { turn += 360 }

            self.set(.tracking)
            self.onTurn?(self.inverted ? turn : -turn)
        }
    }

    public func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
        set(.waiting)
    }

    /// Takes the head's current direction as the new straight ahead.
    public func recenter() {
        reference = nil
        onTurn?(0)
    }

    private func set(_ state: State) {
        guard state != self.state else { return }
        self.state = state
        onStateChange?(state)
    }
}
