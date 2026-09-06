import AppKit
import Foundation

enum WindowFocuser {
    /// Where a tap should take you.
    ///
    /// Before this, "focus" could only ever mean "find the Ghostty window
    /// whose title contains `source`", which is useless for an event that has
    /// no terminal behind it — a reminder, or anything raised by an app with a
    /// window of its own. An explicit `target` overrides that; absent one the
    /// old behaviour is unchanged.
    static func route(target: String?, source: String) {
        guard let target, !target.isEmpty else {
            focus(source: source)
            return
        }
        if let url = URL(string: target), url.scheme != nil {
            NSWorkspace.shared.open(url)
        } else if target.hasPrefix("bundle:") {
            let id = String(target.dropFirst("bundle:".count))
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        } else {
            focus(source: target)
        }
    }

    static func focus(source: String) {
        guard !source.isEmpty else { return }

        // Sanitize source to prevent AppleScript injection
        let safe = source.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "System Events"
            if exists process "ghostty" then
                tell process "ghostty"
                    set windowList to every window
                    repeat with w in windowList
                        if title of w contains "\(safe)" then
                            perform action "AXRaise" of w
                            set frontmost to true
                        end if
                    end repeat
                end tell
            end if
        end tell
        tell application "ghostty" to activate
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            appleScript?.executeAndReturnError(&error)
            if let error = error {
                print("LootDrop: AppleScript error: \(error)")
            }
        }
    }
}
