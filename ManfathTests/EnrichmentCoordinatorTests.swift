import XCTest
@testable import ManfathCore

final class EnrichmentCoordinatorTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func port(_ p: UInt16, pid: Int32 = 1000) -> PortInfo {
        PortInfo(
            port: p, pid: pid, processName: "n",
            user: "u", protocolKind: .ipv4, firstSeenAt: t0, enrichment: nil
        )
    }

    // MARK: - Fan-out

    func testFansOutToAllProvidersAndMerges() async {
        let a = FixedProvider(id: "a", value: Enrichment(framework: .nextjs))
        let b = FixedProvider(id: "b", value: Enrichment(projectName: "my-app"))
        let coord = EnrichmentCoordinator(providers: [a, b])

        let result = await coord.enrich(port(3000))
        XCTAssertEqual(result.framework, .nextjs)
        XCTAssertEqual(result.projectName, "my-app")
    }
}

struct FixedProvider: EnrichmentProvider {
    let id: String
    let value: Enrichment
    func enrich(_ port: PortInfo) async -> Enrichment { value }
}
