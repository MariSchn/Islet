import Darwin
import Foundation

struct TmuxClient: Sendable, Equatable {
    let tty: String
    let pid: Int32
    let activity: Int
    let session: String

    static let listFormat = "#{client_tty} #{client_pid} #{client_activity} #{client_session}"

    static func parse(_ output: String) -> [TmuxClient] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4, !fields[0].isEmpty, let pid = Int32(fields[1]), let activity = Int(fields[2]) else { return nil }
            return TmuxClient(tty: String(fields[0]), pid: pid, activity: activity, session: String(fields[3]))
        }
    }

    static func choose(from clients: [TmuxClient], session: String?) -> TmuxClient? {
        let attached = session.map { session in clients.filter { $0.session == session } } ?? []
        return (attached.isEmpty ? clients : attached).max { $0.activity < $1.activity }
    }
}

enum WezTermPanes {
    static func paneID(in json: Data, tty: String) -> Int? {
        guard let entries = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return nil }
        return entries.first { $0["tty_name"] as? String == tty }?["pane_id"] as? Int
    }
}

enum ProcessTree {
    static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func parent(of pid: Int32) -> Int32? {
        guard let parent = info(of: pid)?.kp_eproc.e_ppid else { return nil }
        return parent > 0 ? parent : nil
    }

    static func terminalDevice(of pid: Int32) -> dev_t? {
        guard let device = info(of: pid)?.kp_eproc.e_tdev, device != -1 else { return nil }
        return device
    }

    static func terminalShell(of pid: Int32) -> Int32? {
        guard let device = terminalDevice(of: pid) else { return nil }
        var shell = pid
        for ancestor in ancestors(of: pid) {
            guard terminalDevice(of: ancestor) == device else { break }
            shell = ancestor
        }
        return shell
    }

    static func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : path
    }

    static func terminalDirectory(of pid: Int32) -> String? {
        terminalShell(of: pid).flatMap(workingDirectory)
    }

    private static func info(of pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    static func ancestors(of pid: Int32, limit: Int = 64) -> [Int32] {
        var result: [Int32] = []
        var current = pid
        while result.count < limit, let next = parent(of: current), next > 1 {
            result.append(next)
            current = next
        }
        return result
    }
}

actor TerminalCommandRunner {
    static let timeout: TimeInterval = 3

    func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) {
            if process.isRunning { process.terminate() }
        }
        let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
