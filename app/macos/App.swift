import Cocoa
import SwiftUI

final class AppModel: ObservableObject {
    @Published var debug = false { didSet { changed?() } }
    @Published var status = "Checking menu layout…" { didSet { if status != oldValue { AppModel.log(status) } } }
    @Published var catSummary = "Looking for empty space…"
    @Published var catsAway = false     // called into the cat tower
    @Published var displays: [DisplayInfo] = []
    @Published var moveStatus: String?  // "Moving to …" while the cats walk home to change screens
    @Published var shownDisplay = ""    // the display the cats are on now
    @Published var power = PowerLevel.full
    @Published var lineup: [CatAppearance] = []
    @Published var keepLineup = false
    var configureCat: ((Int, CatAppearance) -> Void)?
    var shuffleCats: (() -> Void)?
    var rememberCats: ((Bool) -> Void)?
    var home: (() -> Void)?
    @Published var access = MenuBarMonitor.trusted { didSet { if access != oldValue { AppModel.log("Accessibility: \(access)") } } }
    static let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CatsInMenubar.log")
    // Geometry/status only, so live behavior can be checked without screen capture.
    static func log(_ line: String) {
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) { handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close() }
        else { try? Data(text.utf8).write(to: logURL) }
    }
    var changed: (() -> Void)?
    var play: (() -> Void)?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let colony = Colony()
    let monitor = MenuBarMonitor()
    let system = SystemMonitor()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var overlay: NSPanel?
    var habitatView: HabitatView?
    lazy var settings = SettingsWindowController(model: model)
    var animationTimer: Timer?
    var layoutTimer: Timer?
    var lastTick = ProcessInfo.processInfo.systemUptime
    var epoch = 0
    var lastScreen: NSRect = .zero
    // Changing screens: the cats walk home on this one, then come out on the next.
    var shownDisplay: String? { didSet { model.shownDisplay = shownDisplay ?? "" } }
    var moveTarget: String?
    var moveStarted = 0.0
    var pendingLetOut = false
    var lastHeight: CGFloat = 0
    var suspended = false
    var hovering = false
    var monitorInterval = 0.0
    var governor = PowerGovernor()
    var appliedLineup: Data?
    let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: Pref.defaults)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = TowerIcon.menuBar()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.toolTip = "Cats in Menubar"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        popover.behavior = .transient
        let host = NSHostingController(rootView: DashboardView(model: model, system: system,
            openSettings: { [weak self] in self?.showSettings() }, play: { [weak self] in self?.play() }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { [weak self] _ in
            self?.system.detailed = false
        }
        WiFiNamePermission.shared.changed = { [weak self] in self?.system.sample() }
        AppModel.log("Launched pid \(ProcessInfo.processInfo.processIdentifier), Accessibility: \(MenuBarMonitor.trusted)")
        model.changed = { [weak self] in self?.applyOptions() }
        model.play = { [weak self] in self?.play() }
        model.home = { [weak self] in self?.toggleHome() }
        // Each launch starts with cats outside. A saved lineup overrides only appearance, never location.
        defaults.set(false, forKey: "catsHome")
        model.keepLineup = defaults.bool(forKey: Pref.fixedLineup)
        model.configureCat = { [weak self] i, appearance in self?.configureCat(i, appearance) }
        model.shuffleCats = { [weak self] in self?.shuffleCats() }
        model.rememberCats = { [weak self] enabled in self?.rememberCats(enabled) }
        system.updated = { [weak self] stats in self?.systemUpdated(stats) }
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: UserDefaults.didChangeNotification, object: nil)
        applyOptions()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(layoutChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(layoutChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(layoutChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
        startTimers()
        scan()
        let updater = Updater.shared
        updater.isBusy = { [weak self] in self?.habitatView?.dragging != nil || self?.habitatView?.lasering == true }
        updater.start()
        if CommandLine.arguments.contains("--install-self") { updater.installSelf() }
        ScrollDirection.shared.apply()
        if !defaults.bool(forKey: "hasLaunched") || !MenuBarMonitor.trusted {
            showSettings(); defaults.set(true, forKey: "hasLaunched")
        }
    }
    /// Animation and layout timers run at the current power level's pace.
    /// App switches and display changes still trigger an immediate scan; the timer only catches slower changes.
    func startTimers() {
        animationTimer?.invalidate(); layoutTimer?.invalidate()
        let animate = Timer(timeInterval: model.power.frameInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(animate, forMode: .common); animationTimer = animate
        let layout = Timer(timeInterval: model.power.scanInterval, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(layout, forMode: .common); layoutTimer = layout
    }
    @objc func powerStateChanged() { DispatchQueue.main.async { self.systemUpdated(self.system.stats) } }
    @objc func preferencesChanged() { DispatchQueue.main.async { self.applyOptions() } }
    var paused: Bool { defaults.bool(forKey: Pref.paused) }
    /// Manual quiet time, or the nightly schedule when enabled.
    var quietNow: Bool {
        if defaults.bool(forKey: Pref.quiet) { return true }
        guard defaults.bool(forKey: Pref.nightQuiet) else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        let from = defaults.integer(forKey: Pref.nightFrom), to = defaults.integer(forKey: Pref.nightTo)
        return from <= to ? (hour >= from && hour < to) : (hour >= from || hour < to)
    }
    func applyOptions() {
        let previousCount = colony.cats.count
        colony.setCount(defaults.integer(forKey: Pref.count)); colony.quiet = quietNow
        if previousCount != colony.cats.count { appliedLineup = nil }
        if defaults.bool(forKey: Pref.fixedLineup), let data = defaults.data(forKey: Pref.lineup), data != appliedLineup,
           let appearances = try? JSONDecoder().decode([CatAppearance].self, from: data) {
            habitatView?.endDrag()
            colony.applyAppearances(appearances)
            appliedLineup = data
        }
        syncLineup()
        colony.activity = defaults.integer(forKey: Pref.activity)
        let toyColor = defaults.integer(forKey: Pref.toyColor)
        colony.toyColor = Toy.colors.indices.contains(toyColor) ? toyColor : nil
        habitatView?.showLanes = model.debug
        system.wantsApps = defaults.integer(forKey: Pref.topApps) > 0 && (defaults.bool(forKey: Pref.showCPU) || defaults.bool(forKey: Pref.showMemory))
        system.wantsWiFi = defaults.bool(forKey: Pref.showNetwork)
        systemUpdated(system.stats)
        let interval = max(defaults.double(forKey: Pref.interval), model.power.sampleFloor)
        if interval != monitorInterval { monitorInterval = interval; system.start(interval: interval) }
        if paused { overlay?.orderOut(nil) } else { scan() }
        ScrollDirection.shared.apply()
    }
    func syncLineup() {
        let appearances = colony.cats.map(\.appearance)
        if model.lineup != appearances { model.lineup = appearances }
        model.keepLineup = defaults.bool(forKey: Pref.fixedLineup)
    }
    func saveLineup() {
        // Preserve an inactive third slot when the user temporarily reduces the cat count.
        var appearances = (defaults.data(forKey: Pref.lineup).flatMap { try? JSONDecoder().decode([CatAppearance].self, from: $0) }) ?? []
        for i in colony.cats.indices {
            if appearances.indices.contains(i) { appearances[i] = colony.cats[i].appearance }
            else { appearances.append(colony.cats[i].appearance) }
        }
        if let data = try? JSONEncoder().encode(appearances) {
            appliedLineup = data
            defaults.set(data, forKey: Pref.lineup)
        }
    }
    func configureCat(_ index: Int, _ appearance: CatAppearance) {
        guard colony.cats.indices.contains(index) else { return }
        habitatView?.endDrag()
        colony.cats[index].appearance = appearance
        colony.reconcile()
        saveLineup()
        defaults.set(true, forKey: Pref.fixedLineup)
        syncLineup()
        habitatView?.needsDisplay = true
    }
    func rememberCats(_ enabled: Bool) {
        if enabled { saveLineup() }
        defaults.set(enabled, forKey: Pref.fixedLineup)
        syncLineup()
    }
    func shuffleCats() {
        habitatView?.endDrag()
        colony.shuffle()
        model.catsAway = false
        defaults.set(false, forKey: "catsHome")
        defaults.set(false, forKey: Pref.fixedLineup)
        syncLineup()
        habitatView?.needsDisplay = true
    }
    func systemUpdated(_ stats: SystemStats) {
        // Plenty of CPU headroom: lively, smooth cats. Busy, hot or Low Power Mode: they rest and the app slows down.
        let level = defaults.bool(forKey: Pref.adaptivePower)
            ? governor.update(cpu: stats.cpu, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, thermal: stats.thermal)
            : .full
        colony.mood = defaults.bool(forKey: Pref.adaptivePower) ? governor.liveliness : 0
        if level != model.power {
            AppModel.log("Power: \(level.label) (CPU \(Int(governor.smoothed * 100))%)")
            model.power = level
            startTimers()
            let interval = max(defaults.double(forKey: Pref.interval), level.sampleFloor)
            if interval != monitorInterval { monitorInterval = interval; system.start(interval: interval) }
        }
        colony.quiet = quietNow
    }
    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        // Fresh app lists and Wi-Fi details while the panel is open. The Wi-Fi name needs Location
        // Services, asked once, the first time the panel opens on Wi-Fi.
        system.detailed = true
        system.sample()
        if system.stats.wifi != nil && defaults.bool(forKey: Pref.showNetwork) { WiFiNamePermission.shared.askIfNeeded() }
        // Size the panel before showing it; growing after it opens pushes it up behind the menu bar.
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            popover.contentSize = view.fittingSize
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let frame = popover.contentViewController?.view.window?.frame, let screen = button.window?.screen {
            AppModel.log("Panel frame \(frame) screen visible top \(screen.visibleFrame.maxY)")
        }
    }
    @objc func play() { guard !paused else { return }; colony.play() }
    /// The tower icon in screen coordinates, on the menu bar the cats are using. macOS shows status
    /// items on every display's menu bar at the same distance from the right edge.
    var towerRect: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard let from = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) })?.frame,
              lastScreen != .zero, from != lastScreen else { return rect }
        return Displays.mapRightAligned(rect, from: from, to: lastScreen)
    }
    /// Overlay x of the tower icon's center.
    var towerX: Double? {
        guard let rect = towerRect, let overlay else { return nil }
        return rect.midX - overlay.frame.minX
    }
    /// The screen the cats are on now (mid-move, still the old one).
    var currentScreen: NSScreen? {
        shownDisplay.flatMap(Displays.screen(id:)) ?? Displays.target(chosen: defaults.string(forKey: Pref.display) ?? "")
    }
    /// Starts or finishes a move to the display chosen in Settings.
    func updateDisplay() {
        let displays = Displays.all
        if model.displays != displays { model.displays = displays }
        guard let target = Displays.target(chosen: defaults.string(forKey: Pref.display) ?? ""), let targetID = Displays.id(of: target) else { return }
        guard let shown = shownDisplay else { shownDisplay = targetID; return }
        // The screen they were on is gone: they cannot run home there, so they wait inside and come out on the new one.
        if Displays.screen(id: shown) == nil { finishMove(to: targetID); return }
        if let moving = moveTarget {
            if moving != targetID { moveTarget = targetID; model.moveStatus = "Moving to \(target.localizedName)…" }
            if colony.cats.allSatisfy(\.home) || ProcessInfo.processInfo.systemUptime - moveStarted > 15 { finishMove(to: targetID) }
            return
        }
        guard targetID != shown else { return }
        // Nobody out to watch the walk: switch right away.
        if paused || model.catsAway || overlay?.isVisible != true || !colony.cats.contains(where: \.visible) { finishMove(to: targetID); return }
        moveTarget = targetID; moveStarted = ProcessInfo.processInfo.systemUptime
        model.moveStatus = "Moving to \(target.localizedName)…"
        AppModel.log("Moving cats to \(target.localizedName)")
        if let x = towerX { colony.callHome(at: x) }
    }
    private func finishMove(to id: String) {
        colony.sendHomeNow()
        shownDisplay = id; moveTarget = nil; model.moveStatus = nil
        colony.homeX = nil
        pendingLetOut = !model.catsAway
        epoch += 1   // drop any scan of the old screen still in flight
        AppModel.log("Cats now live on \(Displays.screen(id: id)?.localizedName ?? id)")
    }
    func toggleHome() {
        guard let x = towerX else { return }
        if model.catsAway { colony.letOut(at: x) } else { colony.callHome(at: x) }
        model.catsAway.toggle()
        defaults.set(model.catsAway, forKey: "catsHome")
    }
    var shownHomeCount = -1
    var frame = 0
    func updateTowerIcon() {
        let count = colony.homeCount
        guard count != shownHomeCount else { return }
        shownHomeCount = count
        statusItem.button?.image = TowerIcon.menuBar(cats: count)
    }
    @objc func showSettings() {
        popover.performClose(nil)
        settings.show()
    }
    /// Cats stay where they are; the next scan moves any cat that ended up over a menu or icon.
    @objc func layoutChanged() {
        epoch += 1
        scan()
    }
    @objc func willSleep() { suspended = true; habitatView?.endDrag(); overlay?.orderOut(nil) }
    @objc func didWake() { suspended = false; lastTick = ProcessInfo.processInfo.systemUptime; layoutChanged() }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        updateMouse()
        updateTowerIcon()
        // Napping, sitting cats only breathe and swish: a few frames a second is enough.
        frame += 1
        let lively = colony.ball != nil || habitatView?.blending == true || colony.cats.contains { cat in
            cat.visible && (abs(cat.velocity) > 0.1 || cat.escaping || ![.sleeping, .sitting, .loafing].contains(cat.action))
        }
        if !lively && frame % model.power.idleEvery != 0 { return }
        let dt = now - lastTick; lastTick = now
        if colony.homeX == nil, let x = towerX { colony.homeX = x }
        if moveTarget != nil && colony.cats.allSatisfy(\.home) { updateDisplay(); scan() }
        guard !paused, !suspended, overlay?.isVisible == true else { return }
        colony.step(dt)
        habitatView?.invalidateCats()
    }
    /// The overlay is click-through except right over a cat, so cats can be picked up without blocking the menu bar.
    func updateMouse() {
        guard let overlay, let view = habitatView, overlay.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let inside = overlay.frame.contains(mouse)
        let overCat = inside && colony.catIndex(at: mouse.x - overlay.frame.minX) != nil
        let overCatAllowed = overCat && defaults.bool(forKey: Pref.allowDrag)
        // With the laser on, empty menu bar space takes the press too (nothing else uses it).
        let overFree = inside && defaults.bool(forKey: Pref.laser) && colony.lanes.contains { $0.contains(mouse.x - overlay.frame.minX) }
        let catching = view.dragging != nil || view.lasering || overCatAllowed || overFree
        if overlay.ignoresMouseEvents == catching { overlay.ignoresMouseEvents = !catching }
        if overCatAllowed && view.dragging == nil { NSCursor.openHand.set() }
        if overCatAllowed != hovering { hovering = overCatAllowed; if !overCatAllowed { NSCursor.arrow.set() } }
    }
    func scan() {
        // A newly granted Accessibility permission also lets the scroll reverser start.
        if model.access != MenuBarMonitor.trusted { model.access = MenuBarMonitor.trusted; ScrollDirection.shared.apply() }
        updateDisplay()
        guard !suspended, !paused, let screen = currentScreen else { return }
        let frame = screen.frame
        let height = Displays.barHeight(of: screen)
        // A hidden/auto-hidden menu bar is deliberately not a playground.
        guard height >= NSStatusBar.system.thickness - 2 else {
            overlay?.orderOut(nil); colony.updateLanes([]); model.status = "Cats are resting while the menu bar is hidden."; return
        }
        if frame != lastScreen || height != lastHeight {
            overlay?.close()
            let panel = NSPanel(contentRect: NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            let view = HabitatView(colony: colony, frame: NSRect(x: 0, y: 0, width: frame.width, height: height))
            view.showLanes = model.debug
            panel.contentView = view
            overlay = panel; habitatView = view; lastScreen = frame; lastHeight = height
        }
        let generation = epoch
        let ownRect = towerRect
        monitor.scan(screen: frame, barHeight: height, ownItem: ownRect) { [weak self] snapshot in
            guard let self, generation == self.epoch, !self.paused, !self.suspended else { return }
            // An unreadable moment keeps the last good layout instead of making everyone vanish.
            if !snapshot.reliable && !self.colony.lanes.isEmpty { self.model.status = "Using last layout · \(snapshot.message)"; return }
            var obstacles = snapshot.obstacles
            var notch: Lane?
            if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                notch = Lane(lower: left.maxX - frame.minX, upper: right.minX - frame.minX)
                obstacles.append(notch!)
            }
            self.colony.tunnel = notch
            let lanes = snapshot.reliable ? Habitat.freeLanes(width: frame.width, obstacles: obstacles) : []
            self.colony.updateLanes(lanes)
            // Just moved here: the cats come out of this screen's tower.
            if self.pendingLetOut && !lanes.isEmpty, let x = self.towerX { self.colony.letOut(at: x); self.pendingLetOut = false }
            self.model.status = lanes.isEmpty ? (snapshot.reliable ? "No room right now. Cats will return when space opens up." : snapshot.message) : "\(lanes.count) safe area(s) · \(Int(lanes.reduce(0) { $0 + $1.width })) pt available\(self.colony.tunnelEnds() == nil ? "" : " · notch tunnel open")"
            let visible = self.colony.cats.filter(\.visible).count
            self.model.catSummary = lanes.isEmpty ? (self.model.access ? "Waiting for empty space" : "Needs Accessibility access") :
                "\(visible) cat\(visible == 1 ? "" : "s") · \(Int(lanes.reduce(0) { $0 + $1.width })) pt of room · \(self.model.power.label)"
            self.habitatView?.needsDisplay = true
            if lanes.isEmpty { self.overlay?.orderOut(nil) } else { self.overlay?.orderFrontRegardless() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { animationTimer?.invalidate(); layoutTimer?.invalidate(); overlay?.close() }
}
