import AudioToolbox
import AVFAudio
import CoreAudio
import EarRing
import Foundation

public enum EarError: LocalizedError {
    case noAudioUnit
    case audioUnit(String, OSStatus)
    case noChannels(String)
    case ringAllocation

    public var errorDescription: String? {
        switch self {
        case .noAudioUnit: "Die Audio-Unit für den Eingang fehlt"
        case let .audioUnit(step, status): "\(step) fehlgeschlagen (\(status))"
        case let .noChannels(name): "\(name) liefert keine Eingangskanäle"
        case .ringAllocation: "Ringpuffer konnte nicht angelegt werden"
        }
    }
}

/// The capture side: an AUHAL unit reading the loopback device straight into
/// the ring from its input callback.
///
/// Not `AVAudioEngine`: that caches the format of whichever device it saw
/// first and then refuses the connection when the device is switched under it.
/// Here the client format is stated outright, so the device is the only thing
/// that decides it.
public final class Capture {
    public let device: AudioDevice
    public let sampleRate: Double
    public let channels: Int

    private let unit: AudioUnit
    private var context: Unmanaged<Context>?
    private var running = false

    /// Everything the realtime callback touches, in one allocation it can
    /// reach through a raw pointer.
    private final class Context {
        let unit: AudioUnit
        let ring: OpaquePointer
        let buffers: UnsafeMutableAudioBufferListPointer
        let channels: Int
        let maxFrames: UInt32
        /// Written by the callback, read by the UI: the last thing that went
        /// wrong while rendering, and how often.
        var lastStatus: OSStatus = noErr
        var failures: Int = 0

        init(unit: AudioUnit, ring: OpaquePointer, channels: Int, maxFrames: UInt32) {
            self.unit = unit
            self.ring = ring
            self.channels = channels
            self.maxFrames = maxFrames
            buffers = AudioBufferList.allocate(maximumBuffers: channels)
            for channel in 0..<channels {
                buffers[channel] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: maxFrames * UInt32(MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer.allocate(
                        byteCount: Int(maxFrames) * MemoryLayout<Float>.size,
                        alignment: MemoryLayout<Float>.alignment
                    )
                )
            }
        }

        deinit {
            for buffer in buffers { buffer.mData?.deallocate() }
            free(buffers.unsafeMutablePointer)
        }
    }

    public init(device: AudioDevice) throws {
        self.device = device

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else { throw EarError.noAudioUnit }
        var instance: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &instance), "Audio-Unit anlegen")
        guard let unit = instance else { throw EarError.noAudioUnit }
        self.unit = unit

        // Input on bus 1, no output at all: this unit only reads.
        var enable: UInt32 = 1
        try Self.check(
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, UInt32(MemoryLayout<UInt32>.size)),
            "Eingang einschalten"
        )
        var disable: UInt32 = 0
        try Self.check(
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disable, UInt32(MemoryLayout<UInt32>.size)),
            "Ausgang abschalten"
        )
        var id = device.id
        try Self.check(
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioObjectID>.size)),
            "Gerät wählen"
        )

        // Ask the hardware what it has, then state the client format outright.
        var hardware = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try Self.check(
            AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size),
            "Hardware-Format lesen"
        )
        guard hardware.mChannelsPerFrame > 0, hardware.mSampleRate > 0 else { throw EarError.noChannels(device.name) }
        sampleRate = hardware.mSampleRate
        channels = Int(hardware.mChannelsPerFrame)

        var client = AudioStreamBasicDescription(
            mSampleRate: hardware.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: hardware.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        try Self.check(
            AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &client, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)),
            "Format setzen"
        )
    }

    deinit {
        stop()
        AudioComponentInstanceDispose(unit)
    }

    public func start(into ring: OpaquePointer) throws {
        guard !running else { return }

        var maxFrames: UInt32 = 4096
        try Self.check(
            AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, UInt32(MemoryLayout<UInt32>.size)),
            "Blockgröße setzen"
        )

        let context = Unmanaged.passRetained(Context(unit: unit, ring: ring, channels: channels, maxFrames: maxFrames))
        self.context = context

        var callback = AURenderCallbackStruct(
            inputProc: { refCon, flags, timestamp, bus, frames, _ in
                let context = Unmanaged<Context>.fromOpaque(refCon).takeUnretainedValue()
                guard frames <= context.maxFrames else { return noErr }

                let bytes = frames * UInt32(MemoryLayout<Float>.size)
                for channel in 0..<context.channels {
                    context.buffers[channel].mDataByteSize = bytes
                }
                let status = AudioUnitRender(context.unit, flags, timestamp, bus, frames, context.buffers.unsafeMutablePointer)
                if status == noErr {
                    ear_ring_write(context.ring, context.buffers.unsafePointer, frames)
                } else {
                    context.lastStatus = status
                    context.failures += 1
                }
                return status
            },
            inputProcRefCon: context.toOpaque()
        )
        try Self.check(
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)),
            "Rückruf setzen"
        )

        try Self.check(AudioUnitInitialize(unit), "Audio-Unit starten")
        try Self.check(AudioOutputUnitStart(unit), "Aufnahme starten")
        running = true
    }

    public func stop() {
        if running {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            running = false
        }
        context?.release()
        context = nil
    }

    /// What the callback last stumbled over, if anything.
    public var renderFailure: (status: OSStatus, count: Int)? {
        guard let context = context?.takeUnretainedValue(), context.failures > 0 else { return nil }
        return (context.lastStatus, context.failures)
    }

    private static func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw EarError.audioUnit(step, status) }
    }
}
