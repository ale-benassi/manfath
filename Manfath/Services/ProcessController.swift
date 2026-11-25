import Foundation

/// Result of a kill attempt. Surfaced to the UI so it can show the right
/// message without prompting for sudo (per ARCHITECTURE §9).
public enum KillResult: Equatable, Sendable {
    case ok
    case requiresPrivileges     // EPERM — typically a root-owned process
    case notFound               // ESRCH — pid is already gone
    case failed(String)         // any other error
}

/// Metadata about a running process gathered via `lsof -p PID`.
public struct ProcessDetails: Equatable, Sendable {
    public let pid: Int32
    public let commandPath: String?
    public let workingDirectory: String?
    public let openFileCount: Int
}

/// Process management: kill signals, inspect via lsof. All shell-outs
/// use absolute paths per ARCHITECTURE §1.
public actor ProcessController {
    private struct Inspection {
        let task: Task<ProcessDetails, Error>
        var waiters: Set<UUID>
    }

    private let readDetails: @Sendable (Int32) async throws -> ProcessDetails
    private var inspections: [Int32: Inspection] = [:]

    public init() {
        readDetails = { try await Self.inspectProcess(pid: $0) }
    }

    init(readDetails: @escaping @Sendable (Int32) async throws -> ProcessDetails) {
        self.readDetails = readDetails
    }

    // MARK: - Kill

    public func kill(pid: Int32, signal: Int32 = SIGTERM) async -> KillResult {
        let args = ["-\(signal)", "\(pid)"]
        do {
            let result = try await Subprocess.run(
                path: "/bin/kill",
                arguments: args
            )
            if result.exitCode == 0 { return .ok }

            let stderr = result.stderr.lowercased()
            if stderr.contains("no such process") { return .notFound }
            if stderr.contains("operation not permitted") { return .requiresPrivileges }
            return .failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .failed(String(describing: error))
        }
    }

    // MARK: - Inspect

    public func inspect(pid: Int32) async throws -> ProcessDetails {
        try Task.checkCancellation()
        let waiter = UUID()
        let task: Task<ProcessDetails, Error>
        if let existing = inspections[pid]?.task {
            inspections[pid]?.waiters.insert(waiter)
            task = existing
        } else {
            task = Task { [readDetails] in try await readDetails(pid) }
            inspections[pid] = Inspection(task: task, waiters: [waiter])
        }

        // Several ports from the same process can arrive in one scan.
        // Keep inspecting while any of those ports still needs the result.
        return try await withTaskCancellationHandler {
            defer { finishInspection(pid: pid, waiter: waiter) }
            let details = try await task.value
            try Task.checkCancellation()
            return details
        } onCancel: {
            Task { await self.finishInspection(pid: pid, waiter: waiter) }
        }
    }

    private func finishInspection(pid: Int32, waiter: UUID) {
        guard inspections[pid]?.waiters.remove(waiter) != nil else { return }
        if inspections[pid]?.waiters.isEmpty == true {
            inspections.removeValue(forKey: pid)?.task.cancel()
        }
    }

    private static func inspectProcess(pid: Int32) async throws -> ProcessDetails {
        let result = try await Subprocess.run(
            path: "/usr/sbin/lsof",
            arguments: ["-p", "\(pid)", "-Fnct"],
            timeout: 5
        )
        // lsof returns 1 when it finds no matching files for a pid;
        // treat as "process has no files" rather than an error.
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw InspectError.lsofFailed(status: result.exitCode, stderr: result.stderr)
        }

        return Self.parseInspectOutput(result.stdout, pid: pid)
    }

    public enum InspectError: Error {
        case lsofFailed(status: Int32, stderr: String)
    }

    /// Parse `lsof -p PID -Fnct` output. We look for:
    /// - Command path: the `cwd` (current working directory) and `txt`
    ///   (text/executable) records carry name fields.
    /// - File count: number of `f` records (file descriptors).
    static func parseInspectOutput(_ output: String, pid: Int32) -> ProcessDetails {
        var commandPath: String?
        var workingDirectory: String?
        var fileCount = 0

        var currentFd: String?
        var currentType: String?

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard let first = line.first else { continue }
            let value = String(line.dropFirst())

            switch first {
            case "f":
                fileCount += 1
                currentFd = value
                currentType = nil
            case "t":
                currentType = value
            case "n":
                if currentFd == "cwd" {
                    workingDirectory = value
                } else if currentFd == "txt" && commandPath == nil {
                    // First txt record is typically the main executable.
                    commandPath = value
                }
            default:
                break
            }
            _ = currentType   // reserved for future use
        }

        return ProcessDetails(
            pid: pid,
            commandPath: commandPath,
            workingDirectory: workingDirectory,
            openFileCount: fileCount
        )
    }

}
