import Foundation

struct BehaviorSoundConfig: Codable {
    var primarySound: String
    var rareSound: String
    var rareChancePercent: Int  // 0-100, chance to play rare instead of primary

    func rollSound() -> String {
        if rareChancePercent > 0 && Int.random(in: 1...100) <= rareChancePercent {
            return rareSound
        }
        return primarySound
    }
}

struct LootDropSettings: Codable {
    var flash: BehaviorSoundConfig   // done/completed
    var persist: BehaviorSoundConfig // waiting for input
    var silent: BehaviorSoundConfig  // compaction/background

    var retentionDays: Int           // how many days to keep events
    var port: Int                    // HTTP server port
    var customSoundsDir: String?     // optional custom sounds directory
    var driftMinutes: Int            // minutes before "forgotten session" alert

    // Optional so that a settings.json written by an older build still decodes.
    // A non-optional addition would throw, silently resetting every tuned sound
    // back to defaults.
    var doNotDisturbUntil: Date?     // nil = never muted; past date = expired

    static let `default` = LootDropSettings(
        flash: BehaviorSoundConfig(
            primarySound: "system:Bottle",
            rareSound: "system:Glass",
            rareChancePercent: 10
        ),
        persist: BehaviorSoundConfig(
            primarySound: "system:Hero",
            rareSound: "system:Funk",
            rareChancePercent: 10
        ),
        silent: BehaviorSoundConfig(
            primarySound: "system:Bottle",
            rareSound: "system:Submarine",
            rareChancePercent: 10
        ),
        retentionDays: 7,
        port: 7777,
        customSoundsDir: nil,
        driftMinutes: 20,
        doNotDisturbUntil: nil
    )

    /// True while notifications should make no sound and open no popover.
    var isDoNotDisturbActive: Bool {
        guard let until = doNotDisturbUntil else { return false }
        return until > Date()
    }

    /// `nil` minutes means indefinitely; `0` or negative clears it.
    mutating func setDoNotDisturb(minutes: Int?) {
        if let minutes {
            doNotDisturbUntil = minutes > 0 ? Date().addingTimeInterval(Double(minutes) * 60) : nil
        } else {
            doNotDisturbUntil = .distantFuture
        }
    }

    func config(for behavior: EventBehavior) -> BehaviorSoundConfig {
        switch behavior {
        case .flash:   return flash
        case .persist: return persist
        case .silent:  return silent
        }
    }

    var customSoundsDirURL: URL? {
        guard let dir = customSoundsDir, !dir.isEmpty else { return nil }
        let expanded = NSString(string: dir).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
}

class SettingsStore: ObservableObject {
    @Published var settings: LootDropSettings

    private let configPath: URL

    init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lootdrop")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        configPath = configDir.appendingPathComponent("settings.json")

        if FileManager.default.fileExists(atPath: configPath.path),
           let data = try? Data(contentsOf: configPath),
           let loaded = try? JSONDecoder().decode(LootDropSettings.self, from: data) {
            settings = loaded
            print("LootDrop: Loaded settings from \(configPath.path)")
        } else {
            settings = .default
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: configPath, options: .atomic)
        } catch {
            print("LootDrop: Failed to save settings: \(error)")
        }
    }
}
