import Foundation

enum WindowFocuser {
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
                            return true
                        end if
                    end repeat
                end tell
            end if
        end tell
        return false
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
