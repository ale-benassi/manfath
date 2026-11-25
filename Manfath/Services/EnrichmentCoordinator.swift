import Foundation

/// Runs the independent providers in parallel for one port. PortStore
/// retains the result and owns the lifetime of the request.
public struct EnrichmentCoordinator: Sendable {

    private let providers: [any EnrichmentProvider]

    public init(providers: [any EnrichmentProvider]) {
        self.providers = providers
    }

    public func enrich(_ port: PortInfo) async -> Enrichment {
        var merged = await withTaskGroup(of: Enrichment.self) { group in
            for provider in providers {
                _ = group.addTaskUnlessCancelled { await provider.enrich(port) }
            }
            var acc = Enrichment()
            for await partial in group {
                acc.merge(partial)
            }
            return acc
        }
        // Once every provider has reported, we know enough to bucket
        // the port into a category. Doing it here (rather than in a
        // provider) keeps the decision in one place.
        merged.category = CategoryClassifier.classify(
            processName: port.processName,
            executablePath: merged.commandPath,
            framework: merged.framework
        )
        return merged
    }
}
