import Foundation

enum SystemFormat {
    static let gigabyte = 1_073_741_824.0

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(Int64(max(bytesPerSecond, 0).rounded())) + "/s"
    }

    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: max(count, 0))
    }

    static func memory(used: UInt64, total: UInt64, locale: Locale = .autoupdatingCurrent) -> String {
        let usedText = (Double(used) / gigabyte).formatted(.number.precision(.fractionLength(1)).locale(locale))
        let totalText = (Double(total) / gigabyte).formatted(.number.precision(.fractionLength(0)).locale(locale))
        return "\(usedText) of \(totalText) GB"
    }

    static func timeRemaining(minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale)) + " left"
    }

    static func battery(_ battery: BatteryState, locale: Locale = .autoupdatingCurrent) -> String {
        let status: String? = if battery.isCharging {
            "Charging"
        } else if battery.isPluggedIn {
            "Plugged in"
        } else {
            battery.minutesRemaining.map { timeRemaining(minutes: $0, locale: locale) }
        }
        return ["\(battery.percent)%", status].compactMap(\.self).joined(separator: " · ")
    }

    static func pressure(_ pressure: MemoryPressure) -> String? {
        switch pressure {
        case .normal: nil
        case .warning: "Pressure high"
        case .critical: "Pressure critical"
        }
    }
}
