import Foundation

/// Owns the scan loop. On each tick:
///
/// 1. Asks the `PortSource` for the current set of ports.
/// 2. Preserves `firstSeenAt` and `enrichment` for ports already known.
/// 3. Reports successful completion. Sends rows only when they changed.
public actor PortScanner {

    private let source: any PortSource
    private var lastPorts: [PortInfo] = []
    private var lastById: [String: PortInfo] = [:]
    private var lastScanAt: Date?
    private var loopTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var continuation: AsyncStream<ScanUpdate>.Continuation?

    // Observation hooks for tests. Not part of the public contract.
    private(set) var emissionCount: Int = 0
    var currentPorts: [PortInfo] { lastPorts }

    public init(source: any PortSource) {
        self.source = source
    }

    /// PortStore owns the single subscription. Replay the current state
    /// so subscribing after an early refresh or after stop/start is safe.
    func updates() -> AsyncStream<ScanUpdate> {
        let (stream, next) = AsyncStream<ScanUpdate>.makeStream()
        guard !Task.isCancelled else {
            next.finish()
            return stream
        }
        continuation?.finish()
        continuation = next
        if let lastScanAt {
            next.yield(ScanUpdate(completedAt: lastScanAt, changedPorts: lastPorts))
        }
        return stream
    }

    /// Start a recurring loop, or switch to manual scanning with nil.
    public func start(interval: Duration?) {
        guard !Task.isCancelled else { return }
        if interval == nil, loopTask == nil { return }
        if loopTask != nil { stop() }
        guard let interval, interval > .zero else { return }
        loopTask = Task { [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.refreshNow()
                deadline += interval
                let now = clock.now
                // A slow scan or sleep/wake can miss a tick. Skip catch-up scans.
                if deadline <= now { deadline = now + interval }
                try? await clock.sleep(until: deadline, tolerance: .milliseconds(10))
            }
        }
    }

    /// Stop polling and cancel the active scan. Safe to call multiple times.
    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        scanTask?.cancel()
    }

    /// Start a scan immediately, or wait for the scan already in progress.
    public func refreshNow() async {
        while !Task.isCancelled {
            if let scanTask {
                await scanTask.value
                if !scanTask.isCancelled { return }
                continue
            }

            let next = Task {
                await tick()
                scanTask = nil
            }
            scanTask = next
            await next.value
            return
        }
    }

    private func tick() async {
        do {
            let raw = try await source.snapshot()
            try Task.checkCancellation()
            let completedAt = Date()
            let merged = merge(newPorts: raw)
            let changed = merged != lastPorts
            if changed {
                lastPorts = merged
                lastById = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
                emissionCount += 1
            }
            lastScanAt = completedAt
            continuation?.yield(ScanUpdate(completedAt: completedAt, changedPorts: changed ? merged : nil))
        } catch {
            // Scan failures are non-fatal. Log (when Logger is wired) and
            // skip this tick — next tick retries.
        }
    }

    /// For each port in `newPorts`, if we've seen the same id before,
    /// copy `firstSeenAt` and `enrichment` forward. Otherwise use what
    /// the source gave us.
    private func merge(newPorts: [PortInfo]) -> [PortInfo] {
        newPorts.map { port in
            guard let existing = lastById[port.id] else { return port }
            return PortInfo(
                port: port.port,
                pid: port.pid,
                processName: port.processName,
                user: port.user,
                protocolKind: port.protocolKind,
                firstSeenAt: existing.firstSeenAt,
                enrichment: existing.enrichment
            )
        }
    }

    deinit {
        loopTask?.cancel()
        continuation?.finish()
    }
}

struct ScanUpdate: Sendable {
    let completedAt: Date
    let changedPorts: [PortInfo]?
}
