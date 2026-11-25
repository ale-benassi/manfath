import Foundation

/// Runs `/usr/sbin/lsof` and returns the parsed result. Uses absolute
/// path (no $PATH dependence) per ARCHITECTURE §1.
///
/// Errors from the subprocess are surfaced — the caller (PortScanner)
/// decides whether to retry, log, or surface to the UI.
public struct LsofPortSource: PortSource {

    public init() {}

    public func snapshot() async throws -> [PortInfo] {
        let result = try await Subprocess.run(
            path: "/usr/sbin/lsof",
            arguments: ["-iTCP", "-sTCP:LISTEN", "-nP", "-F", "pcLftPn"]
        )
        // lsof exits 1 when no files match (e.g. no listeners).
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw Failure.nonZeroExit(status: result.exitCode, stderr: result.stderr)
        }
        return LsofParser.parse(result.stdout, now: Date())
    }

    public enum Failure: Error {
        case nonZeroExit(status: Int32, stderr: String)
    }
}
