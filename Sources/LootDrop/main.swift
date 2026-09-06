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
    private let appState = AppState()
    private var server: EventServer!
    private var driftDetector: DriftDetector!
    private var scheduler: Scheduler!
    private var cancellables: Set<AnyCancellable> = []
    private var autoDismissWork: DispatchWorkItem?
    private var clickMonitor: Any?
    private var dndExpiryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = settingsStore.settings

        soundPlayer.reloadSounds(customDir: settings.customSoundsDirURL)
        store.load(retentionDays: settings.retentionDays)

        let store = self.store

        // Drift detector — reminds about forgotten approval requests
        driftDetector = DriftDetector(
            driftMinutes: settings.driftMinutes
        ) { [weak self] source, minutes in
            DispatchQueue.main.async {
                self?.deliver(LootEvent(
                    type: "drift",
                    title: "Forgotten session (\(minutes)m)",
                    subtitle: "Still waiting for approval",
                    rarity: .epic,
                    source: source,
                    behavior: .persist
                ))
            }
        }
        if settings.driftMinutes > 0 {
            driftDetector.start()
        }

        // Reminders posted earlier, fired when their time comes.
        // This delivers rather than re-entering accept(): the event still
        // carries the delaySeconds that got it here, so accept() would read
        // it as a fresh request and reschedule it forever, postponing the
        // reminder on every tick instead of ever showing it.
        scheduler = Scheduler { [weak self] incoming in
            self?.deliver(incoming.toLootEvent())
        }
        scheduler.start()

        // Menubar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
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
            appState: appState,
            onEventTapped: { [weak self] event in
                self?.autoDismissWork?.cancel()
                self?.closePopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    WindowFocuser.route(target: event.target, source: event.source)
                }
            },
            onToggleDND: { [weak self] in
                guard let self else { return }
                let active = self.settingsStore.settings.isDoNotDisturbActive
                self.setDoNotDisturb(minutes: active ? 0 : nil)
            }
        )
        popover.contentViewController = NSHostingController(rootView: contentView)

        // HTTP server on configurable port
        let port = UInt16(clamping: settings.port)
        server = EventServer(
            port: port,
            onEvent: { [weak self] incoming in
                self?.accept(incoming)
            },
            onDND: { [weak self] request in
                guard let self else { return "{\"error\":\"gone\"}" }
                return DispatchQueue.main.sync {
                    if request.enabled == false {
                        self.setDoNotDisturb(minutes: 0)
                    } else {
                        self.setDoNotDisturb(minutes: request.minutes)
                    }
                    return self.statusJSON()
                }
            },
            onStatus: { [weak self] in
                guard let self else { return "{\"error\":\"gone\"}" }
                return DispatchQueue.main.sync { self.statusJSON() }
            },
            onClearScheduled: { [weak self] in
                guard let self else { return "{\"error\":\"gone\"}" }
                let removed = self.scheduler.clear()
                return "{\"cleared\":\(removed)}"
            }
        )
        server.start()

        // Badge and menubar icon follow the stores
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &cancellables)
        settingsStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &cancellables)

        armDNDExpiryTimer()
        refreshStatusItem()

        print("LootDrop: Running on port \(port)")
        print("  Retention: \(settings.retentionDays) days | Drift: \(settings.driftMinutes)m")
    }

    // MARK: - Intake

    /// Entry point for anything arriving over HTTP: schedules it if it carries
    /// a delay, otherwise delivers it now.
    private func accept(_ incoming: IncomingEvent) {
        if let delay = incoming.delaySeconds, delay > 0 {
            scheduler.schedule(incoming, fireAt: Date().addingTimeInterval(Double(delay)))
            return
        }
        DispatchQueue.main.async { self.deliver(incoming.toLootEvent()) }
    }

    /// The single path every event takes, whoever raised it.
    private func deliver(_ event: LootEvent) {
        store.add(event)

        if event.behavior == .persist {
            driftDetector.trackPersist(source: event.source)
        } else {
            driftDetector.clearSource(source: event.source)
        }

        // Do Not Disturb suppresses the interruption, never the record: the
        // event is still in the feed and still counted on the badge.
        guard !settingsStore.settings.isDoNotDisturbActive else { return }

        soundPlayer.play(id: settingsStore.settings.config(for: event.behavior).rollSound())
        handleBehavior(event.behavior)
    }

    // MARK: - Do Not Disturb

    /// `nil` mutes indefinitely, `0` clears, anything else mutes for N minutes.
    private func setDoNotDisturb(minutes: Int?) {
        settingsStore.settings.setDoNotDisturb(minutes: minutes)
        settingsStore.save()
        armDNDExpiryTimer()
        refreshStatusItem()
    }

    /// Timed DND has to un-mute the icon on its own; nothing else would notice
    /// the deadline pass, and a stale "muted" icon is a lie about the state.
    private func armDNDExpiryTimer() {
        dndExpiryTimer?.invalidate()
        dndExpiryTimer = nil
        guard let until = settingsStore.settings.doNotDisturbUntil,
              until != .distantFuture,
              until > Date() else { return }
        let timer = Timer(fireAt: until, interval: 0, target: self,
                          selector: #selector(dndExpired), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        dndExpiryTimer = timer
    }

    @objc private func dndExpired() {
        refreshStatusItem()
    }

    private func statusJSON() -> String {
        let s = settingsStore.settings
        let active = s.isDoNotDisturbActive
        var until = "null"
        if active, let date = s.doNotDisturbUntil, date != .distantFuture {
            until = "\(Int(date.timeIntervalSince1970))"
        }
        return "{\"dnd\":\(active),\"dndUntil\":\(until),"
            + "\"scheduled\":\(scheduler.count),\"unviewed\":\(store.unviewedCount)}"
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
        appState.showEventList()
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
        appState.showEventList()
        showPopover()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
            autoDismissWork?.cancel()
        } else {
            showPopover()
            store.markAllViewed()
            refreshStatusItem()
        }
    }

    /// Icon plus badge. The icon carries the mute state so a silent app is
    /// never silently silent.
    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let muted = settingsStore.settings.isDoNotDisturbActive
        let symbol = muted ? "moon.zzz.fill" : "diamond.fill"
        button.image = NSImage(systemSymbolName: symbol,
                               accessibilityDescription: muted ? "LootDrop (muted)" : "LootDrop")
        let count = store.unviewedCount
        button.title = count > 0 ? " \(count)" : ""
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        removeClickOutsideMonitor()
    }
}

// --- Launch ---

setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IOLBF, 0)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = LootDropDelegate()
app.delegate = delegate
app.run()
