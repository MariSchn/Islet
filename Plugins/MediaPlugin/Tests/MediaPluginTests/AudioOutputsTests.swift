import Testing
@testable import MediaPlugin

@MainActor
private final class FakeBackend: AudioOutputBackend {
    var available: [AudioDevice]
    var current: UInt32?
    var selected: [UInt32] = []
    var onChange: (@MainActor () -> Void)?
    var observing = false

    init(available: [AudioDevice], current: UInt32?) {
        self.available = available
        self.current = current
    }

    func devices() -> [AudioDevice] { available }
    func defaultOutputID() -> UInt32? { current }

    func setDefaultOutput(_ id: UInt32) -> Bool {
        selected.append(id)
        current = id
        return true
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        observing = true
    }

    func stopObserving() {
        onChange = nil
        observing = false
    }
}

@MainActor
struct AudioOutputsTests {
    private let speakers = AudioDevice(id: 1, name: "Speakers", hasOutput: true)
    private let airPods = AudioDevice(id: 2, name: "AirPods", hasOutput: true)
    private let microphone = AudioDevice(id: 3, name: "Microphone", hasOutput: false)

    @Test func startListsOnlyOutputDevicesAndMarksTheCurrentOne() {
        let backend = FakeBackend(available: [speakers, microphone, airPods], current: 2)
        let outputs = AudioOutputs(backend: backend)

        outputs.start()

        #expect(outputs.devices.map(\.id) == [1, 2])
        #expect(outputs.currentID == 2)
        #expect(backend.observing)
    }

    @Test func selectCallsTheBackendAndUpdatesTheCurrentOutput() {
        let backend = FakeBackend(available: [speakers, airPods], current: 1)
        let outputs = AudioOutputs(backend: backend)
        outputs.start()

        outputs.select(AudioOutput(id: 2, name: "AirPods"))

        #expect(backend.selected == [2])
        #expect(outputs.currentID == 2)
    }

    @Test func changeNotificationsUpdateDevicesAndCurrentOutput() {
        let backend = FakeBackend(available: [speakers], current: 1)
        let outputs = AudioOutputs(backend: backend)
        outputs.start()

        backend.available = [speakers, airPods]
        backend.current = 2
        backend.onChange?()

        #expect(outputs.devices.map(\.id) == [1, 2])
        #expect(outputs.currentID == 2)
    }

    @Test func stopRemovesTheObserver() {
        let backend = FakeBackend(available: [speakers], current: 1)
        let outputs = AudioOutputs(backend: backend)
        outputs.start()

        outputs.stop()

        #expect(!backend.observing)
    }
}
