import AVFoundation
import Foundation

struct SoundInfo: Identifiable, Hashable {
    let id: String          // unique key: "system:Hero" or "custom:DiabloRingDiscovery"
    let displayName: String // "Hero", "Diablo Ring Discovery"
    let url: URL
    let isSystem: Bool

    var category: String { isSystem ? "System" : "Custom" }
}

class SoundPlayer: ObservableObject {
    @Published var availableSounds: [SoundInfo] = []
    private var players: [String: AVAudioPlayer] = [:]
    private let systemDir = URL(fileURLWithPath: "/System/Library/Sounds")

    func reloadSounds(customDir: URL?) {
        var sounds: [SoundInfo] = []

        // System sounds
        if let files = try? FileManager.default.contentsOfDirectory(
            at: systemDir, includingPropertiesForKeys: nil
        ) {
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let ext = file.pathExtension.lowercased()
                guard ["aiff", "mp3", "wav", "m4a", "caf"].contains(ext) else { continue }
                let name = file.deletingPathExtension().lastPathComponent
                sounds.append(SoundInfo(
                    id: "system:\(name)",
                    displayName: name,
                    url: file,
                    isSystem: true
                ))
            }
        }

        // Custom sounds
        if let dir = customDir,
           FileManager.default.fileExists(atPath: dir.path),
           let files = try? FileManager.default.contentsOfDirectory(
               at: dir, includingPropertiesForKeys: nil
           ) {
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let ext = file.pathExtension.lowercased()
                guard ["aiff", "mp3", "wav", "m4a", "caf", "ogg"].contains(ext) else { continue }
                let name = file.deletingPathExtension().lastPathComponent
                // Pretty-print: replace underscores/camelCase with spaces
                let display = name
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(
                        of: "([a-z])([A-Z])",
                        with: "$1 $2",
                        options: .regularExpression
                    )
                sounds.append(SoundInfo(
                    id: "custom:\(name)",
                    displayName: display,
                    url: file,
                    isSystem: false
                ))
            }
        }

        availableSounds = sounds

        // Pre-load all players
        players.removeAll()
        for sound in sounds {
            do {
                let player = try AVAudioPlayer(contentsOf: sound.url)
                player.prepareToPlay()
                players[sound.id] = player
            } catch {
                print("LootDrop: Failed to load \(sound.displayName): \(error)")
            }
        }

        print("LootDrop: Loaded \(sounds.count) sounds (\(sounds.filter(\.isSystem).count) system, \(sounds.filter { !$0.isSystem }.count) custom)")
    }

    func play(id: String) {
        guard let player = players[id] else {
            // Fallback: try system Bottle
            players["system:Bottle"]?.stop()
            players["system:Bottle"]?.currentTime = 0
            players["system:Bottle"]?.play()
            return
        }
        player.stop()
        player.currentTime = 0
        player.play()
    }
}
