import SwiftUI

struct ContentView: View {
    @ObservedObject var store: EventStore
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var soundPlayer: SoundPlayer
    @ObservedObject var appState: AppState
    var onEventTapped: ((LootEvent) -> Void)?
    var onToggleDND: (() -> Void)?

    @State private var exportMessage: String?

    // Lives on AppState, not @State: this view is hosted once and reused for
    // the life of the app, so a @State flag here would survive every popover
    // close and greet the next alert with the settings pane.
    private var showSettings: Bool { appState.showSettings }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(.orange)
                Text("LootDrop")
                    .font(.headline)
                Spacer()
                if !showSettings {
                    if !store.events.isEmpty {
                        Button {
                            if let url = store.exportToday() {
                                exportMessage = "Saved to ~/Downloads/\(url.lastPathComponent)"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    exportMessage = nil
                                }
                            } else {
                                exportMessage = "No events today"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    exportMessage = nil
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .help("Export today as markdown")

                        Button("Clear") {
                            store.clear()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                Button {
                    onToggleDND?()
                } label: {
                    Image(systemName: settingsStore.settings.isDoNotDisturbActive
                          ? "moon.zzz.fill" : "moon")
                        .foregroundColor(settingsStore.settings.isDoNotDisturbActive
                                         ? .purple : .secondary)
                }
                .buttonStyle(.plain)
                .help(settingsStore.settings.isDoNotDisturbActive
                      ? "Do Not Disturb is on — click to resume"
                      : "Do Not Disturb: silence sounds and popovers")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.showSettings.toggle()
                    }
                } label: {
                    Image(systemName: showSettings ? "xmark.circle.fill" : "gearshape.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Export confirmation banner
            if let msg = exportMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(msg)
                        .font(.caption)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.1))
            }

            if settingsStore.settings.isDoNotDisturbActive {
                HStack(spacing: 5) {
                    Image(systemName: "moon.zzz.fill")
                    Text(dndBannerText)
                }
                .font(.caption)
                .foregroundColor(.purple)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color.purple.opacity(0.12))
            }

            Divider()

            if showSettings {
                SettingsView(
                    settingsStore: settingsStore,
                    soundPlayer: soundPlayer
                )
            } else if store.events.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "eye.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No loot yet...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("curl -X POST localhost:7777/event")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.events) { event in
                            Button {
                                onEventTapped?(event)
                            } label: {
                                EventRow(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 340, height: 420)
        .onAppear {
            store.markAllViewed()
        }
    }

    private var dndBannerText: String {
        guard let until = settingsStore.settings.doNotDisturbUntil else { return "" }
        if until == .distantFuture { return "Do Not Disturb — until you turn it off" }
        let minutes = max(1, Int(until.timeIntervalSinceNow / 60))
        return "Do Not Disturb — \(minutes)m left"
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var soundPlayer: SoundPlayer

    @State private var customDirText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // Sound Assignments
                Text("Sound Assignments")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                BehaviorSoundEditor(
                    label: "Task Complete",
                    description: "Flash open 4s, then close",
                    icon: "checkmark.circle.fill",
                    iconColor: .blue,
                    config: $settingsStore.settings.flash,
                    sounds: soundPlayer.availableSounds,
                    onPreview: { soundPlayer.play(id: $0) },
                    onChanged: { settingsStore.save() }
                )

                BehaviorSoundEditor(
                    label: "Needs Input",
                    description: "Opens and stays until dismissed",
                    icon: "hand.raised.fill",
                    iconColor: .purple,
                    config: $settingsStore.settings.persist,
                    sounds: soundPlayer.availableSounds,
                    onPreview: { soundPlayer.play(id: $0) },
                    onChanged: { settingsStore.save() }
                )

                BehaviorSoundEditor(
                    label: "Background Event",
                    description: "Sound only, no popup",
                    icon: "diamond.fill",
                    iconColor: .orange,
                    config: $settingsStore.settings.silent,
                    sounds: soundPlayer.availableSounds,
                    onPreview: { soundPlayer.play(id: $0) },
                    onChanged: { settingsStore.save() }
                )

                Divider().padding(.horizontal, 12)

                // General Settings
                Text("General")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)

                // Retention
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Text("Keep events for")
                    Picker("", selection: $settingsStore.settings.retentionDays) {
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                .font(.system(.caption))
                .padding(.horizontal, 12)
                .onChange(of: settingsStore.settings.retentionDays) { _ in
                    settingsStore.save()
                }

                // Port
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Text("Listen port")
                    TextField("7777", value: $settingsStore.settings.port, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("(restart required)")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .font(.system(.caption))
                .padding(.horizontal, 12)
                .onChange(of: settingsStore.settings.port) { _ in
                    settingsStore.save()
                }

                // Drift detector
                HStack {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    Text("Remind after")
                    Picker("", selection: $settingsStore.settings.driftMinutes) {
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("20 min").tag(20)
                        Text("30 min").tag(30)
                        Text("Off").tag(0)
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
                .font(.system(.caption))
                .padding(.horizontal, 12)
                .onChange(of: settingsStore.settings.driftMinutes) { _ in
                    settingsStore.save()
                }

                Divider().padding(.horizontal, 12)

                // Custom sounds directory
                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom Sounds Folder")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 6) {
                        TextField("~/path/to/sounds", text: $customDirText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))

                        Button("Set") {
                            let trimmed = customDirText.trimmingCharacters(in: .whitespaces)
                            settingsStore.settings.customSoundsDir = trimmed.isEmpty ? nil : trimmed
                            settingsStore.save()
                            soundPlayer.reloadSounds(customDir: settingsStore.settings.customSoundsDirURL)
                        }
                        .font(.caption)

                        Button {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                customDirText = url.path
                                settingsStore.settings.customSoundsDir = url.path
                                settingsStore.save()
                                soundPlayer.reloadSounds(customDir: url)
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }

                    let customCount = soundPlayer.availableSounds.filter { !$0.isSystem }.count
                    if customCount > 0 {
                        Text("\(customCount) custom sound\(customCount == 1 ? "" : "s") loaded")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else if settingsStore.settings.customSoundsDir != nil {
                        Text("No audio files found in that folder")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else {
                        Text("Add .mp3, .aiff, or .wav files to a folder")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            customDirText = settingsStore.settings.customSoundsDir ?? ""
        }
    }
}

// MARK: - Behavior Sound Editor (primary + rare + chance)

struct BehaviorSoundEditor: View {
    let label: String
    let description: String
    let icon: String
    let iconColor: Color
    @Binding var config: BehaviorSoundConfig
    let sounds: [SoundInfo]
    var onPreview: ((String) -> Void)?
    var onChanged: (() -> Void)?

    private var systemSounds: [SoundInfo] { sounds.filter(\.isSystem) }
    private var customSounds: [SoundInfo] { sounds.filter { !$0.isSystem } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(.body, weight: .medium))
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Primary sound
            HStack(spacing: 6) {
                Text("Primary")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 45, alignment: .trailing)
                soundPicker(selection: $config.primarySound)
                previewButton(config.primarySound)
            }

            // Rare sound + chance
            HStack(spacing: 6) {
                Text("Rare")
                    .font(.caption2)
                    .foregroundColor(.orange.opacity(0.8))
                    .frame(width: 45, alignment: .trailing)
                soundPicker(selection: $config.rareSound)
                previewButton(config.rareSound)
                Picker("", selection: $config.rareChancePercent) {
                    Text("5%").tag(5)
                    Text("10%").tag(10)
                    Text("20%").tag(20)
                    Text("Off").tag(0)
                }
                .labelsHidden()
                .frame(width: 60)
                .onChange(of: config.rareChancePercent) { _ in onChanged?() }
            }
        }
        .padding(.horizontal, 12)
    }

    private func soundPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            Section("System") {
                ForEach(systemSounds) { sound in
                    Text(sound.displayName).tag(sound.id)
                }
            }
            if !customSounds.isEmpty {
                Section("Custom") {
                    ForEach(customSounds) { sound in
                        Text(sound.displayName).tag(sound.id)
                    }
                }
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .onChange(of: selection.wrappedValue) { _ in onChanged?() }
    }

    private func previewButton(_ soundId: String) -> some View {
        Button {
            onPreview?(soundId)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.caption2)
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: LootEvent

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(event.rarity.color)
                .frame(width: 10, height: 10)
                .shadow(color: event.rarity == .legendary ? .orange.opacity(0.8) : .clear, radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let subtitle = event.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !event.source.isEmpty {
                        Text(shortPath(event.source))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
            }

            Spacer()

            Image(systemName: "arrow.right.circle")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.4))

            Text(relativeTime(event.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .opacity(event.viewed ? 0.5 : 1.0)
        .contentShape(Rectangle())
    }

    private func shortPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count <= 2 { return path }
        let suffix = components.suffix(3).joined(separator: "/")
        return "…/" + suffix
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}
