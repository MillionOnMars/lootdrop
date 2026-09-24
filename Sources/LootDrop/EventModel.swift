import Foundation
import SwiftUI

enum Rarity: String, Codable, CaseIterable {
    case common, rare, epic, legendary

    var color: Color {
        switch self {
        case .common:    return .gray
        case .rare:      return .blue
        case .epic:      return .purple
        case .legendary: return .orange
        }
    }
}

// Controls how the event presents itself
// - flash: sound + popover opens for 4 seconds then closes
// - persist: sound + popover opens and stays until user dismisses
// - silent: sound only, no popover
enum EventBehavior: String, Codable {
    case flash, persist, silent
}

struct LootEvent: Identifiable, Codable {
    let id: UUID
    let type: String
    let title: String
    let subtitle: String?
    let rarity: Rarity
    let source: String
    let pid: Int?
    let timestamp: Date
    let behavior: EventBehavior
    var viewed: Bool
    /// Optional routing hint. Absent means "focus the Ghostty window named by
    /// `source`", which is all this app could ever do before.
    var target: String?

    init(
        id: UUID = UUID(),
        type: String,
        title: String,
        subtitle: String? = nil,
        rarity: Rarity = .common,
        source: String = "",
        pid: Int? = nil,
        timestamp: Date = Date(),
        behavior: EventBehavior = .flash,
        viewed: Bool = false,
        target: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.rarity = rarity
        self.source = source
        self.pid = pid
        self.timestamp = timestamp
        self.behavior = behavior
        self.viewed = viewed
        self.target = target
    }
}

struct IncomingEvent: Codable {
    let type: String
    let title: String
    let subtitle: String?
    let rarity: String?
    let source: String?
    let pid: Int?
    let behavior: String?  // "flash", "persist", "silent"
    let target: String?        // where tapping should take you; see WindowFocuser
    let delaySeconds: Int?     // fire this many seconds from now instead of now

    func toLootEvent() -> LootEvent {
        LootEvent(
            type: type,
            title: title,
            subtitle: subtitle,
            rarity: Rarity(rawValue: rarity ?? "common") ?? .common,
            source: source ?? "",
            pid: pid,
            behavior: EventBehavior(rawValue: behavior ?? "flash") ?? .flash,
            target: target
        )
    }

}

/// An event held until its time comes. Persisted so a reminder survives a
/// restart of the app — a reminder that quietly evaporates is worse than none.
struct ScheduledEvent: Codable, Identifiable {
    let id: UUID
    let fireAt: Date
    let event: IncomingEvent

    init(id: UUID = UUID(), fireAt: Date, event: IncomingEvent) {
        self.id = id
        self.fireAt = fireAt
        self.event = event
    }
}
