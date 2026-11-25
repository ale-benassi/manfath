import XCTest
@testable import ManfathCore

final class SubprocessTests: XCTestCase {
    func testDrainsLargeOutputFromBothPipes() async throws {
        let result = try await Subprocess.run(
            path: "/usr/bin/awk",
            arguments: [#"BEGIN { for (i = 0; i < 100000; i++) { printf "a"; printf "b" > "/dev/stderr" } }"#],
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, String(repeating: "a", count: 100000))
        XCTAssertEqual(result.stderr, String(repeating: "b", count: 100000))
    }

    func testTimeoutStopsRunningCommand() async throws {
        do {
            _ = try await Subprocess.run(path: "/bin/sleep", arguments: ["10"], timeout: 0.1)
            XCTFail("Expected the app to stop the child")
        } catch Subprocess.Failure.timedOut {
            // Expected.
        }
    }

    func testCancellationStopsRunningCommand() async throws {
        let command = Task {
            try await Subprocess.run(path: "/bin/sleep", arguments: ["10"], timeout: 5)
        }
        try await Task.sleep(for: .milliseconds(100))
        command.cancel()
        do {
            _ = try await command.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }
}
