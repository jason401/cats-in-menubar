import Cocoa
import ApplicationServices

// Quit on close (Settings > Accessibility, off by default): an app quits once its last window closes.
// It covers every app with a Dock icon except a list kept running, or only picked apps.
//
// How a close is noticed (the same rules Vorssaint's auto quit follows, written anew here):
// - Each covered app gets one Accessibility observer for windows appearing, closing and minimizing.
//   The app element is never asked its role: Chromium apps switch on full accessibility (and keep
//   using CPU) once asked.
// - A listen-only tap sees clicks on a window's close button and ⌘W, as hints to look sooner.
// - A close is confirmed 0.35, 1.0 and 2.2 s later, then once more 1.2 s after that, before the quit.
// - What counts as an open window: a standard window Accessibility lists, or a normal-sized window the
//   window server shows; minimized windows and windows on another desktop keep the app too, an invisible
//   leftover on the desktop in front does not. When a check cannot tell, the app stays.
// Everything runs on a thread of its own, so a slow app never stalls the cats.

@_silgen_name("responsibility_get_pid_responsible_for_pid") private func responsiblePID(_ pid: pid_t) -> pid_t

/// One window as the window server lists it (top-left coordinates).
struct WindowSample: Equatable {
    var id: CGWindowID = 0
    var pid: pid_t = 0
    var layer = 0
    var onscreen = false
    var alpha = 1.0
    var x = 0.0, y = 0.0, width = 0.0, height = 0.0

    init(id: CGWindowID = 0, pid: pid_t = 0, layer: Int = 0, onscreen: Bool = false, alpha: Double = 1,
         x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0) {
        self.id = id; self.pid = pid; self.layer = layer; self.onscreen = onscreen; self.alpha = alpha
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    init?(_ info: [String: Any]) {
        guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return nil }
        let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
        func number(_ key: String) -> Double { (bounds[key] as? NSNumber)?.doubleValue ?? 0 }
        self.init(id: id, pid: pid, layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                  onscreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
                  alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                  x: number("X"), y: number("Y"), width: number("Width"), height: number("Height"))
    }
    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Which apps are covered, as the settings say.
struct QuitScope: Equatable {
    var all = true
    var picked: Set<String> = []
    var exceptions: Set<String> = []
    var menuBarApps: Set<String> = []
}

/// The decisions, kept free of the system so they can be tested.
enum QuitOnCloseRules {
    /// Smaller windows are toolbars, drag images and the like, never what a user closes last.
    static let minimumSide = 80.0
    /// After a close: the checks, then the confirming one before the quit.
    static let checkDelays: [TimeInterval] = [0.35, 1.0, 2.2]
    static let confirmDelay: TimeInterval = 1.2
    /// Closes of one app this close together are one close.
    static let checkSpacing: TimeInterval = 0.25
    /// How long a click on a close button keeps counting as the user's close.
    static let closeRequestGrace: TimeInterval = 5
    /// Windows that appear late are read again, counted from the first look.
    static let windowRereads: [TimeInterval] = [0.5, 1.5, 4.0]
    /// An app that cannot answer yet (still launching) is asked again after these waits.
    static let attachRetries: [TimeInterval] = [0.15, 0.4, 1.0, 2.5, 5.0, 10.0]
    /// Accessibility answers wait no longer than this per app.
    static let messagingTimeout: Float = 0.35

    /// Never quit: Finder hosts the desktop, and quitting Phone ends calls.
    static let mandatoryExceptions = ["com.apple.finder", "com.apple.mobilephone"]

    /// Kept running in "All apps" until the user changes the list: they play, take calls or deliver
    /// messages with no window open.
    static let defaultExceptions = [
        "com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.apple.mobilephone", "com.apple.FaceTime",
        "com.apple.MobileSMS", "com.apple.mail", "com.kakao.KakaoTalkMac", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
        "local.aiilluminati", "local.aiface",   // the AI chats and the face board keep working with no window open
    ]

    /// Whether an app is on a list: by its id, as a Windows app of a listed Parallels, or as an app
    /// inside a listed app's bundle.
    static func listed(bundle: String, url: URL?, in list: Set<String>, bundleID: (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier }) -> Bool {
        if list.contains(bundle) { return true }
        if bundle.hasPrefix("com.parallels.winapp."), list.contains("com.parallels.desktop.console") { return true }
        var folder = url?.deletingLastPathComponent()
        while let current = folder, current.path != "/", !current.path.isEmpty {
            if current.pathExtension == "app", let id = bundleID(current), list.contains(id) { return true }
            folder = current.deletingLastPathComponent()
        }
        return false
    }

    /// Menu bar apps (LSUIElement) quit only once picked and while in the Dock; background-only apps never.
    static func background(uiElement: Bool, backgroundOnly: Bool, optedIn: Bool, inDock: Bool) -> Bool {
        if backgroundOnly { return true }
        return uiElement && !(optedIn && inDock)
    }

    /// Whether an app may quit on close.
    static func covered(bundle: String?, url: URL?, policy: NSApplication.ActivationPolicy, own: String?, uiElement: Bool, backgroundOnly: Bool,
                        scope: QuitScope, bundleID: (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier }) -> Bool {
        guard let bundle, bundle != own, policy == .regular, !backgroundOnly else { return false }
        if listed(bundle: bundle, url: url, in: Set(mandatoryExceptions), bundleID: bundleID) { return false }
        if !scope.all { return scope.picked.contains(bundle) }
        if listed(bundle: bundle, url: url, in: scope.exceptions, bundleID: bundleID) { return false }
        return !background(uiElement: uiElement, backgroundOnly: backgroundOnly, optedIn: scope.menuBarApps.contains(bundle), inDock: policy == .regular)
    }

    /// Apps that can be listed in the settings: this app and Finder never, and only apps with a Dock icon.
    static func pickable(bundle: String?, policy: NSApplication.ActivationPolicy, own: String?) -> Bool {
        guard let bundle, bundle != own, bundle != mandatoryExceptions[0] else { return false }
        return policy == .regular
    }

    enum Event { case windowDestroyed, appHidden, other }
    /// Only a window going away, or an app hiding right after a click on a close button, may be a close.
    /// Switching apps or desktops never is.
    static func schedulesCheck(_ event: Event, closeRequested: Bool) -> Bool {
        switch event {
        case .windowDestroyed: true
        case .appHidden: closeRequested
        case .other: false
        }
    }

    /// The last word before a quit.
    static func shouldQuit(hadWindows: Bool, terminated: Bool, hidden: Bool, closeRequested: Bool, minimized: Bool, userFacingWindow: Bool) -> Bool {
        guard hadWindows, !terminated else { return false }
        if hidden && !closeRequested { return false }
        if minimized { return false }
        return !userFacingWindow
    }

    /// An Accessibility window that keeps its app: full screen, minimized, or a standard window.
    /// Sheets, dialogs and palettes do not.
    static func standardWindow(fullScreen: Bool, minimized: Bool, role: String?, subrole: String?) -> Bool {
        if fullScreen { return true }
        if minimized && role == kAXWindowRole { return true }
        if let subrole { return subrole == kAXStandardWindowSubrole || subrole == "AXFullScreenWindow" }
        return role == kAXWindowRole
    }

    enum WindowKind: Equatable { case unrelated, shown, ownOffscreen }
    /// How a window-server window bears on an app. `everything` also takes other processes' visible
    /// windows (floating toolbars, slideshows, Open and Save panels): only the last check before a quit does.
    static func kind(_ window: WindowSample, app: pid_t, everything: Bool) -> WindowKind {
        guard window.alpha > 0, window.width >= minimumSide, window.height >= minimumSide else { return .unrelated }
        guard window.pid == app || everything else { return .unrelated }
        if window.pid == app && window.layer == 0 { return window.onscreen ? .shown : .ownOffscreen }
        return everything && window.onscreen && window.layer >= 0 ? .shown : .unrelated
    }

    /// An off-screen normal window keeps its app only while parked on a desktop not in front.
    /// No answer keeps it; no desktop at all is a leftover (TextEdit keeps one).
    static func offscreenKeepsApp(spaces: [UInt64]?, visible: Set<UInt64>?) -> Bool {
        guard let spaces else { return true }
        if spaces.isEmpty { return false }
        guard let visible, !visible.isEmpty else { return true }
        return spaces.allSatisfy { !visible.contains($0) }
    }

    /// The close button's corner of a window: a cheap test before asking Accessibility.
    static func inCloseArea(_ point: CGPoint, of frame: CGRect) -> Bool {
        let dx = point.x - frame.minX, dy = point.y - frame.minY
        return dy >= -6 && dy <= 46 && dx >= -6 && dx <= 52
    }
    /// The close button by place alone, when Accessibility cannot point at it: the button sits as far in
    /// from the left as from the top, so only clicks near that diagonal count (never the minimize button).
    static func onCloseButton(_ point: CGPoint, of frame: CGRect) -> Bool {
        let dx = point.x - frame.minX, dy = point.y - frame.minY
        return dx >= 0 && dy >= 0 && max(dx, dy) <= 35 && abs(dx - dy) <= 9
    }

    /// The window server tags a window minimized into the Dock with this bit.
    static func minimized(tags: UInt64) -> Bool { tags & (1 << 60) != 0 }
}

/// Private window server calls, looked up at run time. A missing one answers nil, which keeps apps open.
enum WindowServer {
    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? { dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) }
    private static let connection: Int32 = {
        guard let s = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(s, to: (@convention(c) () -> Int32).self)()
    }()
    private typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let copySpaces: CopySpaces? = symbol("CGSCopySpacesForWindows").map { unsafeBitCast($0, to: CopySpaces.self) }
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let copyDisplaySpaces: CopyDisplaySpaces? = symbol("CGSCopyManagedDisplaySpaces").map { unsafeBitCast($0, to: CopyDisplaySpaces.self) }

    private typealias Query = @convention(c) (Int32, CFArray, UInt64) -> Unmanaged<CFTypeRef>?
    private typealias QueryWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private typealias Advance = @convention(c) (CFTypeRef) -> Bool
    private typealias WindowID = @convention(c) (CFTypeRef) -> UInt32
    private typealias Tags = @convention(c) (CFTypeRef) -> UInt64
    private static let tagQuery: (Query, QueryWindows, Advance, WindowID, Tags)? = {
        guard let q = symbol("SLSWindowQueryWindows"), let w = symbol("SLSWindowQueryResultCopyWindows"), let a = symbol("SLSWindowIteratorAdvance"),
              let i = symbol("SLSWindowIteratorGetWindowID"), let t = symbol("SLSWindowIteratorGetTags") else { return nil }
        return (unsafeBitCast(q, to: Query.self), unsafeBitCast(w, to: QueryWindows.self), unsafeBitCast(a, to: Advance.self),
                unsafeBitCast(i, to: WindowID.self), unsafeBitCast(t, to: Tags.self))
    }()

    /// The desktops a window belongs to: empty for a leftover, nil when the server cannot say.
    static func spaces(of window: CGWindowID) -> [UInt64]? {
        guard connection != 0, let copySpaces,
              let list = copySpaces(connection, 7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return nil }
        return list.map(\.uint64Value)
    }

    /// The desktop in front on each display.
    static func visibleSpaces() -> Set<UInt64>? {
        guard connection != 0, let copyDisplaySpaces,
              let displays = copyDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]], !displays.isEmpty else { return nil }
        let current = displays.compactMap { (($0["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value }
        return current.isEmpty ? nil : Set(current)
    }

    /// Whether the server holds the window minimized in the Dock (macOS 26 and later). Nil when it does not say.
    static func isMinimized(_ window: CGWindowID) -> Bool? {
        guard #available(macOS 26.0, *), connection != 0, let q = tagQuery,
              let result = q.0(connection, [NSNumber(value: window)] as CFArray, 0)?.takeRetainedValue(),
              let iterator = q.1(result)?.takeRetainedValue() else { return nil }
        while q.2(iterator) {
            guard q.3(iterator) == window else { continue }
            let value = q.4(iterator)
            return value == 0 ? nil : QuitOnCloseRules.minimized(tags: value)
        }
        return false   // the window no longer exists
    }
}

/// A thread with its own run loop: the Accessibility observers, the click tap and the timers live here.
final class RunLoopThread {
    private var loop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)

    init(name: String) {
        let thread = Thread { [unowned self] in
            var context = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAlive, .defaultMode)
            self.loop = CFRunLoopGetCurrent()
            self.ready.signal()
            CFRunLoopRun()
        }
        thread.name = name
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
    }
    var runLoop: CFRunLoop { loop! }
    func async(_ work: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }
    func after(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + max(0, delay), 0, 0, 0) { _ in work() }
        CFRunLoopAddTimer(runLoop, timer, .defaultMode)
    }
}

final class QuitOnClose: ObservableObject {
    static let shared = QuitOnClose()
    /// Picked bundle ids, in the order they were picked ("Picked apps").
    @Published private(set) var picked: [String] = UserDefaults.standard.stringArray(forKey: Pref.quitOnCloseApps) ?? []
    /// Bundle ids kept running ("All apps").
    @Published private(set) var exceptions: [String] = UserDefaults.standard.stringArray(forKey: Pref.quitOnCloseExceptions) ?? QuitOnCloseRules.defaultExceptions
    /// Menu bar apps allowed to quit in "All apps" while they show a Dock icon.
    @Published private(set) var menuBarApps: [String] = UserDefaults.standard.stringArray(forKey: Pref.quitOnCloseMenuBarApps) ?? []
    /// Apps the open picker lists: running ones first, then listed apps that are installed but not running.
    @Published private(set) var apps: [TidyApp] = []
    @Published private(set) var menuBarCandidates: [TidyApp] = []
    @Published private(set) var running = false

    private lazy var watcher = CloseWatcher(owner: self)

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.running, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.watcher.launched(app)
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.running, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.watcher.terminated(app.processIdentifier)
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.running, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.watcher.activated(app)
        }
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.running else { return }
            self.watcher.spaceChanged()
        }
    }

    var enabled: Bool { UserDefaults.standard.bool(forKey: Pref.quitOnClose) }
    var allApps: Bool { UserDefaults.standard.bool(forKey: Pref.quitOnCloseAll) }
    /// The list the picker edits: exceptions for all apps, picks otherwise.
    var list: [String] { allApps ? exceptions : picked }
    var scope: QuitScope { QuitScope(all: allApps, picked: Set(picked), exceptions: Set(exceptions), menuBarApps: Set(menuBarApps)) }

    /// Starts, stops or updates the watching from the settings and the Accessibility permission.
    func apply() {
        let wanted = enabled && MenuBarMonitor.trusted
        if wanted { watcher.start(scope: scope, front: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) }
        else if running { watcher.stop() }
        if running != wanted { running = wanted; AppModel.log(wanted ? "Quit on close started" : "Quit on close stopped") }
    }

    /// Quits on the main thread: AppKit's own app objects live there.
    fileprivate func quit(_ pid: pid_t) {
        DispatchQueue.main.async {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
            AppModel.log("Quit on close: \(app.localizedName ?? app.bundleIdentifier ?? "app") closed its last window")
            app.terminate()
        }
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

        // Menu bar apps: running ones that declare LSUIElement, then listed ones not running.
        var bars: [TidyApp] = []
        var seenBars = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            guard let bundle = app.bundleIdentifier, bundle != own, let url = app.bundleURL,
                  let info = Bundle(url: url)?.infoDictionary, Self.flag(info["LSUIElement"]), !Self.flag(info["LSBackgroundOnly"]),
                  seenBars.insert(bundle).inserted else { continue }
            bars.append(TidyApp(bundle: bundle, running: app))
        }
        bars.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        menuBarCandidates = bars + menuBarApps.filter { !seenBars.contains($0) && NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
            .map { TidyApp(bundle: $0) }
    }

    static func flag(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return (text as NSString).boolValue }
        return false
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

    func setMenuBarApp(_ bundle: String, _ on: Bool) {
        menuBarApps.removeAll { $0 == bundle }
        if on { menuBarApps.append(bundle) }
        UserDefaults.standard.set(menuBarApps, forKey: Pref.quitOnCloseMenuBarApps)
        apply()
    }

    /// Installed apps in the current list, for the settings row.
    var listedCount: Int {
        list.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }.count
    }
    var menuBarAppCount: Int {
        menuBarApps.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }.count
    }
}

/// The watching itself. Everything below runs on its own thread; the main thread only hands it work.
private final class CloseWatcher {
    private weak var owner: QuitOnClose?
    private let thread = RunLoopThread(name: "Quit on close")
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let ownBundle = Bundle.main.bundleIdentifier

    // Thread-confined state.
    private var active = false
    private var scope = QuitScope()
    private var frontPID: pid_t = 0
    private var observers: [pid_t: (observer: AXObserver, element: AXUIElement)] = [:]
    private var attaching = Set<pid_t>()
    private var hadWindows = Set<pid_t>()
    private var closeRequests: [pid_t: Date] = [:]
    private var lastScheduled: [pid_t: Date] = [:]
    private var minimized: [pid_t: [AXUIElement]] = [:]
    private var pendingRefresh = Set<pid_t>()
    private struct Reread { let token = UUID(); let origin = Date(); var next = 0; var pending = false }
    private var rereads: [pid_t: Reread] = [:]
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private lazy var systemWide = AXUIElementCreateSystemWide()   // no timeout here: it would apply to every question

    init(owner: QuitOnClose) { self.owner = owner }

    // MARK: Entry points (any thread)

    func start(scope: QuitScope, front: pid_t) { thread.async { self.begin(scope: scope, front: front) } }
    func stop() { thread.async { self.end() } }
    func launched(_ app: NSRunningApplication) { let pid = app.processIdentifier; thread.async { self.attach(pid, attempt: 0) } }
    func terminated(_ pid: pid_t) { thread.async { self.detach(pid) } }
    func activated(_ app: NSRunningApplication) {
        let pid = app.processIdentifier, regular = app.activationPolicy == .regular
        thread.async {
            self.frontPID = pid
            guard self.active, regular, pid != self.ownPID else { return }
            if self.observers[pid] != nil { self.scheduleRefresh(pid) } else { self.attaching.remove(pid); self.attach(pid, attempt: 0) }
        }
    }
    func spaceChanged() {
        thread.async {
            for pid in Array(self.rereads.keys) { self.rereads[pid] = nil; self.refresh(pid) }
        }
    }

    // MARK: Starting and stopping

    private func begin(scope: QuitScope, front: pid_t) {
        self.scope = scope
        frontPID = front
        if !active {
            active = true
            installTap()
        }
        // Follow the settings: drop apps no longer covered, take on the newly covered ones.
        for pid in Array(observers.keys) where !covered(pid) { detach(pid) }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular { attach(app.processIdentifier, attempt: 0) }
    }

    private func end() {
        guard active else { return }
        active = false
        for pid in Array(observers.keys) { detach(pid) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(thread.runLoop, tapSource, .defaultMode) }
        tap = nil; tapSource = nil
        attaching.removeAll(); hadWindows.removeAll(); closeRequests.removeAll(); lastScheduled.removeAll()
        minimized.removeAll(); pendingRefresh.removeAll(); rereads.removeAll()
    }

    private func covered(_ pid: pid_t) -> Bool {
        guard pid != ownPID, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
        let info = app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary } ?? [:]
        return QuitOnCloseRules.covered(bundle: app.bundleIdentifier, url: app.bundleURL, policy: app.activationPolicy, own: ownBundle,
                                        uiElement: QuitOnClose.flag(info["LSUIElement"]), backgroundOnly: QuitOnClose.flag(info["LSBackgroundOnly"]),
                                        scope: scope)
    }

    // MARK: Observers

    private static let appNotifications = [kAXWindowCreatedNotification, kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification,
                                           kAXApplicationActivatedNotification, kAXApplicationDeactivatedNotification,
                                           kAXApplicationHiddenNotification, kAXApplicationShownNotification]
    private static let windowNotifications = [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification]
    private static let refreshing: Set<String> = [kAXWindowCreatedNotification, kAXWindowDeminiaturizedNotification, kAXApplicationShownNotification,
                                                  kAXApplicationActivatedNotification, kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification]

    private func attach(_ pid: pid_t, attempt: Int) {
        guard active, observers[pid] == nil, covered(pid) else { return }
        if attempt == 0 && attaching.contains(pid) { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, QuitOnCloseRules.messagingTimeout)
        // Ask for the windows, never the role: a role question turns on a Chromium app's full accessibility.
        var probe: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &probe) == .cannotComplete,
           attempt < QuitOnCloseRules.attachRetries.count {
            attaching.insert(pid)
            thread.after(QuitOnCloseRules.attachRetries[attempt]) { [weak self] in
                guard let self, self.active, NSRunningApplication(processIdentifier: pid)?.isTerminated == false else { return }
                self.attach(pid, attempt: attempt + 1)
            }
            return
        }
        attaching.remove(pid)
        var created: AXObserver?
        guard AXObserverCreate(pid, closeWatcherCallback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications { AXObserverAddNotification(observer, element, name as CFString, refcon) }
        CFRunLoopAddSource(thread.runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = (observer, element)
        refresh(pid)
    }

    private func detach(_ pid: pid_t) {
        if let entry = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(thread.runLoop, AXObserverGetRunLoopSource(entry.observer), .defaultMode)
        }
        attaching.remove(pid); hadWindows.remove(pid); closeRequests[pid] = nil; lastScheduled[pid] = nil
        minimized[pid] = nil; pendingRefresh.remove(pid); rereads[pid] = nil
    }

    fileprivate func handle(_ element: AXUIElement, _ notification: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard active, observers[pid] != nil else { return }
        switch notification {
        case kAXWindowMiniaturizedNotification:
            markMinimized(pid, element, true)
            return
        case kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification:
            markMinimized(pid, element, false)
        default: break
        }
        if Self.refreshing.contains(notification) { scheduleRefresh(pid) }
        let event: QuitOnCloseRules.Event = notification == kAXUIElementDestroyedNotification ? .windowDestroyed
            : notification == kAXApplicationHiddenNotification ? .appHidden : .other
        if QuitOnCloseRules.schedulesCheck(event, closeRequested: closeRequested(pid)) { scheduleChecks(pid) }
    }

    private func markMinimized(_ pid: pid_t, _ window: AXUIElement, _ on: Bool) {
        var list = minimized[pid] ?? []
        list.removeAll { CFEqual($0, window) }
        if on { list.append(window) }
        minimized[pid] = list.isEmpty ? nil : list
    }

    // MARK: Reading windows

    private func scheduleRefresh(_ pid: pid_t) {
        guard pendingRefresh.insert(pid).inserted else { return }
        thread.async { [weak self] in
            guard let self else { return }
            self.pendingRefresh.remove(pid)
            self.refresh(pid)
        }
    }

    /// Reads an app's windows: whether it ever showed one, and a close notification on each.
    private func refresh(_ pid: pid_t) {
        guard active, let element = observers[pid]?.element else { return }
        let windows = standardWindows(element)
        let server = windows.isEmpty ? hasWindow(pid, everything: false) : nil
        let found = !windows.isEmpty || server == true
        if found { hadWindows.insert(pid) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registered = 0
        if let observer = observers[pid]?.observer {
            for window in windows {
                var ok = false
                for name in Self.windowNotifications {
                    let result = AXObserverAddNotification(observer, window, name as CFString, refcon)
                    if name == kAXUIElementDestroyedNotification { ok = result == .success || result == .notificationAlreadyRegistered }
                }
                if ok { registered += 1 }
                if bool(window, kAXMinimizedAttribute) { markMinimized(pid, window, true) }
            }
        }
        // Windows that appear late, or that Accessibility could not yet watch, are read again.
        let again = found ? registered < max(windows.count, 1) : (!hadWindows.contains(pid) && registered == 0)
        guard again else { rereads[pid] = nil; return }
        var reread = rereads[pid] ?? Reread()
        if !reread.pending, reread.next < QuitOnCloseRules.windowRereads.count {
            let due = QuitOnCloseRules.windowRereads[reread.next] - Date().timeIntervalSince(reread.origin)
            let token = reread.token
            reread.next += 1; reread.pending = true
            thread.after(due) { [weak self] in
                guard let self, self.rereads[pid]?.token == token else { return }
                self.rereads[pid]?.pending = false
                self.refresh(pid)
            }
        }
        rereads[pid] = reread
    }

    private func standardWindows(_ app: AXUIElement) -> [AXUIElement] {
        var all = elements(app, kAXWindowsAttribute)
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let window = element(app, attribute), !all.contains(where: { CFEqual($0, window) }) { all.append(window) }
        }
        return all.filter { window in
            AXUIElementSetMessagingTimeout(window, QuitOnCloseRules.messagingTimeout)
            return QuitOnCloseRules.standardWindow(fullScreen: bool(window, "AXFullScreen"), minimized: bool(window, kAXMinimizedAttribute),
                                                   role: string(window, kAXRoleAttribute), subrole: string(window, kAXSubroleAttribute))
        }
    }

    /// Whether the window server shows a window that keeps the app. Nil when it cannot list windows.
    private func hasWindow(_ pid: pid_t, everything: Bool) -> Bool? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        var visible: Set<UInt64>??
        var drawsFor: [pid_t: Bool] = [:]
        for info in list {
            guard let window = WindowSample(info) else { continue }
            switch QuitOnCloseRules.kind(window, app: pid, everything: everything) {
            case .unrelated: continue
            case .shown:
                if window.pid == pid { return true }
                // Another process's window counts when it works for this app and is not an app of its own
                // (a sandboxed app's Open panel, not a program started from a terminal).
                let works = drawsFor[window.pid] ?? (responsiblePID(window.pid) == pid
                                                     && NSRunningApplication(processIdentifier: window.pid)?.activationPolicy != .regular)
                drawsFor[window.pid] = works
                if works { return true }
            case .ownOffscreen:
                if WindowServer.isMinimized(window.id) != false { return true }
                if visible == nil { visible = .some(WindowServer.visibleSpaces()) }
                if QuitOnCloseRules.offscreenKeepsApp(spaces: WindowServer.spaces(of: window.id), visible: visible!) { return true }
            }
        }
        return false
    }

    private func userFacingWindow(_ pid: pid_t, _ element: AXUIElement) -> Bool {
        let windows = standardWindows(element)
        if windows.contains(where: { bool($0, kAXMinimizedAttribute) }) { return true }
        if let server = hasWindow(pid, everything: true) { return server }
        return !windows.isEmpty
    }

    private func knownMinimized(_ pid: pid_t, _ element: AXUIElement) -> Bool {
        for window in standardWindows(element) where bool(window, kAXMinimizedAttribute) { markMinimized(pid, window, true) }
        return !(minimized[pid] ?? []).isEmpty
    }

    // MARK: Checking and quitting

    private func closeRequested(_ pid: pid_t) -> Bool {
        guard let at = closeRequests[pid] else { return false }
        return Date().timeIntervalSince(at) < QuitOnCloseRules.closeRequestGrace
    }

    private func scheduleChecks(_ pid: pid_t) {
        let now = Date()
        if let last = lastScheduled[pid], now.timeIntervalSince(last) < QuitOnCloseRules.checkSpacing { return }
        lastScheduled[pid] = now
        for delay in QuitOnCloseRules.checkDelays {
            thread.after(delay) { [weak self] in self?.check(pid, confirming: true) }
        }
    }

    private func check(_ pid: pid_t, confirming: Bool) {
        guard active, hadWindows.contains(pid), let element = observers[pid]?.element,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, covered(pid) else { return }
        let requested = closeRequested(pid)
        if app.isHidden && !requested { return }
        guard QuitOnCloseRules.shouldQuit(hadWindows: true, terminated: app.isTerminated, hidden: app.isHidden, closeRequested: requested,
                                          minimized: knownMinimized(pid, element), userFacingWindow: userFacingWindow(pid, element)) else { return }
        if let bundle = app.bundleIdentifier, hostsRunningApp(bundle) { return }
        if confirming {
            // One more look a moment later: leaving full screen and swapping windows leave short gaps.
            thread.after(QuitOnCloseRules.confirmDelay) { [weak self] in self?.check(pid, confirming: false) }
            return
        }
        hadWindows.remove(pid); closeRequests[pid] = nil; minimized[pid] = nil
        owner?.quit(pid)
    }

    /// A web app or app shim (Chrome's) names the browser that runs it; the browser stays while it runs.
    private func hostsRunningApp(_ host: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            guard !app.isTerminated, app.activationPolicy == .regular, app.bundleIdentifier != host, let url = app.bundleURL else { return false }
            return Bundle(url: url)?.object(forInfoDictionaryKey: "CrBundleIdentifier") as? String == host
        }
    }

    // MARK: Close hints: clicks on a close button and ⌘W

    private func installTap() {
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask,
                                           callback: closeTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            AppModel.log("Quit on close could not watch clicks (Accessibility needed); closes are still seen, a little later")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(thread.runLoop, source, .defaultMode)
        tap = port; tapSource = source
    }

    fileprivate func tapped(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, active { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard active else { return }
        let flags = event.flags
        if type == .leftMouseDown {
            guard flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty, AXIsProcessTrusted() else { return }
            clicked(at: event.location)
        } else if type == .keyDown {
            guard flags.contains(.maskCommand), !flags.contains(.maskControl) else { return }
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
            let typed = String(utf16CodeUnits: chars, count: length).lowercased()
            guard typed == "w" || (length == 0 && event.getIntegerValueField(.keyboardEventKeycode) == 13) else { return }
            let pid = frontPID
            guard pid != ownPID, NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { return }
            attach(pid, attempt: 0)
            guard observers[pid] != nil else { return }
            // ⌘W may close only a tab: a hint to look, not a close request.
            refresh(pid)
            scheduleChecks(pid)
        }
    }

    private func clicked(at point: CGPoint) {
        guard let window = frontWindow(at: point) else { return }
        guard eligible(window.pid), QuitOnCloseRules.inCloseArea(point, of: window.frame), closeButton(of: window, at: point) else { return }
        refresh(window.pid)
        closeRequests[window.pid] = Date()
        hadWindows.insert(window.pid)
        scheduleChecks(window.pid)
    }

    /// The front normal window under the point: the window that got the click.
    private func frontWindow(at point: CGPoint) -> WindowSample? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard let window = WindowSample(info), window.width >= QuitOnCloseRules.minimumSide, window.height >= QuitOnCloseRules.minimumSide,
                  window.frame.contains(point) else { continue }
            guard window.layer == 0, window.alpha > 0, window.pid != ownPID else { continue }
            return window
        }
        return nil
    }

    private func eligible(_ pid: pid_t) -> Bool {
        if observers[pid] != nil { return true }
        guard NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { return false }
        attach(pid, attempt: 0)
        return observers[pid] != nil
    }

    /// Whether the click is on the window's enabled close button, by Accessibility or, when it cannot
    /// point at one, by place alone (never on the minimize, zoom or full screen button).
    private func closeButton(of window: WindowSample, at point: CGPoint) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success, let hit else { return false }
        AXUIElementSetMessagingTimeout(hit, 0.15)
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard pid == window.pid else { return false }
        if let top = topLevelWindow(hit, pid), QuitOnCloseRules.standardWindow(fullScreen: bool(top, "AXFullScreen"), minimized: false,
                                                                                 role: string(top, kAXRoleAttribute), subrole: string(top, kAXSubroleAttribute)),
           let button = element(top, kAXCloseButtonAttribute) {
            AXUIElementSetMessagingTimeout(button, 0.15)
            let enabled = value(button, kAXEnabledAttribute) as? Bool ?? true
            if let frame = frame(button) { return enabled && frame.insetBy(dx: -4, dy: -4).contains(point) }
        }
        let otherButtons: Set<String> = [kAXMinimizeButtonSubrole, kAXZoomButtonSubrole, "AXFullScreenButton"]
        return QuitOnCloseRules.onCloseButton(point, of: window.frame) && !otherButtons.contains(string(hit, kAXSubroleAttribute) ?? "")
    }

    /// The window an element belongs to, never asking the app element itself anything.
    private func topLevelWindow(_ start: AXUIElement, _ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        func isApp(_ e: AXUIElement) -> Bool { CFEqual(e, app) }
        if !isApp(start), string(start, kAXRoleAttribute) == kAXWindowRole { return start }
        for attribute in [kAXWindowAttribute, kAXTopLevelUIElementAttribute] {
            if let window = element(start, attribute), !isApp(window), string(window, kAXRoleAttribute) == kAXWindowRole { return window }
        }
        var current = start
        for _ in 0..<8 {
            guard let parent = element(current, kAXParentAttribute), !isApp(parent) else { return nil }
            if string(parent, kAXRoleAttribute) == kAXWindowRole { return parent }
            current = parent
        }
        return nil
    }

    // MARK: Accessibility reads

    private func value(_ e: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var out: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, attribute as CFString, &out) == .success ? out : nil
    }
    private func element(_ e: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(e, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    private func elements(_ e: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let list = value(e, attribute) as? [AnyObject] else { return [] }
        return list.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }
    private func bool(_ e: AXUIElement, _ attribute: String) -> Bool { (value(e, attribute) as? Bool) ?? false }
    private func string(_ e: AXUIElement, _ attribute: String) -> String? { value(e, attribute) as? String }
    private func frame(_ e: AXUIElement) -> CGRect? {
        guard let p = value(e, kAXPositionAttribute), let s = value(e, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

private func closeWatcherCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<CloseWatcher>.fromOpaque(refcon).takeUnretainedValue().handle(element, notification as String)
}

private func closeTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo { Unmanaged<CloseWatcher>.fromOpaque(userInfo).takeUnretainedValue().tapped(type, event) }
    return Unmanaged.passUnretained(event)
}
