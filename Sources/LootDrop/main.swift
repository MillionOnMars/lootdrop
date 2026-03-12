import AppKit
import Combine
import SwiftUI

// --- App Delegate (menubar-only app) ---

class LootDropDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = EventStore()
    private let settingsStore = SettingsStore()
    private let soundPlayer = SoundPlayer()
    private var server: EventServer!
    private var driftDetector: DriftDetector!
    private var cancellable: AnyCancellable?
    private var autoDismissWork: DispatchWorkItem?
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = settingsStore.settings

        // Load sounds and history
        soundPlayer.reloadSounds(customDir: settings.customSoundsDirURL)
        store.load(retentionDays: settings.retentionDays)

        // Drift detector — reminds about forgotten approval requests
        let store = self.store
        let soundPlayer = self.soundPlayer
        let settingsStore = self.settingsStore

        driftDetector = DriftDetector(
            driftMinutes: settings.driftMinutes
        ) { [weak self] source, minutes in
            DispatchQueue.main.async {
                let event = LootEvent(
                    type: "drift",
                    title: "Forgotten session (\(minutes)m)",
                    subtitle: "Still waiting for approval",
                    rarity: .epic,
                    source: source,
                    behavior: .persist
                )
                let sound = settingsStore.settings.config(for: .persist).rollSound()
                store.add(event)
                soundPlayer.play(id: sound)
                self?.showPopoverPersist()
            }
        }
        if settings.driftMinutes > 0 {
            driftDetector.start()
        }

        // Menubar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "diamond.fill", accessibilityDescription: "LootDrop")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Popover — applicationDefined so we control dismissal ourselves
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 420)
        popover.behavior = .applicationDefined
        popover.delegate = self

        let contentView = ContentView(
            store: store,
            settingsStore: settingsStore,
            soundPlayer: soundPlayer,
            onEventTapped: { [weak self] event in
                self?.autoDismissWork?.cancel()
                self?.closePopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    WindowFocuser.focus(source: event.source)
                }
            }
        )
        popover.contentViewController = NSHostingController(rootView: contentView)

        // HTTP server on configurable port
        let port = UInt16(clamping: settings.port)
        server = EventServer(port: port) { [weak self] incoming in
            let event = incoming.toLootEvent()
            DispatchQueue.main.async {
                let sound = settingsStore.settings.config(for: event.behavior).rollSound()
                store.add(event)
                soundPlayer.play(id: sound)
                self?.handleBehavior(event.behavior)

                if event.behavior == .persist {
                    self?.driftDetector.trackPersist(source: event.source)
                } else {
                    self?.driftDetector.clearSource(source: event.source)
                }
            }
        }
        server.start()

        // Update badge when store changes
        cancellable = store.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateBadge()
            }
        }

        print("LootDrop: Running on port \(port)")
        print("  Retention: \(settings.retentionDays) days | Drift: \(settings.driftMinutes)m")
    }

    // MARK: - Popover management

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        addClickOutsideMonitor()
    }

    private func closePopover() {
        popover.performClose(nil)
        removeClickOutsideMonitor()
    }

    /// Monitor for clicks outside the popover to dismiss it
    private func addClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.popover.isShown else { return }
            self.closePopover()
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - Behaviors

    private func handleBehavior(_ behavior: EventBehavior) {
        switch behavior {
        case .flash:   showPopoverFlash()
        case .persist: showPopoverPersist()
        case .silent:  break
        }
    }

    private func showPopoverFlash() {
        autoDismissWork?.cancel()
        showPopover()
        let work = DispatchWorkItem { [weak self] in
            self?.closePopover()
        }
        autoDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func showPopoverPersist() {
        autoDismissWork?.cancel()
        autoDismissWork = nil
        showPopover()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
            autoDismissWork?.cancel()
        } else {
            showPopover()
            store.markAllViewed()
            updateBadge()
        }
    }

    private func updateBadge() {
        let count = store.unviewedCount
        if let button = statusItem.button {
            button.title = count > 0 ? " \(count)" : ""
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        removeClickOutsideMonitor()
    }
}

// --- Launch ---

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = LootDropDelegate()
app.delegate = delegate
app.run()
