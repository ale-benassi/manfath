import Foundation

/// Short-lived commands owned by the app. Drain both pipes during execution
/// so a full pipe never prevents the child from exiting.
final class Subprocess: @unchecked Sendable {
    struct Output {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    enum Failure: Error {
        case timedOut
        case readFailed(Int32)
    }

    static func run(path: String, arguments: [String], timeout: TimeInterval = 2) async throws -> Output {
        let command = Subprocess(path: path, arguments: arguments, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { command.start($0) }
        } onCancel: {
            command.cancel()
        }
    }

    // Launch, pipe callbacks, timeout and cancellation share this queue.
    private let queue = DispatchQueue(label: "com.manfath.subprocess")
    private let process = Process()
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<Output, Error>?
    private var failure: Error?
    private var exitCode: Int32?
    private var stdout: String?
    private var stderr: String?
    private var channels: [DispatchIO] = []

    private init(path: String, arguments: [String], timeout: TimeInterval) {
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        self.timeout = timeout
    }

    private func start(_ continuation: CheckedContinuation<Output, Error>) {
        queue.async { [self] in
            if let failure = self.failure {
                continuation.resume(throwing: failure)
                return
            }
            let out = Pipe()
            let err = Pipe()
            self.process.standardOutput = out
            self.process.standardError = err
            self.process.terminationHandler = { [weak self] process in
                self?.recordExit(process.terminationStatus)
            }
            do {
                try self.process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            self.continuation = continuation
            self.read(out.fileHandleForReading, into: \.stdout)
            self.read(err.fileHandleForReading, into: \.stderr)
            self.queue.asyncAfter(deadline: .now() + self.timeout) { [weak self] in
                guard let self, self.continuation != nil else { return }
                self.fail(Failure.timedOut)
            }
        }
    }

    private func read(_ handle: FileHandle, into output: ReferenceWritableKeyPath<Subprocess, String?>) {
        let channel = DispatchIO(type: .stream, fileDescriptor: handle.fileDescriptor, queue: queue) { _ in
            try? handle.close()
        }
        channels.append(channel)
        var bytes = Data()
        channel.read(offset: 0, length: Int.max, queue: queue) { done, data, error in
            if let data { bytes.append(contentsOf: data) }
            guard done else { return }
            channel.close()
            self.channels.removeAll { $0 === channel }
            if error != 0 { self.fail(Failure.readFailed(error)) }
            self[keyPath: output] = String(data: bytes, encoding: .utf8) ?? ""
            self.finishIfReady()
        }
    }

    private func recordExit(_ status: Int32) {
        queue.async {
            self.exitCode = status
            self.finishIfReady()
        }
    }

    private func cancel() {
        queue.async { self.fail(CancellationError()) }
    }

    private func fail(_ error: Error) {
        guard failure == nil else { return }
        failure = error
        if continuation != nil, exitCode == nil, process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        for channel in channels { channel.close(flags: .stop) }
    }

    private func finishIfReady() {
        guard let continuation, let exitCode, let stdout, let stderr else { return }
        self.continuation = nil
        if let failure {
            continuation.resume(throwing: failure)
        } else {
            continuation.resume(returning: Output(exitCode: exitCode, stdout: stdout, stderr: stderr))
        }
    }
}
