import CoreAudio
import EarRing
import XCTest

final class RingTests: XCTestCase {
    private let channels = 3
    private let block = 256
    private let target = 1024

    private var ring: OpaquePointer!

    override func setUp() {
        ring = ear_ring_create(UInt32(channels), 8192, UInt32(target), 48_000)
    }

    override func tearDown() {
        ear_ring_destroy(ring)
    }

    /// Writes one planar block; channel c carries `base + c * 1000 + frame index`.
    private func write(base: Float) {
        let list = AudioBufferList.allocate(maximumBuffers: channels)
        let samples = (0..<channels).map { c -> UnsafeMutablePointer<Float> in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: block)
            for i in 0..<block { pointer[i] = base + Float(c * 1000) + Float(i) }
            return pointer
        }
        defer {
            samples.forEach { $0.deallocate() }
            free(list.unsafeMutablePointer)
        }
        for c in 0..<channels {
            list[c] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(block * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(samples[c])
            )
        }
        ear_ring_write(ring, list.unsafePointer, UInt32(block))
    }

    private func read(channel: Int) -> [Float] {
        var out = [Float](repeating: -1, count: block)
        out.withUnsafeMutableBufferPointer {
            ear_ring_read(ring, UInt32(channel), $0.baseAddress!, UInt32(block))
        }
        return out
    }

    func testSilentUntilPrimed() {
        write(base: 0)
        XCTAssertEqual(read(channel: 0), [Float](repeating: 0, count: block))
        XCTAssertEqual(ear_ring_primed(ring), 0)
    }

    func testChannelsStayAlignedWithEachOther() {
        for i in 0..<8 { write(base: Float(i * 10_000)) }

        let first = read(channel: 0)
        let second = read(channel: 1)
        let third = read(channel: 2)

        XCTAssertEqual(ear_ring_primed(ring), 1)
        XCTAssertNotEqual(first[0], 0)
        for i in 0..<block {
            XCTAssertEqual(second[i] - first[i], 1000)
            XCTAssertEqual(third[i] - first[i], 2000)
        }
    }

    func testTheNextReadContinuesWhereTheLastEnded() {
        for i in 0..<8 { write(base: Float(i * 10_000)) }

        let a = read(channel: 0)
        write(base: 80_000)
        let b = read(channel: 0)

        // Primed at `target` behind the writer: block 4 of 0...7, then block 5.
        XCTAssertEqual(a[0], 40_000)
        XCTAssertEqual(a[block - 1], 40_255)
        XCTAssertEqual(b[0], 50_000)
        XCTAssertEqual(ear_ring_underruns(ring), 0)
    }

    func testRunningDryCountsAnUnderrun() {
        for i in 0..<6 { write(base: Float(i * 10_000)) }
        for _ in 0..<12 { _ = read(channel: 0) }
        XCTAssertGreaterThan(ear_ring_underruns(ring), 0)
    }

    func testRunningOverJumpsBack() {
        for i in 0..<6 { write(base: Float(i * 10_000)) }
        _ = read(channel: 0)
        for i in 6..<20 { write(base: Float(i * 10_000)) }
        _ = read(channel: 0)
        XCTAssertEqual(ear_ring_overruns(ring), 1)
    }

    func testPingSoundsOnlyOnItsChannel() {
        ear_ring_ping(ring, 1)
        let quiet = read(channel: 0)
        let loud = read(channel: 1)

        XCTAssertEqual(quiet.map(abs).max(), 0)
        XCTAssertGreaterThan(loud.map(abs).max()!, 0.05)
        XCTAssertGreaterThan(ear_ring_level(ring, 1), 0.05)
    }
}
