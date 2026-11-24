import Cocoa

// Quit on close (Settings > Accessibility, off by default): a picked app quits once its last window closes.
// Only apps the user picks are watched. Windows are read from the window server once a second, and only
// while a picked app runs: no Accessibility observers, nothing asked of the watched apps themselves.
//
// What counts as an open window: a normal-sized, visible window that is on screen or belongs to a Space.
// Minimized windows and windows on other desktops still belong to a Space; the invisible leftovers many apps
// keep after their last window closes (TextEdit keeps one) belong to none. The Space lookup is a private
// window server call, the same one Space-aware window tools use.

@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopySpacesForWindows") private func CGSCopySpacesForWindows(_ connection: Int32, _ mask: Int32, _ windows: CFArray) -> Unmanaged<CFArray>?

/// One window as the window server lists it.
struct WindowSample: Equatable {
    var id: CGWindowID = 0
    var pid: pid_t = 0
    var layer = 0
    var onscreen = false
    var alpha = 1.0
    var width = 0.0, height = 0.0

    init(id: CGWindowID = 0, pid: pid_t = 0, layer: Int = 0, onscreen: Bool = false, alpha: Double = 1, width: Double = 0, height: Double = 0) {
        self.id = id; self.pid = pid; self.layer = layer; self.onscreen = onscreen; self.alpha = alpha; self.width = width; self.height = height
    }
    init?(_ info: [String: Any]) {
        guard let id = info[kCGWindowNumber as String] as? CGWindowID, let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }
        let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
        self.init(id: id, pid: pid, layer: info[kCGWindowLayer as String] as? Int ?? 0, onscreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false,
                  alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
                  width: (bounds["Width"] as? NSNumber)?.doubleValue ?? 0, height: (bounds["Height"] as? NSNumber)?.doubleValue ?? 0)
    }
}

enum QuitOnCloseRules {
    /// Smaller windows are toolbars, drag images and the like, never what a user closes last.
    static let minimumSide = 80.0
    /// How long an app must have no windows: full-screen exits and window swaps leave short gaps.
    static let grace: TimeInterval = 1.5

    /// Whether a window keeps its app open. `inSpace` is asked only for off-screen normal windows.
    static func counts(_ window: WindowSample, inSpace: () -> Bool) -> Bool {
        guard window.alpha > 0, window.width >= minimumSide, window.height >= minimumSide else { return false }
        if window.layer == 0 { return window.onscreen || inSpace() }
        // Floating panels and palettes the app shows (below the menu bar's level) keep it too, while visible.
        return window.onscreen && window.layer > 0 && window.layer < Int(CGWindowLevelForKey(.mainMenuWindow))
    }

    enum Step: Equatable { case keep, wait, quit }
    /// One check of one app: quit only after it had a window, then had none for the whole grace period.
    static func step(windows: Int, hadWindows: Bool, hidden: Bool, emptySince: Date?, now: Date) -> Step {
        if windows > 0 || !hadWindows || hidden { return .keep }
        guard let emptySince else { return .wait }
        return now.timeIntervalSince(emptySince) >= grace ? .quit : .wait
    }

    /// Apps that can never be picked: this app, Finder (it hosts the desktop) and anything without a Dock icon.
    static func pickable(bundle: String?, policy: NSApplication.ActivationPolicy, own: String?) -> Bool {
        guard let bundle, bundle != own, bundle != FinderShortcuts.finderID else { return false }
        return policy == .regular
    }
}

final class QuitOnClose: ObservableObject {
    static let shared = QuitOnClose()
    /// Picked bundle ids, in the order they were picked.
    @Published private(set) var picked: [String] = UserDefaults.standard.stringArray(forKey: Pref.quitOnCloseApps) ?? []
    /// Running apps that can be picked, then picked apps that are not running.
    @Published private(set) var apps: [TidyApp] = []
    @Published private(set) var running = false

    private struct Watch { var hadWindows = false; var emptySince: Date? }
    private var watches: [pid_t: Watch] = [:]
    private var timer: Timer?
    private lazy var connection = CGSMainConnectionID()

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.apply() }
        }
    }

    var enabled: Bool { UserDefaults.standard.bool(forKey: Pref.quitOnClose) }

    /// Starts or stops the once-a-second check from the setting and the picked apps that run.
    func apply() {
        let watched = enabled ? watchedApps() : []
        let pids = Set(watched.map(\.processIdentifier))
        watches = watches.filter { pids.contains($0.key) }
        for pid in pids where watches[pid] == nil { watches[pid] = Watch() }
        let wanted = !pids.isEmpty
        if wanted && timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            check()
        } else if !wanted, let timer {
            timer.invalidate(); self.timer = nil
        }
        running = wanted
    }

    private func watchedApps() -> [NSRunningApplication] {
        let set = Set(picked)
        return NSWorkspace.shared.runningApplications.filter { app in
            guard let bundle = app.bundleIdentifier, set.contains(bundle), !app.isTerminated else { return false }
            return QuitOnCloseRules.pickable(bundle: bundle, policy: app.activationPolicy, own: Bundle.main.bundleIdentifier)
        }
    }

    private func check() {
        guard enabled else { apply(); return }
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        var counts: [pid_t: Int] = [:]
        for info in list {
            guard let window = WindowSample(info), watches[window.pid] != nil else { continue }
            if QuitOnCloseRules.counts(window, inSpace: { inSpace(window.id) }) { counts[window.pid, default: 0] += 1 }
        }
        let now = Date()
        for app in watchedApps() {
            let pid = app.processIdentifier
            var watch = watches[pid] ?? Watch()
            let windows = counts[pid] ?? 0
            if windows > 0 { watch.hadWindows = true; watch.emptySince = nil }
            switch QuitOnCloseRules.step(windows: windows, hadWindows: watch.hadWindows, hidden: app.isHidden, emptySince: watch.emptySince, now: now) {
            case .keep: watch.emptySince = nil
            case .wait: if watch.emptySince == nil { watch.emptySince = now }
            case .quit:
                AppModel.log("Quit on close: \(app.localizedName ?? app.bundleIdentifier ?? "app") closed its last window")
                app.terminate()
                watch = Watch()     // a refused quit (unsaved changes) starts over once it has a window again
            }
            watches[pid] = watch
        }
    }

    private func inSpace(_ window: CGWindowID) -> Bool {
        let spaces = CGSCopySpacesForWindows(connection, 7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue() as? [Any]
        return !(spaces ?? []).isEmpty
    }

    // MARK: Picking apps (Settings)

    func refreshApps() {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var list: [TidyApp] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundle = app.bundleIdentifier, QuitOnCloseRules.pickable(bundle: bundle, policy: app.activationPolicy, own: own),
                  seen.insert(bundle).inserted else { continue }
            list.append(TidyApp(bundle: bundle, running: app))
        }
        list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let missing = picked.filter { !seen.contains($0) }.map { TidyApp(bundle: $0) }
        apps = list + missing
    }

    func setPicked(_ bundle: String, _ on: Bool) {
        picked.removeAll { $0 == bundle }
        if on { picked.append(bundle) }
        UserDefaults.standard.set(picked, forKey: Pref.quitOnCloseApps)
        apply()
    }
}
