import AVFAudio
import Foundation

/// A point in the installation's world: meters, `x` east, `y` north, `z` up.
/// The same axes as `Octopus.Installation.World`.
public struct WorldPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// One output channel of scsynth and where its speaker stands.
public struct Speaker: Codable, Equatable, Identifiable, Sendable {
    public var channel: Int
    public var panel: Int
    public var x: Double
    public var y: Double
    public var z: Double

    public var id: Int { channel }
    public var point: WorldPoint { WorldPoint(x: x, y: y, z: z) }

    /// Compass bearing from the ring center, degrees clockwise from north.
    public var bearing: Double { Geometry.bearing(x: x, y: y) }

    public init(channel: Int, panel: Int, x: Double, y: Double, z: Double) {
        self.channel = channel
        self.panel = panel
        self.x = x
        self.y = y
        self.z = z
    }
}

/// What `GET /api/sound/speakers` answers.
public struct Layout: Codable, Equatable, Sendable {
    public var ringRadiusM: Double?
    public var platformRadiusM: Double?
    public var listenerDefault: WorldPoint
    public var speakers: [Speaker]

    public var radius: Double {
        ringRadiusM ?? speakers.map { hypot($0.x, $0.y) }.max() ?? 10
    }

    public init(ringRadiusM: Double?, platformRadiusM: Double?, listenerDefault: WorldPoint, speakers: [Speaker]) {
        self.ringRadiusM = ringRadiusM
        self.platformRadiusM = platformRadiusM
        self.listenerDefault = listenerDefault
        self.speakers = speakers
    }

    public static func decode(_ data: Data) throws -> Layout {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Layout.self, from: data)
    }

    public static func load(from base: URL) async throws -> Layout {
        let url = base.appending(path: "api/sound/speakers")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let layout = try decode(data)
        guard !layout.speakers.isEmpty else { throw URLError(.cannotParseResponse) }
        return layout
    }

    /// The Nation 2026 ring as octopus describes it, for when octopus is not
    /// around: 12 panels on 10 m, panel 10 due north, channels in frame order
    /// running counter-clockwise.
    public static let fallback: Layout = {
        let count = 12
        let north = 10
        let radius = 10.0
        let speakers = (1...count).map { channel -> Speaker in
            // Frame index f sits (count - 1 - f) steps clockwise of north,
            // see `Octopus.Radar.PanelMapping.installation_panel_of_frame/3`.
            let steps = (count - channel) % count
            let theta = Double(steps) * 2 * .pi / Double(count)
            let panel = (steps + north - 1) % count + 1
            return Speaker(channel: channel, panel: panel, x: radius * sin(theta), y: radius * cos(theta), z: 1.18)
        }
        return Layout(
            ringRadiusM: radius,
            platformRadiusM: 2.25,
            listenerDefault: WorldPoint(x: 0, y: 0, z: 1.6),
            speakers: speakers
        )
    }()
}

/// Where the listener stands and which way they look.
public struct Listener: Equatable, Sendable {
    public var position: WorldPoint
    /// Degrees clockwise from north.
    public var heading: Double

    public init(position: WorldPoint, heading: Double = 0) {
        self.position = position
        self.heading = heading
    }
}

public enum Geometry {
    /// AVAudioEnvironmentNode is OpenAL-shaped: `x` right, `y` up, `-z` ahead
    /// of a listener in default orientation. Facing north in the world, east
    /// is to the right, so north maps to `-z` and up to `y`.
    public static func avPoint(_ p: WorldPoint) -> AVAudio3DPoint {
        AVAudio3DPoint(x: Float(p.x), y: Float(p.z), z: Float(-p.y))
    }

    /// The listener's orientation as vectors — no yaw sign convention to get wrong.
    public static func avOrientation(heading: Double) -> AVAudio3DVectorOrientation {
        let h = heading * .pi / 180
        let ahead = WorldPoint(x: sin(h), y: cos(h), z: 0)
        return AVAudio3DVectorOrientation(
            forward: avPoint(ahead),
            up: AVAudio3DVector(x: 0, y: 1, z: 0)
        )
    }

    /// Compass bearing of a ground vector, degrees clockwise from north in 0..<360.
    public static func bearing(x: Double, y: Double) -> Double {
        let degrees = atan2(x, y) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Where a source appears to the listener: degrees, 0 ahead, positive to the right.
    public static func relativeBearing(of point: WorldPoint, from listener: Listener) -> Double {
        let absolute = bearing(x: point.x - listener.position.x, y: point.y - listener.position.y)
        var relative = (absolute - listener.heading).truncatingRemainder(dividingBy: 360)
        if relative > 180 { relative -= 360 }
        if relative <= -180 { relative += 360 }
        return relative
    }
}
