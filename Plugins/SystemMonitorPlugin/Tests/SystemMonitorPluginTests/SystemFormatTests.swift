import Foundation
import Testing
@testable import SystemMonitorPlugin

struct SystemFormatTests {
    private let english = Locale(identifier: "en_US_POSIX")
    private var separator: String { Locale.autoupdatingCurrent.decimalSeparator ?? "." }

    @Test func ratesUseByteCountsPerSecond() {
        #expect(SystemFormat.rate(0) == "0 KB/s")
        #expect(SystemFormat.rate(-20) == "0 KB/s")
        #expect(SystemFormat.rate(1_000) == "1 KB/s")
        #expect(SystemFormat.rate(2_500_000) == "2\(separator)5 MB/s")
    }

    @Test func sizesUseByteCounts() {
        #expect(SystemFormat.bytes(2_000_000_000) == "2 GB")
        #expect(SystemFormat.bytes(-1) == "0 KB")
    }

    @Test func memoryShowsUsedOfTotal() {
        #expect(SystemFormat.memory(used: UInt64(9.1 * SystemFormat.gigabyte), total: 16 << 30, locale: english) == "9.1 of 16 GB")
        #expect(SystemFormat.memory(used: 0, total: 8 << 30, locale: english) == "0.0 of 8 GB")
    }

    @Test func percentRounds() {
        #expect(SystemFormat.percent(22.6) == "23%")
        #expect(SystemFormat.percent(0) == "0%")
    }

    @Test func batteryDescribesChargingAndTimeRemaining() {
        #expect(SystemFormat.battery(BatteryState(percent: 82, isCharging: true, isPluggedIn: true), locale: english) == "82% · Charging")
        #expect(SystemFormat.battery(BatteryState(percent: 100, isCharging: false, isPluggedIn: true), locale: english) == "100% · Plugged in")
        #expect(SystemFormat.battery(BatteryState(percent: 40, isCharging: false, isPluggedIn: false, minutesRemaining: 192), locale: english) == "40% · 3 hr, 12 min left")
        #expect(SystemFormat.battery(BatteryState(percent: 40, isCharging: false, isPluggedIn: false), locale: english) == "40%")
    }

    @Test func pressureLabelOnlyWhenNotNormal() {
        #expect(SystemFormat.pressure(.normal) == nil)
        #expect(SystemFormat.pressure(.warning) == "Pressure high")
        #expect(SystemFormat.pressure(.critical) == "Pressure critical")
    }
}
