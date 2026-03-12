import Foundation

/// Tracks "persist" events (waiting for approval) and fires a reminder
/// if the user hasn't interacted after N minutes.
class DriftDetector {
    private var pendingSources: [String: Date] = [:]  // source -> when it started waiting
    private var timer: Timer?
    private let onDrift: (String, Int) -> Void  // (source, minutes waiting)

    var driftMinutes: Int

    init(driftMinutes: Int, onDrift: @escaping (String, Int) -> Void) {
        self.driftMinutes = driftMinutes
        self.onDrift = onDrift
    }

    func start() {
        // Check every 60 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkDrift()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call when a persist event arrives (something is waiting for approval)
    func trackPersist(source: String) {
        if pendingSources[source] == nil {
            pendingSources[source] = Date()
        }
    }

    /// Call when any non-persist event arrives from a source (user took action)
    func clearSource(source: String) {
        pendingSources.removeValue(forKey: source)
    }

    private func checkDrift() {
        let now = Date()
        let threshold = TimeInterval(driftMinutes * 60)

        for (source, startTime) in pendingSources {
            let elapsed = now.timeIntervalSince(startTime)
            if elapsed >= threshold {
                let minutes = Int(elapsed / 60)
                onDrift(source, minutes)
                // Reset the timer so we don't spam — next alert in another driftMinutes
                pendingSources[source] = now
            }
        }
    }
}
