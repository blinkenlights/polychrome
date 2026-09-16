import AVFAudio
@testable import EarKit
import XCTest

final class GeometryTests: XCTestCase {
    func testNorthIsAheadEastIsRightUpIsUp() {
        let north = Geometry.avPoint(WorldPoint(x: 0, y: 10, z: 0))
        XCTAssertEqual(north.z, -10)

        let east = Geometry.avPoint(WorldPoint(x: 10, y: 0, z: 0))
        XCTAssertEqual(east.x, 10)

        let up = Geometry.avPoint(WorldPoint(x: 0, y: 0, z: 1.6))
        XCTAssertEqual(up.y, 1.6, accuracy: 1e-6)
    }

    func testFacingNorthIsTheDefaultOrientation() {
        let orientation = Geometry.avOrientation(heading: 0)
        XCTAssertEqual(orientation.forward.x, 0, accuracy: 1e-6)
        XCTAssertEqual(orientation.forward.z, -1, accuracy: 1e-6)
        XCTAssertEqual(orientation.up.y, 1)
    }

    func testFacingEastLooksAlongPositiveX() {
        let orientation = Geometry.avOrientation(heading: 90)
        XCTAssertEqual(orientation.forward.x, 1, accuracy: 1e-6)
        XCTAssertEqual(orientation.forward.z, 0, accuracy: 1e-6)
    }

    func testBearingIsClockwiseFromNorth() {
        XCTAssertEqual(Geometry.bearing(x: 0, y: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(Geometry.bearing(x: 1, y: 0), 90, accuracy: 1e-9)
        XCTAssertEqual(Geometry.bearing(x: 0, y: -1), 180, accuracy: 1e-9)
        XCTAssertEqual(Geometry.bearing(x: -1, y: 0), 270, accuracy: 1e-9)
    }

    func testRelativeBearingTurnsWithTheListener() {
        let east = WorldPoint(x: 10, y: 0, z: 0)
        let origin = WorldPoint(x: 0, y: 0, z: 0)

        XCTAssertEqual(Geometry.relativeBearing(of: east, from: Listener(position: origin, heading: 0)), 90, accuracy: 1e-9)
        XCTAssertEqual(Geometry.relativeBearing(of: east, from: Listener(position: origin, heading: 90)), 0, accuracy: 1e-9)
        XCTAssertEqual(Geometry.relativeBearing(of: east, from: Listener(position: origin, heading: 180)), -90, accuracy: 1e-9)
    }

    /// Matches what octopus answers for Nation 2026 (`Octopus.Sound.Speakers`).
    func testFallbackRingMatchesOctopus() {
        let speakers = Dictionary(uniqueKeysWithValues: Layout.fallback.speakers.map { ($0.channel, $0) })
        XCTAssertEqual(speakers.count, 12)

        let expected: [(channel: Int, panel: Int, x: Double, y: Double)] = [
            (1, 9, -5.0, 8.66), (3, 7, -10.0, 0.0), (6, 4, 0.0, -10.0),
            (9, 1, 10.0, 0.0), (12, 10, 0.0, 10.0),
        ]
        for e in expected {
            let s = speakers[e.channel]!
            XCTAssertEqual(s.panel, e.panel, "panel of channel \(e.channel)")
            XCTAssertEqual(s.x, e.x, accuracy: 0.01, "x of channel \(e.channel)")
            XCTAssertEqual(s.y, e.y, accuracy: 0.01, "y of channel \(e.channel)")
        }
    }

    func testDecodesTheOctopusAnswer() throws {
        let json = """
        {"ring_radius_m": 10.0, "platform_radius_m": 2.25,
         "listener_default": {"x": 0.0, "y": 0.0, "z": 1.6},
         "speakers": [{"channel": 1, "panel": 9, "x": -5.0, "y": 8.66, "z": 1.18}]}
        """
        let layout = try Layout.decode(Data(json.utf8))
        XCTAssertEqual(layout.ringRadiusM, 10)
        XCTAssertEqual(layout.speakers.first?.panel, 9)
        XCTAssertEqual(layout.listenerDefault.z, 1.6)
    }

    func testDecodesALinearInstallation() throws {
        let json = """
        {"ring_radius_m": null, "platform_radius_m": null,
         "listener_default": {"x": 0.0, "y": 0.0, "z": 1.6}, "speakers": []}
        """
        let layout = try Layout.decode(Data(json.utf8))
        XCTAssertNil(layout.ringRadiusM)
        XCTAssertTrue(layout.speakers.isEmpty)
    }
}
