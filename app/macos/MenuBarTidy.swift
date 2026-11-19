import Cocoa
import ApplicationServices
import CoreAudio
import CoreMediaIO

/// A menu bar app that can be moved into the panel.
struct TidyApp: Identifiable, Equatable {
    let id: String      // bundle identifier
    let name: String
    let icon: NSImage
    var running = true

    init(bundle: String, running app: NSRunningApplication? = nil) {
        id = bundle
        let url = app?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
        name = app?.localizedName ?? url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundle
        icon = app?.icon ?? url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle)
        running = app != nil
    }
}

/// One app's status items as Accessibility reports them (top-left global coordinates).
struct StatusExtra {
    let pid: pid_t
    let bundle: String
    let frames: [CGRect]
}

/// Moves picked menu bar apps into the panel on macOS 27.
///
/// macOS 27 draws the menu bar itself and drops a status item that grows too wide, so the old trick of
/// pushing icons away with a huge spacer no longer works. Instead this holds the menu bar visibility
/// restriction behind assessment (exam) mode, as Hidden Bar does (MenuBarVisibilityShim): every running
/// app is allowed except the picked ones, and macOS hides those and reflows the bar.
///
/// What macOS 27 imposes, all handled here the way Hidden Bar found it must be:
/// - Hiding is per app: an app with several icons hides them all.
/// - macOS's own items (clock, Wi-Fi, Control Center…) always stay visible (system items 0..<64).
/// - The allow-list names apps, so an app that starts later is added before macOS hides it for good.
/// - Assessment mode makes macOS ignore the clock: a click on it lifts the restriction for a moment and
///   is replayed, so Notification Center still opens.
/// - It also hides the capsule naming the app that records: while a microphone or camera is in use,
///   nothing is hidden.
/// - macOS knows an app by bundle id only in /Applications; run from elsewhere it would hide this app's
///   own tower too, so the feature stays off there.
final class MenuBarTidy: ObservableObject {
    static let shared = MenuBarTidy()
    static let systemItems = Array(0..<64)
    /// Other menu bar managers hold the same restriction; whichever activates last wins, so this one waits.
    static let otherManagers = ["com.dwarvesv.minimalbar": "Hidden Bar", "com.stonerl.Thaw": "Thaw",
                                "com.jordanbaird.Ice": "Ice", "com.surteesstudios.Bartender": "Bartender"]

    @Published private(set) var status = "Off"
    /// Apps with icons in the menu bar now, and every picked app (for Settings).
    @Published private(set) var menuBarApps: [TidyApp] = []
    /// Picked apps that are running, in the order picked (for the panel).
    @Published private(set) var panelApps: [TidyApp] = []
    /// Apps outside /Applications that own icons: macOS 27 may hide them although they are allowed.
    @Published private(set) var unknownToMacOS: [String] = []
    /// The picked bundle ids, for Settings' switches.
    @Published private(set) var picked: [String] = []
    /// Shown under the panel icons when opening an app's menu did not work.
    @Published private(set) var notice: String?

    /// Called whenever the menu bar changes, so the cats look for space again.
    var layoutChanged: (() -> Void)?

    let available = CIMVisibilityIsAvailable()
    let own = Bundle.main.bundleIdentifier ?? "local.catsinmenubar"
    private let defaults = UserDefaults.standard
    private var assertion: Any?
    private var held: [String]?          // the allow-list of the held restriction
    private var activating = false
    private var generation = 0           // the activation whose answer counts
    private var again = false            // the wanted list changed while an activation was in flight
    private var waiters: [(Bool) -> Void] = []
    private var failure: (list: [String], at: Double)?
    private var temporary: String?       // shown while its menu is open from the panel
    private var liftAll = false          // the clock is being pressed
    private var captureActive = false
    private var captureTimer: Timer?
    private var running: NSKeyValueObservation?
    private var pending: DispatchWorkItem?
    private var session = 0
    private var started = false

    var enabled: Bool { defaults.bool(forKey: Pref.tidy) }
    var chosen: [String] { defaults.stringArray(forKey: Pref.tidyApps) ?? [] }
    /// Apps macOS is hiding right now; their icons may still report old frames, which are not obstacles.
    var hiddenNow: Set<String> { held == nil ? [] : Set(chosen).subtracting([temporary].compactMap { $0 }) }
    var busy: Bool { temporary != nil || liftAll }

    static func inApplications(_ url: URL = Bundle.main.bundleURL) -> Bool {
        url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix("/Applications/")
    }

    /// Every running app except the hidden ones, and always this one.
    static func allowList(running: [String], hidden: Set<String>, own: String) -> [String] {
        Array(Set(running).subtracting(hidden).union([own])).sorted()
    }

    func start() {
        guard !started else { return }
        started = true
        picked = chosen
        // NSWorkspace's launch notifications skip agents, and most menu bar apps are agents.
        running = NSWorkspace.shared.observe(\.runningApplications, options: []) { [weak self] _, _ in
            DispatchQueue.main.async { self?.soon() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.soon()
        }
        refresh()
    }

    /// App launches and preference changes come in bursts.
    private func soon() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Applies the wanted restriction, and reads which apps own icons when on or when Settings lists them.
    func refresh(list: Bool = false) {
        updateCapture()
        reconcile()
        guard list || enabled, MenuBarMonitor.trusted else { return }
        let apps = NSWorkspace.shared.runningApplications
        DispatchQueue.global(qos: .utility).async {
            let extras = Self.readExtras(apps)
            DispatchQueue.main.async { self.update(extras: extras) }
        }
    }

    /// Fresh status item owners (from the cats' scans too).
    func update(extras: [StatusExtra]) {
        let apps = NSWorkspace.shared.runningApplications
        var byBundle: [String: NSRunningApplication] = [:]
        for app in apps { if let id = app.bundleIdentifier, byBundle[id] == nil { byBundle[id] = app } }
        let picked = chosen
        if picked != self.picked { self.picked = picked }
        let owners = Set(extras.map(\.bundle)).subtracting(MenuBarMonitor.systemBars).subtracting([own])
        // Names and icons are looked up only when the set of apps changes (scans run every few seconds).
        let listed = owners.union(picked)
        if listed != Set(menuBarApps.map(\.id)) || menuBarApps.contains(where: { $0.running != (byBundle[$0.id] != nil) }) {
            menuBarApps = listed.map { TidyApp(bundle: $0, running: byBundle[$0]) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        let panel = picked.filter { byBundle[$0] != nil }
        if panel != panelApps.map(\.id) { panelApps = panel.map { TidyApp(bundle: $0, running: byBundle[$0]) } }
        let outside = owners.compactMap { id -> String? in
            guard let app = byBundle[id], let url = app.bundleURL, !Self.inApplications(url), !url.path.hasPrefix("/System/") else { return nil }
            return app.localizedName ?? id
        }.sorted()
        if outside != unknownToMacOS { unknownToMacOS = outside }
    }

    func setPicked(_ bundle: String, _ on: Bool) {
        var list = chosen.filter { $0 != bundle }
        if on { list.append(bundle) }
        defaults.set(list, forKey: Pref.tidyApps)
        picked = list
        refresh(list: true)
    }

    // MARK: The restriction

    /// What should be held now; nil shows everything.
    private func wanted() -> (list: [String]?, reason: String) {
        let apps = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        guard enabled else { return (nil, "Off") }
        guard available else { return (nil, "Needs macOS 27: its menu bar API is missing here.") }
        guard Self.inApplications() else { return (nil, "Move Cats in Menubar to the Applications folder first. Run from elsewhere, macOS would hide its tower too.") }
        if let other = apps.lazy.compactMap({ Self.otherManagers[$0] }).first { return (nil, "Paused while \(other) is running: both would hide icons at once.") }
        guard MenuBarMonitor.trusted else { return (nil, "Needs Accessibility access to open hidden apps.") }
        if captureActive { return (nil, "Showing every icon while a microphone or camera is in use.") }
        if liftAll { return (nil, "Opening Notification Center…") }
        let hidden = Set(chosen).subtracting([temporary].compactMap { $0 })
        let count = Set(apps).intersection(hidden).count
        guard count > 0 else { return (nil, chosen.isEmpty ? "On. Pick apps below." : "On. None of the picked apps is running.") }
        return (Self.allowList(running: apps, hidden: hidden, own: own), "Hiding \(count) app\(count == 1 ? "" : "s").")
    }

    /// Brings the held restriction in line with what is wanted. `done` runs once it is applied.
    func reconcile(_ done: ((Bool) -> Void)? = nil) {
        let (list, reason) = wanted()
        if status != reason { status = reason; AppModel.log("Menu bar tidy: \(reason)") }
        updateClockMonitor(list != nil)
        if let done { waiters.append(done) }
        // One activation at a time; the newest wanted list follows when it lands.
        if activating { again = true; return }
        guard let list else { drop(); finish(true); return }
        if list == held, assertion != nil { finish(true); return }
        if let failure, failure.list == list, ProcessInfo.processInfo.systemUptime - failure.at < 30 { drop(); finish(false); return }
        activating = true
        generation += 1
        let attempt = generation
        // macOS normally answers within milliseconds; one that never answers must not keep icons hidden.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.activating, attempt == self.generation else { return }
            self.generation += 1
            self.activated(nil, list, "macOS did not answer")
        }
        CIMVisibilityActivate(Self.systemItems.map { NSNumber(value: $0) }, list) { [weak self] handle, error in
            guard let self else { return }
            // An answer after the timeout (or after a newer request) is let go at once.
            guard attempt == self.generation else { if let handle { CIMVisibilityInvalidate(handle) }; return }
            self.activated(handle, list, error?.localizedDescription ?? "unknown error")
        }
    }

    private func activated(_ handle: Any?, _ list: [String], _ problem: String) {
        activating = false
        if let handle {
            let old = assertion
            assertion = handle; held = list; failure = nil
            if let old { CIMVisibilityInvalidate(old) }
        } else {
            // Failing open: an older list would also hide every app started since. Retried after a while.
            failure = (list, ProcessInfo.processInfo.systemUptime)
            drop()
            status = "macOS refused: \(problem). Trying again shortly."
            AppModel.log("Menu bar tidy: \(status)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 31) { [weak self] in self?.reconcile() }
        }
        layoutChanged?()
        // Waiters are told once the newest list is applied, not this older one.
        if again { again = false; reconcile(); return }
        finish(handle != nil)
    }

    private func finish(_ ok: Bool) {
        let list = waiters; waiters = []
        list.forEach { $0(ok) }
    }

    private func drop() {
        guard let old = assertion else { held = nil; return }
        assertion = nil; held = nil
        CIMVisibilityInvalidate(old)
        layoutChanged?()
    }

    /// Shows everything at once (Quit, sleep). macOS also drops it when this process exits.
    func stop() {
        drop()
        captureTimer?.invalidate(); captureTimer = nil
        updateClockMonitor(false)
    }

    // MARK: Opening a hidden app's menu from the panel

    /// Shows the one app, presses its icon, waits while its menu or panel is open, then hides it again.
    func open(_ bundle: String) {
        session += 1
        let id = session
        notice = nil
        let lifting = hiddenNow.contains(bundle)
        temporary = lifting ? bundle : nil
        AppModel.log("Menu bar tidy: opening \(bundle)")
        reconcile { [weak self] ok in
            guard let self, id == self.session else { return }
            guard ok else { return self.end(id, "macOS did not show \(bundle)") }
            self.layoutChanged?()
            // macOS applies a lifted restriction a moment after it answers.
            DispatchQueue.main.asyncAfter(deadline: .now() + (lifting ? 0.05 : 0)) {
                self.press(id, bundle, since: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    private func press(_ id: Int, _ bundle: String, since: Double) {
        guard id == session else { return }
        MenuBarItemPresser.press(bundle: bundle) { [weak self] outcome in
            guard let self, id == self.session else { return }
            switch outcome {
            case .pressed:
                self.watch(id, bundle, pressedAt: ProcessInfo.processInfo.systemUptime, menuSeen: false, activeSeen: false)
            case .noItem where ProcessInfo.processInfo.systemUptime - since < 1.5:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.press(id, bundle, since: since) }
            case .noItem:
                self.end(id, "\(self.name(bundle)) has no icon in the menu bar right now.")
            case .noPress:
                // Its icon stays in the menu bar for a while so it can be clicked there.
                self.notice = "\(self.name(bundle)) does not open from here. Its icon stays in the menu bar for 15 seconds."
                AppModel.log("Menu bar tidy: \(bundle) takes no press; shown for 15 s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.end(id, nil) }
            }
        }
    }

    /// A menu is a window at the pop-up menu level; an app that opens a panel instead keeps focus while it is up.
    private func watch(_ id: Int, _ bundle: String, pressedAt: Double, menuSeen: Bool, activeSeen: Bool) {
        guard id == session else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - pressedAt
        var menuSeen = menuSeen, activeSeen = activeSeen
        if MenuBarItemPresser.isMenuOpen(bundle: bundle) { menuSeen = true }
        else if menuSeen { return end(id, nil) }
        if menuSeen {
            if elapsed > 600 { return end(id, nil) }
        } else if elapsed > 0.8 {
            if MenuBarItemPresser.isActive(bundle: bundle) { activeSeen = true }
            else if activeSeen || elapsed > 2.8 { return end(id, nil) }
            if elapsed > 15 { return end(id, nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.watch(id, bundle, pressedAt: pressedAt, menuSeen: menuSeen, activeSeen: activeSeen)
        }
    }

    private func end(_ id: Int, _ problem: String?) {
        guard id == session else { return }
        session += 1
        if let problem { notice = problem; AppModel.log("Menu bar tidy: \(problem)") }
        temporary = nil
        reconcile()
    }

    private func name(_ bundle: String) -> String { panelApps.first { $0.id == bundle }?.name ?? bundle }

    // MARK: Microphone and camera

    private func updateCapture() {
        let want = enabled && available
        if want && captureTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.pollCapture() }
            RunLoop.main.add(timer, forMode: .common); captureTimer = timer
            pollCapture()
        } else if !want, let timer = captureTimer {
            timer.invalidate(); captureTimer = nil
            captureActive = false
        }
    }

    private func pollCapture() {
        DispatchQueue.global(qos: .utility).async {
            let active = CaptureActivity.isActive
            DispatchQueue.main.async {
                guard active != self.captureActive else { return }
                self.captureActive = active
                AppModel.log("Menu bar tidy: microphone or camera \(active ? "in use" : "free")")
                self.reconcile()
            }
        }
    }

    // MARK: The clock

    private var clockMonitor: Any?
    private var clockDown: CGRect?
    private var clockUp: CGPoint?        // a release seen before the press was checked
    private var clockClick = 0
    private var replayingUntil = 0.0

    private func updateClockMonitor(_ on: Bool) {
        if on, clockMonitor == nil {
            clockMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                self?.clockEvent(event)
            }
        } else if !on, !liftAll, let monitor = clockMonitor {
            NSEvent.removeMonitor(monitor); clockMonitor = nil; clockDown = nil
        }
    }

    /// While hidden, macOS ignores clicks on the clock; a click that begins and ends on it (with
    /// Notification Center closed, since such a click closes it by itself) is replayed with nothing hidden.
    /// The Accessibility reads run off the main thread (a busy system process must not stall the cats);
    /// a mouse-up that arrives before they finish is kept and decided when they do.
    private func clockEvent(_ event: NSEvent) {
        guard ProcessInfo.processInfo.systemUptime > replayingUntil, !liftAll, let location = event.cgEvent?.location else { return }
        switch event.type {
        case .leftMouseDown:
            clockDown = nil; clockUp = nil
            clockClick += 1
            let click = clockClick
            guard event.modifierFlags.isDisjoint(with: [.command, .control]),
                  MenuBarItemPresser.menuBarBands().contains(where: { $0.contains(location) }) else { return }
            DispatchQueue.global(qos: .userInteractive).async {
                let clock = SystemClock.frames().first(where: { $0.contains(location) })
                let open = clock != nil && SystemClock.notificationCenterOpen()
                DispatchQueue.main.async {
                    guard click == self.clockClick, let clock, !open else { return }
                    self.clockDown = clock
                    if let up = self.clockUp { self.clockReleased(at: up) }
                }
            }
        case .leftMouseUp:
            if clockDown == nil { clockUp = location } else { clockReleased(at: location) }
        default: break
        }
    }

    private func clockReleased(at location: CGPoint) {
        defer { clockDown = nil; clockUp = nil; clockClick += 1 }
        if let clock = clockDown, clock.contains(location) { pressClock(clock, retry: true) }
    }

    private func pressClock(_ clock: CGRect, retry: Bool) {
        liftAll = true
        // The click is replayed only once nothing is hidden (after an activation in flight, if any).
        reconcile { [weak self] _ in
            // MenuBarAgent ignores a press that arrives before it applied the lift.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard let self else { return }
                self.replayingUntil = ProcessInfo.processInfo.systemUptime + 0.3
                SystemClock.click(at: CGPoint(x: clock.midX, y: clock.midY))
                // Measured by Hidden Bar on 27.2: the panel stays open when hiding resumes right after the press.
                DispatchQueue.main.asyncAfter(deadline: .now() + (retry ? 0.05 : 0.6)) {
                    self.liftAll = false
                    self.reconcile()
                    guard retry else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        DispatchQueue.global(qos: .userInteractive).async {
                            let open = SystemClock.notificationCenterOpen()
                            DispatchQueue.main.async { if !open && !self.liftAll { self.pressClock(clock, retry: false) } }
                        }
                    }
                }
            }
        }
    }

    // MARK: Keeping the tower leftmost

    private var lastMove = -100.0
    private var failedMoves = 0
    private var leftCount = -1

    /// Status items left of `own` (its AppKit frame) on its menu bar, ignoring hidden apps and this app.
    static func itemsLeft(of own: NSRect, extras: [StatusExtra], skip: Set<String>, ownPid: pid_t, band: CGRect) -> [CGRect] {
        extras.filter { $0.pid != ownPid && !skip.contains($0.bundle) }.flatMap(\.frames).filter { frame in
            band.contains(CGPoint(x: frame.midX, y: frame.midY)) && frame.maxX <= own.minX + 2
        }
    }

    /// With the tower leftmost, other apps' icons (also one shown for a moment from the panel) appear
    /// right of it, away from the cats. macOS 27 keeps the order in a protected file, so the tower is
    /// ⌘-dragged left of the leftmost icon, as a person would (the pointer moves for a moment).
    func keepLeftmost(own: NSRect, extras: [StatusExtra]) {
        guard enabled, defaults.bool(forKey: Pref.tidyLeftmost), !busy, MenuBarMonitor.trusted,
              let primary = NSScreen.screens.first?.frame.maxY,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: own.midX, y: own.midY)) }) else { return }
        let band = MenuBarItemPresser.menuBarBands().first { $0.minX == screen.frame.minX && $0.width == screen.frame.width } ?? .zero
        let left = Self.itemsLeft(of: own, extras: extras, skip: hiddenNow, ownPid: ProcessInfo.processInfo.processIdentifier, band: band)
        if left.count != leftCount {
            leftCount = left.count
            AppModel.log("Menu bar tidy: \(left.isEmpty ? "the tower is leftmost" : "\(left.count) icon(s) left of the tower")")
        }
        guard let leftmost = left.min(by: { $0.minX < $1.minX }) else { failedMoves = 0; return }
        let now = ProcessInfo.processInfo.systemUptime
        // Never while the user holds a button, and give up after a few tries that changed nothing.
        guard now - lastMove > 15, failedMoves < 3, NSEvent.pressedMouseButtons == 0 else { return }
        lastMove = now; failedMoves += 1
        let from = CGPoint(x: own.midX, y: primary - own.midY)
        let to = CGPoint(x: leftmost.minX + 2, y: leftmost.midY)
        AppModel.log("Menu bar tidy: moving the tower left of \(left.count) icon(s)")
        StatusItemDrag.perform(from: from, to: to) { [weak self] in self?.layoutChanged?() }
    }

    // MARK: Accessibility reads

    /// Each app's status items (the cats' scan collects the same on its own pass).
    /// Runs off the main thread, so our own process is never asked (see MenuBarMonitor.scan).
    static func readExtras(_ apps: [NSRunningApplication]) -> [StatusExtra] {
        let me = ProcessInfo.processInfo.processIdentifier
        return apps.compactMap { app in
            guard app.processIdentifier != me, let id = app.bundleIdentifier, app.bundleURL?.pathExtension == "app" || MenuBarMonitor.systemBars.contains(id) else { return nil }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard let bar = MenuBarItemPresser.value(of: element, kAXExtrasMenuBarAttribute),
                  CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
            let frames = MenuBarItemPresser.children(of: bar as! AXUIElement).compactMap(MenuBarItemPresser.frame(of:))
            return StatusExtra(pid: app.processIdentifier, bundle: id, frames: frames)
        }
    }
}

/// The panel's two rows of hidden apps: how many icons show, and whether a "+N" takes the last spot.
enum PanelGrid {
    static let perRow = 7, rows = 2
    static func layout(count: Int, perRow: Int = perRow, rows: Int = rows) -> (shown: Int, overflow: Int) {
        let room = perRow * rows
        return count <= room ? (count, 0) : (room - 1, count - room + 1)
    }
}

/// Whether any app records from a microphone or uses a camera: the public state the recording
/// indicators reflect, with no microphone or camera permission. Based on Hidden Bar's CaptureActivityMonitor.
enum CaptureActivity {
    /// Listeners macOS shows no recording capsule for: corespeechd keeps the microphone open for
    /// "Siri" / "Hey Siri" for minutes or hours at a time, which would keep every icon shown.
    static let quietListeners: Set<String> = ["com.apple.CoreSpeech"]

    static var isActive: Bool {
        if #available(macOS 14.2, *) {
            // Each process's "is running input"; a device's "running somewhere" also fires for a headset only playing.
            let recording = audioObjects(kAudioHardwarePropertyProcessObjectList)
                .filter { audioFlag(kAudioProcessPropertyIsRunningInput, of: $0) }
                .map { audioBundle(of: $0) }
            if counts(recording) { return true }
        }
        return cameras().contains(where: cameraRunning)
    }

    /// Whether the processes recording now (by bundle id, nil when unknown) count as a microphone in use.
    static func counts(_ recording: [String?]) -> Bool {
        recording.contains { $0.map { !quietListeners.contains($0) } ?? true }
    }

    @available(macOS 14.2, *)
    private static func audioBundle(of object: AudioObjectID) -> String? {
        var address = audioAddress(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioObjects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = audioAddress(selector)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func audioFlag(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> Bool {
        var address = audioAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func cameraAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func cameras() -> [CMIOObjectID] {
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private static func cameraRunning(_ camera: CMIOObjectID) -> Bool {
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        var value: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(camera, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr && value != 0
    }
}

/// The menu bar clock and Notification Center, through public Accessibility and window-list reads.
/// Based on Hidden Bar's SystemMenuBarClock.
enum SystemClock {
    static let clockIdentifier = "com.apple.menuextra.clock"
    // Only the open panel shows Edit Widgets; a notification left on screen has the same window bounds.
    static let panelControlIdentifier = "widget-editor-button"

    /// Clock frames in top-left global coordinates (one per display). Each item sits in a group: bar > group > item.
    static func frames() -> [CGRect] {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else { return [] }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let bar = MenuBarItemPresser.value(of: app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var found: [CGRect] = []
        for group in MenuBarItemPresser.children(of: bar as! AXUIElement) {
            for item in [group] + MenuBarItemPresser.children(of: group)
            where MenuBarItemPresser.value(of: item, "AXIdentifier") as? String == clockIdentifier {
                if let frame = MenuBarItemPresser.frame(of: item) { found.append(frame) }
            }
        }
        return found
    }

    /// AXPress opens and at once closes the panel on 27.2, so a click is posted instead. No modifiers are inherited.
    static func click(at point: CGPoint) {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return }
        for event in [down, up] { event.flags = []; event.setIntegerValueField(.mouseEventClickState, value: 1) }
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }

    /// The panel is a window as tall as the screen owned by Notification Center.
    static func notificationCenterOpen() -> Bool {
        let owners = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").map(\.processIdentifier))
        let minimum = (NSScreen.screens.map(\.frame.height).min() ?? 0) / 2
        guard !owners.isEmpty, let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let up = windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, owners.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.height >= minimum
        }
        guard up else { return false }
        var identifiers: [String] = []
        for pid in owners {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.5)
            guard let windows = MenuBarItemPresser.value(of: app, kAXWindowsAttribute) as? [AXUIElement] else { return true }
            for window in windows { collect(window, depth: 0, into: &identifiers) }
        }
        return identifiers.contains(panelControlIdentifier)
    }

    private static func collect(_ element: AXUIElement, depth: Int, into found: inout [String]) {
        if let identifier = MenuBarItemPresser.value(of: element, "AXIdentifier") as? String { found.append(identifier) }
        guard depth < 5 else { return }
        for child in MenuBarItemPresser.children(of: element) { collect(child, depth: depth + 1, into: &found) }
    }
}

/// A ⌘-drag of a status item, posted as mouse events, then the pointer goes back where it was.
enum StatusItemDrag {
    static func perform(from: CGPoint, to: CGPoint, done: @escaping () -> Void) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return done() }
        let home = CGEvent(source: nil)?.location ?? from
        func event(_ type: CGEventType, _ point: CGPoint) -> CGEvent? {
            let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            e?.flags = .maskCommand
            return e
        }
        let steps = 10
        var events: [CGEvent] = []
        if let down = event(.leftMouseDown, from) { events.append(down) }
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            if let drag = event(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y)) { events.append(drag) }
        }
        if let up = event(.leftMouseUp, to) { events.append(up) }
        guard events.count == steps + 2 else { return done() }
        func post(_ index: Int) {
            guard index < events.count else {
                CGWarpMouseCursorPosition(home)
                CGAssociateMouseAndMouseCursorPosition(1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: done)
                return
            }
            events[index].post(tap: .cghidEventTap)
            // macOS needs a moment after the press before the item lifts and follows.
            DispatchQueue.main.asyncAfter(deadline: .now() + (index == 0 ? 0.15 : 0.02)) { post(index + 1) }
        }
        post(0)
    }
}
