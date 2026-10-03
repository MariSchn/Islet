import Testing
@testable import SystemMonitorPlugin

struct RingBufferTests {
    @Test func keepsTheLastValuesInOrder() {
        var buffer = RingBuffer<Int>(capacity: 60)
        for value in 0..<45 {
            buffer.append(value)
        }
        #expect(buffer.values == Array(0..<45))
        for value in 45..<150 {
            buffer.append(value)
        }
        #expect(buffer.count == 60)
        #expect(buffer.values == Array(90..<150))
    }

    @Test func removeAllStartsOver() {
        var buffer = RingBuffer<Int>(capacity: 3)
        (0..<5).forEach { buffer.append($0) }
        buffer.removeAll()
        #expect(buffer.values.isEmpty)
        buffer.append(9)
        #expect(buffer.values == [9])
    }
}
