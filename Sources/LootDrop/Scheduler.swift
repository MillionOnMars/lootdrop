import Foundation

/// Holds events until their time comes.
///
/// Backed by a file rather than a timer alone, because the whole point of
/// "remind me in 20 minutes" is that you have stopped thinking about it: a
/// reminder lost to an app restart or a laptop sleep is worse than no reminder,
/// since you were counting on it. Overdue events fire on the next tick after
/// wake rather than being dropped.
final class Scheduler {
    private let path: URL
    private let onFire: (IncomingEvent) -> Void
    private var pending: [ScheduledEvent] = []
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.erikbethke.lootdrop.scheduler")

    init(onFire: @escaping (IncomingEvent) -> Void) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lootdrop")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appendingPathComponent("scheduled.json")
        self.onFire = onFire
    }

    var count: Int { queue.sync { pending.count } }

    var upcoming: [ScheduledEvent] {
        queue.sync { pending.sorted { $0.fireAt < $1.fireAt } }
    }

    func start() {
        load()
        // Polling beats a one-shot Timer per reminder: a Mac that sleeps
        // through the fire date still fires on the next tick after it wakes.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func schedule(_ event: IncomingEvent, fireAt: Date) {
        queue.sync {
            pending.append(ScheduledEvent(fireAt: fireAt, event: event))
            save()
        }
    }

    /// Drops every pending reminder. Returns how many were removed.
    @discardableResult
    func clear() -> Int {
        queue.sync {
            let n = pending.count
            pending.removeAll()
            save()
            return n
        }
    }

    private func tick() {
        let now = Date()
        let due: [ScheduledEvent] = queue.sync {
            let ready = pending.filter { $0.fireAt <= now }
            guard !ready.isEmpty else { return [] }
            let readyIDs = Set(ready.map(\.id))
            pending.removeAll { readyIDs.contains($0.id) }
            save()
            return ready
        }
        for item in due {
            DispatchQueue.main.async { self.onFire(item.event) }
        }
    }

    // MARK: - Persistence (always called on `queue`)

    private func load() {
        queue.sync {
            guard let data = try? Data(contentsOf: path),
                  let decoded = try? JSONDecoder().decode([ScheduledEvent].self, from: data)
            else { return }
            pending = decoded
            if !decoded.isEmpty {
                print("LootDrop: restored \(decoded.count) scheduled event(s)")
            }
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(pending).write(to: path, options: .atomic)
        } catch {
            print("LootDrop: failed to save scheduled events: \(error)")
        }
    }
}
