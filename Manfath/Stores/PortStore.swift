import Foundation
import Observation

/// SwiftUI-facing source of truth for the list of ports.
///
/// Bridges the `PortScanner` actor (background) to SwiftUI (main actor).
/// Views read `filteredPorts` and write `searchText` / `sortMode`.
@MainActor @Observable
public final class PortStore {

    public private(set) var ports: [PortInfo] = [] {
        didSet { filteredCache = nil }
    }
    public private(set) var lastRefreshAt: Date?

    /// Primary IPv4 on the LAN (Wi-Fi or Ethernet), refreshed
    /// periodically so mobile-test URLs stay valid across network
    /// changes. `nil` when off-network.
    public private(set) var lanIPv4: String?

    public var searchText: String = ""
    public var sortMode: SortMode = .portAscending

    public let scanner: PortScanner
    public let settings: SettingsStore
    public let processController: ProcessController
    public let enrichmentCoordinator: EnrichmentCoordinator?

    /// Transient banner shown briefly at the top of the popover.
    /// Cleared automatically after a few seconds.
    public private(set) var errorBanner: String?
    public private(set) var bannerKind: BannerKind = .error
    private var errorClearTask: Task<Void, Never>?

    @ObservationIgnored private var subscriptionTask: Task<Void, Never>?
    @ObservationIgnored private var scanConfigurationTask: Task<Void, Never>?
    @ObservationIgnored private var scanSession: UUID?
    @ObservationIgnored private var enrichmentTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var portIndices: [String: Int] = [:]
    @ObservationIgnored private var lanRefreshTask: Task<Void, Never>?

    public init(
        scanner: PortScanner,
        settings: SettingsStore,
        processController: ProcessController = ProcessController(),
        enrichmentCoordinator: EnrichmentCoordinator? = nil
    ) {
        self.scanner = scanner
        self.settings = settings
        self.processController = processController
        self.enrichmentCoordinator = enrichmentCoordinator
    }

    /// Start the scan loop and subscribe to snapshots. Idempotent.
    /// Reads `settings.refreshInterval` and reacts to changes.
    public func start() {
        guard subscriptionTask == nil else { return }

        let session = UUID()
        scanSession = session
        subscriptionTask = Task { [weak self, scanner] in
            let stream = await scanner.updates()
            for await update in stream {
                guard let self, self.scanSession == session else { return }
                if let changed = update.changedPorts { self.receive(changed) }
                self.lastRefreshAt = update.completedAt
            }
        }

        trackRefreshInterval(session: session)
        startLANRefresh()
    }

    /// Re-arms on every `settings.refreshInterval` change and restarts
    /// the scanner with the new cadence. `.manual` stops the auto loop.
    private func trackRefreshInterval(session: UUID) {
        guard scanSession == session else { return }
        let interval = withObservationTracking {
            settings.refreshInterval
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.trackRefreshInterval(session: session)
            }
        }
        let previous = scanConfigurationTask
        previous?.cancel()
        scanConfigurationTask = Task { [scanner] in
            await previous?.value
            await scanner.start(interval: interval.isAutomatic ? interval.duration : nil)
        }
    }

    /// Stop the scan loop and cancel the subscription. Idempotent.
    public func stop() {
        guard let subscriptionTask else { return }
        scanSession = nil
        subscriptionTask.cancel()
        self.subscriptionTask = nil
        for task in enrichmentTasks.values { task.cancel() }
        enrichmentTasks.removeAll()
        lanRefreshTask?.cancel()
        lanRefreshTask = nil
        let previous = scanConfigurationTask
        previous?.cancel()
        scanConfigurationTask = Task { [scanner] in
            await previous?.value
            await scanner.stop()
        }
    }

    private func startLANRefresh() {
        lanIPv4 = LANAddressService.primaryIPv4()
        lanRefreshTask?.cancel()
        lanRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                let next = LANAddressService.primaryIPv4()
                if self?.lanIPv4 != next { self?.lanIPv4 = next }
            }
        }
    }

    /// Force an immediate scan without waiting for the next tick.
    public func refreshNow() async {
        await scanConfigurationTask?.value
        await scanner.refreshNow()
    }

    /// Entry point for incoming snapshots. Internal so tests can drive
    /// it directly without spinning up an actual scanner subscription.
    ///
    /// Preserves enrichment across scans by merging in previously known
    /// enrichments (the scanner's source returns `enrichment: nil`
    /// every tick). Ports that arrive without enrichment are dispatched
    /// to the coordinator for lookup.
    func receive(_ snapshot: [PortInfo]) {
        let merged = snapshot.map { new -> PortInfo in
            if new.enrichment == nil, let index = portIndices[new.id],
               ports[index].firstSeenAt == new.firstSeenAt, let enrichment = ports[index].enrichment {
                var out = new
                out.enrichment = enrichment
                return out
            }
            return new
        }

        let nextIndices = Dictionary(uniqueKeysWithValues: merged.enumerated().map { ($1.id, $0) })
        for (id, task) in enrichmentTasks {
            if let old = portIndices[id], let next = nextIndices[id],
               ports[old].firstSeenAt == merged[next].firstSeenAt, merged[next].enrichment == nil {
                continue
            }
            task.cancel()
            enrichmentTasks[id] = nil
        }
        portIndices = nextIndices
        if ports != merged { ports = merged }

        guard let coordinator = enrichmentCoordinator else { return }
        for port in merged where port.enrichment == nil && enrichmentTasks[port.id] == nil {
            let id = port.id
            enrichmentTasks[id] = Task { [weak self] in
                guard !Task.isCancelled else { return }
                let enrichment = await coordinator.enrich(port)
                guard !Task.isCancelled, let self else { return }
                self.enrichmentTasks[id] = nil
                self.applyEnrichment(id: id, enrichment: enrichment)
            }
        }
    }

    func applyEnrichment(id: String, enrichment: Enrichment) {
        guard let index = portIndices[id], ports[index].enrichment != enrichment else { return }
        ports[index].enrichment = enrichment
    }

    // MARK: - Row actions

    public func openInBrowser(port: UInt16) {
        BrowserService.openLocalhost(port: port)
    }

    public func copyAddress(port: UInt16) {
        PasteboardService.copy("localhost:\(port)")
    }

    public func kill(pid: Int32) async {
        let result = await processController.kill(pid: pid)
        switch result {
        case .ok:
            // Next scan will drop the row; no UI feedback needed here.
            break
        case .requiresPrivileges:
            showError(String(localized: "kill.requiresPrivileges"))
        case .notFound:
            showError(String(localized: "kill.notFound"))
        case .failed(let msg):
            showError(String(localized: "kill.failed \(msg)"))
        }
    }

    private func showError(_ message: String) {
        bannerKind = .error
        errorBanner = message
        scheduleBannerClear()
    }

    /// Surface a transient banner — colour adapts to `kind` (info, hint
    /// → blue/amber; success → cyan; error → red). Lets cross-cutting UI
    /// (tunnel start, install hints, etc.) report a one-line note
    /// without owning its own banner state.
    public func flashBanner(_ message: String, kind: BannerKind = .info) {
        bannerKind = kind
        errorBanner = message
        scheduleBannerClear()
    }

    private func scheduleBannerClear() {
        errorClearTask?.cancel()
        errorClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run { self?.errorBanner = nil }
        }
    }

    // MARK: - Derived view state

    private struct FilterInputs: Equatable {
        let blocklist: [String]
        let minPort: UInt16
        let maxPort: UInt16
        let realOnly: Bool
        let groups: [PortGroup]
        let query: String
        let sort: SortMode
    }

    private struct FilteredCache {
        let inputs: FilterInputs
        let ports: [PortInfo]
        var sections: [PortSection]?
    }

    @ObservationIgnored private var filteredCache: FilteredCache?

    /// Filter order per ARCHITECTURE §7: blocklist → port range →
    /// real-server filter → search text → sort.
    public var filteredPorts: [PortInfo] {
        // Read all observable inputs even on a cache hit. The popover
        // and menu bar badge each track their own reads.
        let snapshot = ports
        let inputs = FilterInputs(
            blocklist: settings.processBlocklist,
            minPort: settings.minPort,
            maxPort: settings.maxPort,
            realOnly: settings.showOnlyRealServers,
            groups: settings.portGroups,
            query: searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            sort: sortMode
        )
        if let cached = filteredCache, cached.inputs == inputs { return cached.ports }

        let blocklist = Set(inputs.blocklist.map { $0.lowercased() })
        let query = inputs.query
        let filtered = snapshot.filter { port in
            guard !blocklist.contains(port.processName.lowercased()) else { return false }
            // Hide non-real-server categories when the filter is on.
            // We give an as-yet-unenriched port the benefit of the doubt
            // so it doesn't blink in and out as enrichment lands.
            let inRange = port.port >= inputs.minPort && port.port <= inputs.maxPort
            let passesCategory = !inputs.realOnly || port.enrichment?.category?.isRealServer != false
            if !inRange || !passesCategory {
                // Pinned groups override the range and server filter.
                guard inputs.groups.contains(where: { $0.contains(port.port) }) else { return false }
            }
            if query.isEmpty { return true }
            return String(port.port).contains(query)
                || port.processName.lowercased().contains(query)
                || String(port.pid).contains(query)
                || port.enrichment?.framework?.rowLabel?.lowercased().contains(query) == true
                || port.enrichment?.projectName?.lowercased().contains(query) == true
        }

        let sorted = filtered.sorted(by: comparator(for: inputs.sort))
        filteredCache = FilteredCache(inputs: inputs, ports: sorted)
        return sorted
    }

    /// Sections in render order: pinned groups first, then auto
    /// `ProcessCategory` buckets. Each port appears in **exactly one**
    /// section — when multiple groups list the same port (e.g. both
    /// `preset.nextjs` and `preset.react` claim 3000), we disambiguate
    /// by the detected framework. If no framework hint is available
    /// the first matching group in the user's defined order wins.
    public var sectionedPorts: [PortSection] {
        let filtered = filteredPorts
        if let cached = filteredCache?.sections { return cached }
        let groups = settings.portGroups
        var sections: [PortSection] = []
        var groupBuckets: [UUID: [PortInfo]] = [:]
        var buckets: [ProcessCategory: [PortInfo]] = [:]

        for port in filtered {
            if let group = Self.bestGroup(for: port, candidates: groups) {
                groupBuckets[group.id, default: []].append(port)
            } else {
                let category = port.enrichment?.category ?? .unknown
                buckets[category, default: []].append(port)
            }
        }

        // Render groups in user-defined order, skipping empties.
        for group in groups {
            if let portsInGroup = groupBuckets[group.id], !portsInGroup.isEmpty {
                sections.append(.group(group: group, ports: portsInGroup))
            }
        }

        for cat in ProcessCategory.allCases {
            if let portsInCat = buckets[cat], !portsInCat.isEmpty {
                sections.append(.category(category: cat, ports: portsInCat))
            }
        }
        filteredCache?.sections = sections
        return sections
    }

    /// Pick the single group a port belongs in. When multiple groups
    /// list the same port, prefer the one whose `presetId` matches the
    /// detected framework; otherwise fall through to user order.
    static func bestGroup(for port: PortInfo, candidates: [PortGroup]) -> PortGroup? {
        let expected = port.enrichment?.framework.flatMap(presetId(for:))
        var first: PortGroup?
        for group in candidates where group.contains(port.port) {
            if let expected, group.presetId == expected { return group }
            if first == nil { first = group }
        }
        return first
    }

    /// Map a `FrameworkHint` to the matching preset id from
    /// `PresetGroups.all`. Used to break ties when multiple groups
    /// claim the same port.
    private static func presetId(for hint: FrameworkHint) -> String? {
        switch hint {
        case .nextjs:                   return "preset.nextjs"
        case .vite:                     return "preset.vite"
        case .cra:                      return "preset.react"
        case .rails:                    return "preset.rails"
        case .django:                   return "preset.django"
        case .flask:                    return "preset.flask"
        case .express:                  return "preset.express"
        case .spring:                   return "preset.spring"
        case .rustRocket, .rustActix:   return "preset.actix"
        case .goStdlib:                 return "preset.gohttp"
        case .nuxt:                     return "preset.nuxt"      // not in catalog yet
        case .astro:                    return "preset.astro"
        case .svelte:                   return "preset.svelte"
        case .remix:                    return "preset.remix"
        case .unknown:                  return nil
        }
    }

    /// Real-server count for the optional badge / settings counter.
    /// Counts only categories where `isRealServer == true`.
    public var realServerCount: Int {
        filteredPorts.reduce(into: 0) { count, port in
            if port.enrichment?.category?.isRealServer == true { count += 1 }
        }
    }

    private func comparator(for mode: SortMode) -> (PortInfo, PortInfo) -> Bool {
        switch mode {
        case .portAscending:
            return { $0.port < $1.port }
        case .portDescending:
            return { $0.port > $1.port }
        case .processName:
            return {
                $0.processName.localizedCaseInsensitiveCompare($1.processName)
                    == .orderedAscending
            }
        case .firstSeenDescending:
            return { $0.firstSeenAt > $1.firstSeenAt }
        }
    }
}

public enum SortMode: String, CaseIterable, Sendable {
    case portAscending
    case portDescending
    case processName
    case firstSeenDescending
}

/// Visual tone for transient banners. View layer maps each case to a
/// colour palette; logic layer just tags meaning.
public enum BannerKind: Sendable {
    case info       // generic note — neutral / amber
    case success    // tunnel ready, copy succeeded — cyan
    case error      // kill failed, install missing — danger red
}

/// One section in the popover's sections-view. Either a user-pinned
/// `PortGroup` or an auto-classified `ProcessCategory`. Identifiable so
/// SwiftUI's ForEach can diff cleanly across re-renders.
public enum PortSection: Identifiable, Sendable {
    case group(group: PortGroup, ports: [PortInfo])
    case category(category: ProcessCategory, ports: [PortInfo])

    public var id: String {
        switch self {
        case .group(let g, _):    return "group-\(g.id.uuidString)"
        case .category(let c, _): return "cat-\(c.rawValue)"
        }
    }

    public var ports: [PortInfo] {
        switch self {
        case .group(_, let p), .category(_, let p): return p
        }
    }

    /// True for `.group` sections — used by the view to render a pin
    /// affordance in the section header.
    public var isPinned: Bool {
        if case .group = self { return true }
        return false
    }

    /// `LocalizedStringKey` for category sections (so they translate),
    /// or the raw user-typed group name for pinned groups.
    public var titleKey: String {
        switch self {
        case .group(let g, _):    return g.name
        case .category(let c, _): return c.rawValue   // resolves via category.<rawValue>
        }
    }
}
