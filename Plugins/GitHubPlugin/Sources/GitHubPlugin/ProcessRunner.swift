import Foundation
import Synchronization

struct CommandResult: Sendable, Equatable {
    var status: Int32
    var output: Data
    var errorOutput: Data
}

enum CommandError: Error {
    case timedOut
}

protocol CommandRunning: Sendable {
    func run(_ executable: URL, arguments: [String], timeout: Duration) async throws -> CommandResult
}

struct ProcessRunner: CommandRunning {
    static let killGracePeriod: Duration = .seconds(2)
    static let outputGracePeriod: Duration = .seconds(1)

    func run(_ executable: URL, arguments: [String], timeout: Duration) async throws -> CommandResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "NO_COLOR": "1"]) { _, new in new }
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let (exits, exited) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { process in
            exited.yield(process.terminationStatus)
            exited.finish()
        }
        let output = OutputCollector(outputPipe.fileHandleForReading)
        let errors = OutputCollector(errorPipe.fileHandleForReading)
        do {
            try process.run()
        } catch {
            output.stop()
            errors.stop()
            throw error
        }

        let watchdog = Task {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return false
            }
            Self.stop(process)
            return true
        }
        return try await withTaskCancellationHandler {
            var status: Int32 = -1
            for await exitStatus in exits {
                status = exitStatus
            }
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await output.finished()
                    await errors.finished()
                }
                group.addTask {
                    try? await Task.sleep(for: Self.outputGracePeriod)
                }
                await group.next()
                group.cancelAll()
            }
            output.stop()
            errors.stop()
            watchdog.cancel()
            if await watchdog.value { throw CommandError.timedOut }
            try Task.checkCancellation()
            return CommandResult(status: status, output: output.data, errorOutput: errors.data)
        } onCancel: {
            Self.stop(process)
        }
    }

    private static func stop(_ process: Process) {
        process.terminate()
        Task {
            try? await Task.sleep(for: killGracePeriod)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}

private final class OutputCollector: Sendable {
    private let handle: FileHandle
    private let buffer = Mutex(Data())
    private let done: AsyncStream<Void>
    private let finish: AsyncStream<Void>.Continuation

    init(_ handle: FileHandle) {
        self.handle = handle
        (done, finish) = AsyncStream<Void>.makeStream()
        handle.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                stop()
            } else {
                buffer.withLock { $0.append(chunk) }
            }
        }
    }

    var data: Data {
        buffer.withLock { $0 }
    }

    func finished() async {
        for await _ in done {}
    }

    func stop() {
        handle.readabilityHandler = nil
        finish.finish()
    }
}
