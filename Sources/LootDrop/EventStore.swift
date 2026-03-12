import Foundation
import SwiftUI

class EventStore: ObservableObject {
    @Published var events: [LootEvent] = []

    private let storePath: URL

    var unviewedCount: Int {
        events.filter { !$0.viewed }.count
    }

    init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lootdrop")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        storePath = configDir.appendingPathComponent("history.json")
    }

    func load(retentionDays: Int) {
        guard FileManager.default.fileExists(atPath: storePath.path) else { return }
        do {
            let data = try Data(contentsOf: storePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var loaded = try decoder.decode([LootEvent].self, from: data)

            let ttl = TimeInterval(retentionDays * 24 * 60 * 60)
            let cutoff = Date().addingTimeInterval(-ttl)
            loaded = loaded.filter { $0.timestamp > cutoff }

            for i in loaded.indices {
                loaded[i].viewed = true
            }

            events = loaded
            print("LootDrop: Loaded \(events.count) events from history (\(retentionDays)-day retention)")
        } catch {
            print("LootDrop: Failed to load history: \(error)")
        }
    }

    func add(_ event: LootEvent) {
        events.insert(event, at: 0)
        if events.count > 500 {
            events = Array(events.prefix(500))
        }
        save()
    }

    func markAllViewed() {
        for i in events.indices {
            events[i].viewed = true
        }
        save()
    }

    func clear() {
        events.removeAll()
        save()
    }

    // MARK: - Markdown Export

    func exportToday() -> URL? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayEvents = events.filter { $0.timestamp >= today }

        guard !todayEvents.isEmpty else { return nil }

        // Group by source
        let grouped = Dictionary(grouping: todayEvents) { $0.source.isEmpty ? "general" : $0.source }
        let dateStr = ISO8601DateFormatter().string(from: today).prefix(10)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var md = "# LootDrop — \(dateStr)\n\n"
        md += "\(todayEvents.count) events across \(grouped.count) project\(grouped.count == 1 ? "" : "s")\n\n"

        for (source, events) in grouped.sorted(by: { $0.key < $1.key }) {
            md += "## \(source)\n\n"
            for event in events.reversed() {  // chronological order
                let time = timeFormatter.string(from: event.timestamp)
                let rarity = event.rarity != .common ? " [\(event.rarity.rawValue)]" : ""
                md += "- **\(time)** \(event.title)\(rarity)"
                if let sub = event.subtitle { md += " — \(sub)" }
                md += "\n"
            }
            md += "\n"
        }

        // Write to Downloads
        let downloadsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        let filePath = downloadsDir.appendingPathComponent("lootdrop-\(dateStr).md")

        do {
            try md.write(to: filePath, atomically: true, encoding: .utf8)
            print("LootDrop: Exported to \(filePath.path)")
            return filePath
        } catch {
            print("LootDrop: Export failed: \(error)")
            return nil
        }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(events)
            try data.write(to: storePath, options: .atomic)
        } catch {
            print("LootDrop: Failed to save history: \(error)")
        }
    }
}
