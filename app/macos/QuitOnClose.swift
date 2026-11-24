import Cocoa

// Quit on close (Settings > Accessibility, off by default): an app quits once its last window closes.
// It covers every app with a Dock icon except a list kept running (players, messengers, calls), or only
// picked apps. Windows are read from the window server once a second while a watched app runs: no
// Accessibility observers, nothing asked of the watched apps themselves.
//
// What counts as an open window: a normal-sized, visible window that is on screen or belongs to a Space.
// Minimized windows and windows on other desktops still belong to a Space; the invisible leftovers many apps
// keep after their last window closes (TextEdit keeps one) belong to none. The Space lookup is a private
// window server call, the same one Space-aware window tools use.

@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopySpacesForWindows") private func CGSCopySpacesForWindows(_ connection: Int32, _ mask: Int32, _ windows: CFArray) -> Unmanaged<CFArray>?
/// The app a helper process works for: a sandboxed app's Open and Save panels run in a system service.
@_silgen_name("responsibility_get_pid_responsible_for_pid") private func responsiblePID(_ pid: pid_t) -> pid_t

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
    /// Right after a click or ⌘W the gap is confirmed sooner: the user just closed something.
    static let quickGrace: TimeInterval = 0.7
    /// When the checks run after a click or ⌘W; the last one lands after the quick grace.
    static let quickChecks: [TimeInterval] = [0.25, 0.6, 1.0]

    /// Whether a window keeps its app open. `inSpace` is asked only for off-screen normal windows.
    static func counts(_ window: WindowSample, inSpace: () -> Bool) -> Bool {
        guard window.alpha > 0, window.width >= minimumSide, window.height >= minimumSide else { return false }
        if window.layer == 0 { return window.onscreen || inSpace() }
        // Floating panels and palettes the app shows (below the menu bar's level) keep it too, while visible.
        return window.onscreen && window.layer > 0 && window.layer < Int(CGWindowLevelForKey(.mainMenuWindow))
    }

    enum Step: Equatable { case keep, wait, quit }
    /// One check of one app: quit only after it had a window, then had none for the whole grace period.
    static func step(windows: Int, hadWindows: Bool, hidden: Bool, emptySince: Date?, now: Date, grace: TimeInterval = grace) -> Step {
        if windows > 0 || !hadWindows || hidden { return .keep }
        guard let emptySince else { return .wait }
        return now.timeIntervalSince(emptySince) >= grace ? .quit : .wait
    }

    /// Kept running in "All apps" until the user changes the list: they play, take calls or deliver
    /// messages with no window open.
    static let defaultExceptions = [
        "com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.apple.mobilephone", "com.apple.FaceTime",
        "com.apple.MobileSMS", "com.apple.mail", "com.kakao.KakaoTalkMac", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
        "local.aiilluminati", "local.aiface",   // the AI chats and the face board keep working with no window open
    ]

    /// Whether an app is watched: all pickable apps but the exceptions, or only the picked ones.
    static func watched(bundle: String?, policy: NSApplication.ActivationPolicy, own: String?, all: Bool, picked: Set<String>, exceptions: Set<String>) -> Bool {
        guard pickable(bundle: bundle, policy: policy, own: own), let bundle else { return false }
        return all ? !exceptions.contains(bundle) : picked.contains(bundle)
    }

    /// Apps that can never be picked: this app, Finder (it hosts the desktop) and anything without a Dock icon.
    static func pickable(bundle: String?, policy: NSApplication.ActivationPolicy, own: String?) -> Bool {
        guard let bundle, bundle != own, bundle != FinderShortcuts.finderID else { return false }
        return policy == .regular
    }
}

final class QuitOnClose: ObservableObject {
    static let shared = QuitOnClose()
    /// Picked bundle ids, in the order they were picked ("Picked apps").
    @Published private(set) var picked: [String] = UserDefaults.standard.stringArray(forKey: Pref.quitOnCloseApps) ?? []
    /// Bundle ids kept running ("All apps").
    @Published private(set) var exceptions: [String] = UserDefaults.standard.stringArray(forKey: Pref.quitOnCloseExceptions) ?? QuitOnCloseRules.defaultExceptions
    /// Running apps that can be picked, then listed apps that are installed but not running.
    @Published private(set) var apps: [TidyApp] = []
    @Published private(set) var running = false

    private struct Watch { var hadWindows = false; var emptySince: Date? }
    private var watches: [pid_t: Watch] = [:]
    private var timer: Timer?
    /// Clicks and ⌘W, watched only to check sooner; nothing about them is kept.
    private var closeMonitor: Any?
    private var lastCloseAction = Date.distantPast
    private var quickChecks: [DispatchWorkItem] = []
    private lazy var connection = CGSMainConnectionID()

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.apply() }
        }
    }

    var enabled: Bool { UserDefaults.standard.bool(forKey: Pref.quitOnClose) }
    var allApps: Bool { UserDefaults.standard.bool(forKey: Pref.quitOnCloseAll) }
    /// The list the picker edits: exceptions for all apps, picks otherwise.
    var list: [String] { allApps ? exceptions : picked }

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
        if wanted && closeMonitor == nil {
            closeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] event in
                if event.type == .keyDown {
                    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    guard mods == .command, event.charactersIgnoringModifiers?.lowercased() == "w" else { return }
                }
                self?.closeActionSeen()
            }
        } else if !wanted, let monitor = closeMonitor {
            NSEvent.removeMonitor(monitor); closeMonitor = nil
        }
        running = wanted
    }

    private func watchedApps() -> [NSRunningApplication] {
        let all = allApps, picks = Set(picked), kept = Set(exceptions), own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            !app.isTerminated && QuitOnCloseRules.watched(bundle: app.bundleIdentifier, policy: app.activationPolicy, own: own,
                                                          all: all, picked: picks, exceptions: kept)
        }
    }

    /// A click (maybe on a close button) or ⌘W: check a few times over the next second instead of
    /// waiting for the once-a-second check, so an app quits about a second after its last window closes.
    private func closeActionSeen() {
        lastCloseAction = Date()
        quickChecks.forEach { $0.cancel() }
        quickChecks = QuitOnCloseRules.quickChecks.map { delay in
            let work = DispatchWorkItem { [weak self] in self?.check() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    private func check() {
        guard enabled else { apply(); return }
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        var counts: [pid_t: Int] = [:], helped: [pid_t: Int] = [:]
        var offscreen: [WindowSample] = []
        var owners: [pid_t: pid_t] = [:]   // helper pid → the app it works for, looked up once per check
        for info in list {
            guard let window = WindowSample(info) else { continue }
            guard watches[window.pid] != nil else {
                // A visible window of another process working for a watched app (an Open or Save panel)
                // keeps that app open, but does not count as the app having shown a window of its own.
                guard window.onscreen, QuitOnCloseRules.counts(window, inSpace: { false }) else { continue }
                let owner = owners[window.pid] ?? responsiblePID(window.pid)
                owners[window.pid] = owner
                if owner != window.pid, watches[owner] != nil { helped[owner, default: 0] += 1 }
                continue
            }
            if QuitOnCloseRules.counts(window, inSpace: { false }) { counts[window.pid, default: 0] += 1 }
            else if !window.onscreen { offscreen.append(window) }
        }
        // Only an app with nothing on screen needs the Space lookup, and only until one window is found.
        for window in offscreen where counts[window.pid] == nil {
            if QuitOnCloseRules.counts(window, inSpace: { inSpace(window.id) }) { counts[window.pid] = 1 }
        }
        let now = Date()
        for app in watchedApps() {
            let pid = app.processIdentifier
            var watch = watches[pid] ?? Watch()
            let own = counts[pid] ?? 0, windows = own + (helped[pid] ?? 0)
            if own > 0 { watch.hadWindows = true }
            if windows > 0 { watch.emptySince = nil }
            let quick = now.timeIntervalSince(lastCloseAction) < 2
            switch QuitOnCloseRules.step(windows: windows, hadWindows: watch.hadWindows, hidden: app.isHidden, emptySince: watch.emptySince, now: now,
                                         grace: quick ? QuitOnCloseRules.quickGrace : QuitOnCloseRules.grace) {
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
        let missing = self.list.filter { !seen.contains($0) && NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
            .map { TidyApp(bundle: $0) }
        apps = list + missing
    }

    /// Turns an app on in the current list: picked to quit, or kept running.
    func setListed(_ bundle: String, _ on: Bool) {
        if allApps {
            exceptions.removeAll { $0 == bundle }
            if on { exceptions.append(bundle) }
            UserDefaults.standard.set(exceptions, forKey: Pref.quitOnCloseExceptions)
        } else {
            picked.removeAll { $0 == bundle }
            if on { picked.append(bundle) }
            UserDefaults.standard.set(picked, forKey: Pref.quitOnCloseApps)
        }
        apply()
    }

    /// Installed apps in the current list, for the settings row.
    var listedCount: Int {
        list.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }.count
    }
}
