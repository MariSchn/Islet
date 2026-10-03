import CoreAudio
import Foundation
import Observation

struct AudioOutput: Equatable, Identifiable, Sendable {
    let id: UInt32
    let name: String
}

struct AudioDevice: Equatable, Sendable {
    let id: UInt32
    let name: String
    let hasOutput: Bool
}

@MainActor
protocol AudioOutputBackend: AnyObject {
    func devices() -> [AudioDevice]
    func defaultOutputID() -> UInt32?
    func setDefaultOutput(_ id: UInt32) -> Bool
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

@MainActor
@Observable
final class AudioOutputs {
    private(set) var devices: [AudioOutput] = []
    private(set) var currentID: UInt32?

    @ObservationIgnored private let backend: any AudioOutputBackend

    init(backend: any AudioOutputBackend = CoreAudioBackend()) {
        self.backend = backend
    }

    func start() {
        reload()
        backend.startObserving { [weak self] in self?.reload() }
    }

    func stop() {
        backend.stopObserving()
    }

    func select(_ output: AudioOutput) {
        guard backend.setDefaultOutput(output.id) else { return }
        reload()
    }

    private func reload() {
        devices = backend.devices().filter(\.hasOutput).map { AudioOutput(id: $0.id, name: $0.name) }
        currentID = backend.defaultOutputID()
    }
}

@MainActor
final class CoreAudioBackend: AudioOutputBackend {
    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var defaultAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private var listener: AudioObjectPropertyListenerBlock?

    func devices() -> [AudioDevice] {
        var address = Self.devicesAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let name = name(of: id) else { return nil }
            return AudioDevice(id: id, name: name, hasOutput: hasOutputStreams(id))
        }
    }

    func defaultOutputID() -> UInt32? {
        var address = Self.defaultAddress
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    func setDefaultOutput(_ id: UInt32) -> Bool {
        var address = Self.defaultAddress
        var value = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value) == noErr
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        stopObserving()
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { onChange() }
        }
        listener = block
        var devices = Self.devicesAddress
        var current = Self.defaultAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, .main, block)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &current, .main, block)
    }

    func stopObserving() {
        guard let block = listener else { return }
        listener = nil
        var devices = Self.devicesAddress
        var current = Self.defaultAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, .main, block)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &current, .main, block)
    }

    private func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private func name(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
