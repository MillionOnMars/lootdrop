import Combine
import Foundation

/// View state that outlives any single popover presentation.
///
/// This exists because of a real bug. `ContentView` is hosted in one
/// `NSHostingController` built at launch and reused for the life of the app,
/// so a `@State` flag inside it is never reset — open the settings pane, click
/// away, and the next incoming event pops the settings pane open instead of
/// the alert that caused it, for four seconds, over and over. Hoisting the
/// flag out here lets the delegate force the list back into view whenever the
/// popover is being shown *because something happened*.
final class AppState: ObservableObject {
    @Published var showSettings = false

    /// Called on every event-driven presentation. A manual click on the
    /// menubar icon deliberately does not do this, so that fiddling with
    /// sound settings survives an accidental click-away.
    func showEventList() {
        if showSettings { showSettings = false }
    }
}
