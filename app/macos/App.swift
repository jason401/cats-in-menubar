import Cocoa
import SwiftUI

final class AppModel: ObservableObject {
    @Published var debug = false { didSet { changed?() } }
    @Published var status = "Checking menu layout…" { didSet { if status != oldValue { AppModel.log(status) } } }
    @Published var catSummary = "Looking for empty space…"
    @Published var catsAway = false     // called into the cat tower
    @Published var shuffling = false    // all going in to come back out as new cats
    @Published var displays: [DisplayInfo] = []
    @Published var moveStatus: String?  // "Moving to …" while the cats walk home to change screens
    @Published var shownDisplay = ""    // the display the cats are on now
    @Published var power = PowerLevel.full
    @Published var lineup: [CatAppearance] = []
    @Published var keepLineup = false
    @Published var wheelCat: CatAppearance?   // the cat in the CPU wheel, nil while the wheel is off
    var configureCat: ((Int, CatAppearance) -> Void)?
    var configureWheelCat: ((CatAppearance) -> Void)?
    var shuffleCats: (() -> Void)?
    var rememberCats: ((Bool) -> Void)?
    var keepCurrent: (() -> Void)?
    var home: (() -> Void)?
    var openHiddenApp: ((String) -> Void)?   // a hidden menu bar app's icon clicked in the panel
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
    lazy var dashboard = DashboardPanel(model: model, system: system, openSettings: { [weak self] in self?.showSettings() }, play: { [weak self] in self?.play() })
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
    var pendingLetOut = false
    var barHidden = false   // the cats went inside when the menu bar hid; they come back out when it returns
    var lastHeight: CGFloat = 0
    var suspended = false
    var hovering = false
    var monitorInterval = 0.0
    var governor = PowerGovernor()
    var appliedLineup: Data?
    var lineupLoaded = false    // with turns on, the saved lineup only sets who comes out at launch
    var wheelLoaded = false     // the saved wheel cat comes back at launch only with Keep my cats
    // The CPU wheel: a template tower + wheel image, and the colored cat as its own layer on top.
    var wheelOn = false
    /// The wheel runs on the AI Face board instead: the menu bar shows only the tower, turns happen offstage.
    var wheelAway = false
    var wheelShown: Bool { wheelOn && !wheelAway }
    var wheelPace = WheelPace()
    var wheelCat: WheelOverlayView?
    var wheelBattery = WheelBattery.plain
    var wheelTimer: Timer?
    var wheelAngle = 0.0, wheelStep = 0.0, wheelLast = 0.0
    var wheelGait = WheelPace.Gait.rest
    /// Wheel seconds left until the next cat's turn; counts down only while the wheel runs unpaused.
    var wheelNextShift: Double?
    var wheelDropShown = false   // a held cat is over the wheel and letting go would trade places
    var towerDropShown = false   // a held cat is over the tower and letting go would trade it for another cat
    var wheelShiftRange = -1
    let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: Pref.defaults)
        WheelShift.migrate(defaults, domain: Bundle.main.bundleIdentifier ?? "")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = TowerIcon.menuBar()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        setUpDashboard()
        WiFiNamePermission.shared.changed = { [weak self] in self?.system.sample() }
        AppModel.log("Launched pid \(ProcessInfo.processInfo.processIdentifier), Accessibility: \(MenuBarMonitor.trusted)")
        model.changed = { [weak self] in self?.applyOptions() }
        model.play = { [weak self] in self?.play() }
        model.home = { [weak self] in self?.toggleHome() }
        model.openHiddenApp = { [weak self] bundle in
            // The panel goes first: the app's own menu opens from the menu bar.
            self?.dashboard.hide()
            MenuBarTidy.shared.open(bundle)
        }
        MenuBarTidy.shared.layoutChanged = { [weak self] in self?.layoutChanged() }
        MenuBarTidy.shared.start()
        // Each launch the cats hop out of the tower one by one. A saved lineup overrides only appearance, never location.
        defaults.set(false, forKey: "catsHome")
        model.keepLineup = defaults.bool(forKey: Pref.fixedLineup)
        model.configureCat = { [weak self] i, appearance in self?.configureCat(i, appearance) }
        model.configureWheelCat = { [weak self] appearance in self?.configureWheelCat(appearance) }
        model.shuffleCats = { [weak self] in self?.shuffleCats() }
        model.rememberCats = { [weak self] enabled in self?.rememberCats(enabled) }
        model.keepCurrent = { [weak self] in self?.keepCurrent() }
        colony.swapped = { [weak self] in self?.syncLineup() }
        colony.shuffled = { [weak self] in self?.shuffleDone() }
        colony.wheelChanged = { [weak self] in self?.wheelCatChanged() }
        colony.wheelTurnCompleted = { [weak self] in self?.wheelNextShift = nil }
        system.updated = { [weak self] stats in self?.systemUpdated(stats) }
        FaceStream.shared.source = { [weak self] in self?.faceInput() }
        FaceStream.shared.changed = { [weak self] in self?.faceStreamChanged() }
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: UserDefaults.didChangeNotification, object: nil)
        applyOptions()
        colony.startInTower()
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
        FinderShortcuts.shared.apply()
        QuitOnClose.shared.apply()
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
        let rotating = defaults.bool(forKey: Pref.rotate)
        if defaults.bool(forKey: Pref.fixedLineup), !(rotating && lineupLoaded), let data = defaults.data(forKey: Pref.lineup), data != appliedLineup,
           let appearances = try? JSONDecoder().decode([CatAppearance].self, from: data) {
            habitatView?.endDrag()
            colony.applyAppearances(appearances)
            appliedLineup = data
        }
        lineupLoaded = true
        colony.rotation = rotating ? Self.rotationPaces[max(0, min(2, defaults.integer(forKey: Pref.rotatePace)))] : nil
        syncLineup()
        colony.activity = defaults.integer(forKey: Pref.activity)
        let toyColor = defaults.integer(forKey: Pref.toyColor)
        colony.toyColor = Toy.colors.indices.contains(toyColor) ? toyColor : nil
        if defaults.bool(forKey: Pref.cpuWheel) != wheelOn { setWheel(!wheelOn) }
        wheelLoaded = true
        updateFaceStream()
        habitatView?.showLanes = model.debug
        system.wantsApps = defaults.integer(forKey: Pref.topApps) > 0 && (defaults.bool(forKey: Pref.showCPU) || defaults.bool(forKey: Pref.showMemory))
        system.wantsWiFi = defaults.bool(forKey: Pref.showNetwork)
        system.wantsGPU = defaults.bool(forKey: Pref.showGPU)
        system.wantsPower = defaults.bool(forKey: Pref.showBattery)
        // The panel opening on hover would cover the tooltip.
        statusItem.button?.toolTip = defaults.bool(forKey: Pref.panelOnHover) ? nil : "Cats in Menubar"
        systemUpdated(system.stats)
        let interval = max(defaults.double(forKey: Pref.interval), model.power.sampleFloor)
        if interval != monitorInterval { monitorInterval = interval; system.start(interval: interval) }
        if paused { overlay?.orderOut(nil) } else { scan() }
        ScrollDirection.shared.apply()
        FinderShortcuts.shared.apply()
        QuitOnClose.shared.apply()
    }
    /// Minutes out before another cat takes a turn: often, normal, now and then.
    static let rotationPaces: [ClosedRange<Double>] = [300...600, 900...1800, 2700...5400]
    func syncLineup() {
        let appearances = colony.cats.map(\.appearance)
        if model.lineup != appearances { model.lineup = appearances }
        if model.wheelCat != colony.wheel { model.wheelCat = colony.wheel }
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
        // The wheel cat is kept under its own key (also saved at every turn).
        if let wheel = colony.wheel, let data = try? JSONEncoder().encode(wheel) { defaults.set(data, forKey: Pref.wheelCat) }
    }
    func configureCat(_ index: Int, _ appearance: CatAppearance) {
        guard colony.cats.indices.contains(index) else { return }
        habitatView?.endDrag()
        // Picking a cat by hand ends taking turns.
        defaults.set(false, forKey: Pref.rotate); colony.rotation = nil
        // A coat another cat wears (the wheel cat too) is traded between the two.
        colony.dress(index, appearance)
        saveLineup()
        defaults.set(true, forKey: Pref.fixedLineup)
        syncLineup()
        habitatView?.needsDisplay = true
    }
    /// The wheel cat picked by hand; a coat a cat outside wears is traded. Turns in the wheel carry on.
    func configureWheelCat(_ appearance: CatAppearance) {
        guard colony.wheel != nil else { return }
        habitatView?.endDrag()
        colony.dress(nil, appearance)
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
    /// Stops taking turns and keeps the cats out now (and saves them for the next launch).
    func keepCurrent() {
        defaults.set(false, forKey: Pref.rotate); colony.rotation = nil
        rememberCats(true)
    }
    /// Everyone goes into the tower and comes back out, one by one, as new cats.
    func shuffleCats() {
        guard !model.shuffling else { return }
        habitatView?.endDrag()
        model.catsAway = false
        defaults.set(false, forKey: "catsHome")
        defaults.set(false, forKey: Pref.fixedLineup)
        // Paused or asleep nobody can walk: new cats at once.
        if paused || suspended || (colony.homeX ?? towerX) == nil {
            colony.shuffle()
        } else {
            model.shuffling = true
            colony.beginShuffle(at: colony.homeX ?? towerX!)
        }
        syncLineup()
        habitatView?.needsDisplay = true
    }
    private func shuffleDone() {
        model.shuffling = false
        // "Keep my cats" turned on mid-shuffle keeps the new cats, not the ones that went in.
        if defaults.bool(forKey: Pref.fixedLineup) { saveLineup() }
        syncLineup()
        // Changing screens, or the menu bar is hidden: they come out wherever they show up next.
        guard moveTarget == nil, !barHidden, !pendingLetOut, let x = colony.homeX ?? towerX else { return }
        colony.letOut(at: x, after: 1.5)
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
        // The panel's contents follow the stats on the next pass; then it is measured again.
        if dashboard.isShown { DispatchQueue.main.async { self.dashboard.resize() } }
        let gait = wheelPace.gait
        wheelPace.update(cpu: stats.cpu)
        // Waking from a nap should not wait for the resting cat's next one-second look.
        if wheelOn && gait == .rest && wheelPace.gait != .rest { stepWheel() }
        // A new battery percent shows on the next wheel frame; a resting wheel draws it now.
        let battery = WheelBattery.gauge(hasBattery: stats.hasBattery, level: stats.batteryLevel,
                                         enabled: defaults.bool(forKey: Pref.wheelBattery), mono: defaults.bool(forKey: Pref.wheelBatteryMono))
        if battery != wheelBattery {
            wheelBattery = battery
            if wheelOn && (paused || wheelPace.gait == .rest) { stepWheel() }
        }
    }
    /// Shows or hides the wheel. The status item gets wider, so free space is measured again.
    func setWheel(_ on: Bool) {
        wheelOn = on
        wheelTimer?.invalidate(); wheelTimer = nil
        guard let button = statusItem.button else { return }
        button.imagePosition = on ? .imageOnly : .imageLeft
        if on {
            // At launch without Keep my cats the wheel cat is new too; switched on again later, the last one comes back.
            let saved = defaults.data(forKey: Pref.wheelCat).flatMap { try? JSONDecoder().decode(CatAppearance.self, from: $0) }
            colony.enableWheel(saved, fresh: saved != nil && !wheelLoaded && !defaults.bool(forKey: Pref.fixedLineup))
            let view = WheelOverlayView(frame: NSRect(x: 0, y: 0, width: 20, height: TowerIcon.wheelSize.height))
            view.isHidden = wheelAway
            button.addSubview(view); wheelCat = view
            wheelLast = ProcessInfo.processInfo.systemUptime; wheelNextShift = nil
            stepWheel()
        } else {
            colony.wheel = nil; colony.wheelX = nil   // a cat on its way to the wheel carries on as itself
            wheelCat?.removeFromSuperview(); wheelCat = nil; wheelAway = false
            shownHomeCount = -1; updateTowerIcon()
        }
        AppModel.log("CPU wheel: \(on ? "on" : "off")")
        updateFaceStream()
        syncLineup()
        layoutChanged()
    }
    /// One wheel frame, then the next is scheduled at the current pace (RunCat style), independent of
    /// the cats' animation timer, which slows down exactly when the CPU is busy.
    func stepWheel() {
        wheelTimer?.invalidate(); wheelTimer = nil
        guard wheelOn, !suspended, let button = statusItem.button, let cat = wheelCat else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Frames are at most 1 s apart, so a longer gap is sleep and does not count toward a turn.
        let elapsed = min(2, max(0, now - wheelLast)), dt = min(0.5, elapsed); wheelLast = now
        // Paused cats rest in the wheel too, and so does a wheel cat waiting for the cat taking over.
        // A cat held over the wheel, ready to take over when let go, gets the same pause as a signal.
        let waiting = paused || colony.wheelWaiting || wheelDropShown
        let gait = waiting ? .rest : wheelPace.gait
        let motion = waiting ? WheelPace.Motion(frameRate: 0, degreesPerSecond: 0) : wheelPace.motion(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if gait != wheelGait { wheelGait = gait; wheelStep = 0 } else { wheelStep += dt * motion.frameRate }
        // Cats take turns in the wheel after a random wait, drawn again at every swap and whenever the
        // range changes. Off keeps the cat in it. Pause stops the countdown.
        let range = defaults.integer(forKey: Pref.wheelSwapRange)
        if range != wheelShiftRange { wheelShiftRange = range; wheelNextShift = nil }
        if WheelShift.interval(range: range, roll: 0) == nil { wheelNextShift = nil }
        else if let left = wheelNextShift {
            if !paused { wheelNextShift = left - elapsed }
            if let left = wheelNextShift, left <= 0 {
                // A busy moment (a swap, a toy, everyone on the move) tries again shortly. The wait is reset
                // first: a new wheel cat redraws through stepWheel, which must not start another turn.
                wheelNextShift = 10
                wheelNextShift = takeWheelTurn() ? nextWheelShift(range) : 10
            }
        } else { wheelNextShift = nextWheelShift(range) }
        // Turning clockwise: the cat runs right, so the tread under its paws moves left.
        wheelAngle = (wheelAngle - dt * motion.degreesPerSecond).truncatingRemainder(dividingBy: 360)
        shownHomeCount = colony.homeCount
        if wheelAway {
            // On the board: only the tower here, and a slow tick is enough to count down to the next turn.
            button.image = TowerIcon.menuBar(cats: shownHomeCount, open: towerDropShown)
            let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in self?.stepWheel() }
            RunLoop.main.add(timer, forMode: .common); wheelTimer = timer
            return
        }
        button.image = TowerIcon.menuBar(cats: shownHomeCount, wheel: wheelAngle, battery: wheelBattery, open: towerDropShown)
        // The image is centered in the button; the cat layer covers its left 20 pt.
        let size = TowerIcon.wheelSize
        cat.frame = NSRect(x: (button.bounds.width - size.width) / 2, y: (button.bounds.height - size.height) / 2, width: 20, height: size.height)
        cat.coat = colony.wheel?.coat ?? 0
        cat.cell = WheelOverlayView.cell(gait, step: Int(wheelStep), coat: cat.coat)
        cat.battery = wheelBattery
        let timer = Timer(timeInterval: motion.frameRate > 0 ? 1 / motion.frameRate : 1, repeats: false) { [weak self] _ in self?.stepWheel() }
        RunLoop.main.add(timer, forMode: .common); wheelTimer = timer
    }
    /// Seconds until the next turn; a `wheelSwapSeconds` default (unregistered, for checking by hand) overrides the range.
    func nextWheelShift(_ range: Int) -> Double? {
        let debug = defaults.double(forKey: Pref.wheelSwapSeconds)
        return debug > 0 ? debug : WheelShift.interval(range: range, roll: Double.random(in: 0...1))
    }
    /// The wheel cat's turn is up. A cat out playing walks over and they trade places in front of the wheel;
    /// out of sight (everyone in, paused, quiet, a hidden menu bar, changing screens) they trade in the tower.
    /// Keep my cats keeps the lineup: a cat from outside it takes the wheel. False: try again in a moment.
    func takeWheelTurn() -> Bool {
        let keep = defaults.bool(forKey: Pref.fixedLineup)
        let seen = wheelShown && !paused && !suspended && !barHidden && !model.catsAway && !model.shuffling && moveTarget == nil && overlay?.isVisible == true
        if !keep && seen {
            switch colony.beginBaton() {
            case .started:
                if let i = colony.cats.firstIndex(where: \.wheelBound) { AppModel.log("CPU wheel: \(CatAppearance.names[colony.cats[i].coat]) walks over to take a turn") }
                return true
            case .busy: return false
            case .nobodyOut: break
            }
        }
        return colony.swapWheelOffstage(keepLineup: keep)
    }
    /// Another cat is in the wheel: saved for the next launch and shown from this frame on.
    func wheelCatChanged() {
        guard let wheel = colony.wheel else { return }
        if let data = try? JSONEncoder().encode(wheel) { defaults.set(data, forKey: Pref.wheelCat) }
        AppModel.log("CPU wheel: \(CatAppearance.names[wheel.coat]) takes a turn")
        syncLineup()
        wheelStep = 0
        if wheelOn && wheelCat != nil { stepWheel() }
    }
    @objc func togglePanel() { dashboard.click() }
    /// The panel under the icon (DashboardPanel): it opens when the pointer rests on the icon, or on a click.
    func setUpDashboard() {
        guard let button = statusItem.button else { return }
        dashboard.icon = { [weak self] in
            guard let button = self?.statusItem.button, let window = button.window else { return nil }
            return window.convertToScreen(button.convert(button.bounds, to: nil))
        }
        dashboard.blockers = { [weak self] in
            guard let self else { return .init(enabled: false) }
            return .init(enabled: self.defaults.bool(forKey: Pref.panelOnHover),
                         catBusy: self.hovering || self.habitatView?.dragging != nil || self.habitatView?.lasering == true || self.towerDropShown || self.wheelDropShown,
                         buttonDown: NSEvent.pressedMouseButtons != 0,
                         command: NSEvent.modifierFlags.contains(.command),
                         towerMoving: StatusItemDrag.moving)
        }
        dashboard.hoverOn = { [weak self] in self?.defaults.bool(forKey: Pref.panelOnHover) ?? false }
        // Fresh app lists and Wi-Fi details while the panel is open.
        dashboard.willShow = { [weak self] in self?.system.detailed = true; self?.system.sample() }
        dashboard.didHide = { [weak self] in self?.system.detailed = false }
        // The Wi-Fi name needs Location Services, asked once, the first time the panel is clicked open on Wi-Fi;
        // a prompt that pops up from just resting on the icon would be a surprise.
        dashboard.clicked = { [weak self] in
            guard let self else { return }
            if self.system.stats.wifi != nil && self.defaults.bool(forKey: Pref.showNetwork) { WiFiNamePermission.shared.askIfNeeded() }
        }
        button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: dashboard, userInfo: nil))
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
    /// Overlay x of the tower icon's center (with the wheel on, the tower is the image's right 18 pt).
    var towerX: Double? {
        guard let rect = towerRect, let overlay else { return nil }
        return TowerIcon.towerCenterX(in: rect, wheel: wheelShown) - overlay.frame.minX
    }
    /// Overlay x of the wheel's center, while the wheel shows in the menu bar.
    var wheelX: Double? {
        guard wheelShown, let rect = towerRect, let overlay else { return nil }
        return TowerIcon.wheelCenterX(in: rect) - overlay.frame.minX
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
        if let moving = moveTarget {
            if moving != targetID { moveTarget = targetID; model.moveStatus = "Moving to \(target.localizedName)…" }
            // No time limit, and out of sight they still walk home (hidden menu bar, unplugged screen).
            // Only pausing, or nobody left outside, ends it at once.
            if paused || !colony.cats.contains(where: { !$0.home && $0.visible }) { finishMove(to: targetID) }
            return
        }
        guard targetID != shown else { return }
        // Nobody out to walk home: switch right away.
        if paused || model.catsAway || !colony.cats.contains(where: { !$0.home && $0.visible }) { finishMove(to: targetID); return }
        moveTarget = targetID
        model.moveStatus = "Moving to \(target.localizedName)…"
        AppModel.log("Moving cats to \(target.localizedName)")
        habitatView?.endDrag()   // a held cat is put down and runs home with the others
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
        // Called home mid-shuffle: everyone stays in as they are.
        if model.shuffling { colony.shuffling = false; model.shuffling = false }
        if model.catsAway { colony.letOut(at: x) } else { habitatView?.endDrag(); colony.callHome(at: x) }
        model.catsAway.toggle()
        defaults.set(model.catsAway, forKey: "catsHome")
    }
    var shownHomeCount = -1
    var frame = 0
    func updateTowerIcon() {
        let count = colony.homeCount
        guard count != shownHomeCount else { return }
        // The wheel redraws the whole icon each frame; show the change now rather than on its next frame.
        if wheelOn { stepWheel(); return }
        shownHomeCount = count
        statusItem.button?.image = TowerIcon.menuBar(cats: count, open: towerDropShown)
    }
    @objc func showSettings() {
        dashboard.hide()
        settings.show()
    }
    /// Cats stay where they are; the next scan moves any cat that ended up over a menu or icon.
    @objc func layoutChanged() {
        epoch += 1
        scan()
    }
    @objc func willSleep() { suspended = true; dashboard.hide(); habitatView?.endDrag(); overlay?.orderOut(nil); wheelTimer?.invalidate(); wheelTimer = nil; updateFaceStream() }
    @objc func didWake() {
        suspended = false; lastTick = ProcessInfo.processInfo.systemUptime; layoutChanged()
        wheelLast = lastTick; stepWheel(); updateFaceStream()
    }
    /// The wheel on the AI Face board, while the setting and the wheel are on and the Mac is awake.
    func updateFaceStream() {
        FaceStream.shared.update(enabled: defaults.bool(forKey: Pref.faceStream), available: wheelOn && !suspended)
    }
    /// While the board shows the wheel, the menu bar does not; when the stream ends it comes back.
    /// The status item gets narrower or wider, so free space is measured again.
    func faceStreamChanged() {
        let away = wheelOn && FaceStream.shared.state == .streaming
        guard away != wheelAway else { return }
        wheelAway = away
        if away {
            colony.cancelBaton(); colony.wheelX = nil   // a cat on its way to the wheel carries on as itself
            wheelDropShown = false
        }
        wheelCat?.isHidden = away
        shownHomeCount = -1
        AppModel.log("CPU wheel: \(away ? "on the AI Face board" : "back in the menu bar")")
        stepWheel()
        layoutChanged()
    }
    /// What the board's wheel shows: the same cat, gait and battery as the menu bar, at the board's pace.
    func faceInput() -> FaceStream.Input? {
        guard wheelOn else { return nil }
        let waiting = paused || colony.wheelWaiting || wheelDropShown
        return FaceStream.Input(gait: waiting ? .rest : wheelPace.gait,
                                motion: waiting ? WheelPace.Motion(frameRate: 0, degreesPerSecond: 0) : wheelPace.motion(maxFrameRate: FaceStream.maxFPS),
                                coat: colony.wheel?.coat ?? 0, battery: wheelBattery)
    }
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
        // The tower slides whenever menu bar items to its right change width or come and go; auto rotation
        // walks cats in and out without a fresh callHome/letOut, so follow the icon every frame.
        if let x = towerX, colony.homeX == nil || (0...(overlay?.frame.width ?? 0)).contains(x) { colony.homeX = x }
        if !wheelShown { colony.wheelX = nil } else if let x = wheelX, colony.wheelX == nil || (0...(overlay?.frame.width ?? 0)).contains(x) { colony.wheelX = x }
        if let rect = towerRect, let overlay { colony.ownItem = Lane(lower: rect.minX - overlay.frame.minX, upper: rect.maxX - overlay.frame.minX) }
        let dropReady = wheelShown && colony.wheelDropReady && habitatView?.wheelDropAllowed?() == true
        if dropReady != wheelDropShown { wheelDropShown = dropReady; stepWheel() }
        // Over the tower, ready to go in: the tower's door opens wide.
        let towerReady = colony.towerDropReady && habitatView?.towerDropAllowed?() == true
        if towerReady != towerDropShown { towerDropShown = towerReady; shownHomeCount = -1; updateTowerIcon() }
        if moveTarget != nil && colony.cats.allSatisfy(\.home) { updateDisplay(); scan() }
        // Out of sight (hidden menu bar, unplugged screen) the cats carry on as usual; only pausing stops them.
        guard !paused, !suspended else { return }
        colony.onStage = overlay?.isVisible == true
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
        // A newly granted Accessibility permission also lets the scroll reverser and Finder shortcuts start.
        if model.access != MenuBarMonitor.trusted { model.access = MenuBarMonitor.trusted; ScrollDirection.shared.apply(); FinderShortcuts.shared.apply(); QuitOnClose.shared.apply() }
        updateDisplay()
        // Their screen was unplugged mid-walk: they finish the walk home on its last layout, unseen.
        if moveTarget != nil, let shown = shownDisplay, Displays.screen(id: shown) == nil { overlay?.orderOut(nil); return }
        guard !suspended, !paused, let screen = currentScreen else { return }
        let frame = screen.frame
        let height = Displays.barHeight(of: screen)
        // A hidden/auto-hidden menu bar is deliberately not a playground.
        // While it is hidden (full-screen apps, auto-hide) the cats run home out of sight on the last layout,
        // and come back out when it returns.
        guard height >= NSStatusBar.system.thickness - 2 else {
            if !barHidden {
                barHidden = true; habitatView?.endDrag()
                if !model.catsAway, let x = colony.homeX ?? towerX { colony.callHome(at: x) }
            }
            overlay?.orderOut(nil); model.status = "Cats are resting in the tower while the menu bar is hidden."; return
        }
        if barHidden { barHidden = false; pendingLetOut = !model.catsAway }
        if frame != lastScreen || height != lastHeight {
            overlay?.close()
            let panel = NSPanel(contentRect: NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            let view = HabitatView(colony: colony, frame: NSRect(x: 0, y: 0, width: frame.width, height: height))
            view.interactionEnded = { Updater.shared.resumeWhenIdle() }
            view.wheelDropAllowed = { [weak self] in
                guard let self else { return false }
                return self.wheelShown && !self.defaults.bool(forKey: Pref.fixedLineup)
                    && !self.paused && !self.suspended && !self.barHidden && !self.model.catsAway
                    && !self.model.shuffling && self.moveTarget == nil && self.overlay?.isVisible == true
            }
            // Keep my cats only fixes the lineup at launch, so a new cat by hand is still fine.
            view.towerDropAllowed = { [weak self] in
                guard let self else { return false }
                return !self.paused && !self.suspended && !self.barHidden && !self.model.catsAway
                    && !self.model.shuffling && self.moveTarget == nil && self.overlay?.isVisible == true
            }
            view.showLanes = model.debug
            panel.contentView = view
            overlay = panel; habitatView = view; lastScreen = frame; lastHeight = height
        }
        let generation = epoch
        let ownRect = towerRect
        let tidy = MenuBarTidy.shared
        monitor.scan(screen: frame, barHeight: height, ownItem: ownRect, skip: tidy.hiddenNow) { [weak self] snapshot in
            guard let self else { return }
            tidy.update(extras: snapshot.extras)
            if !self.dashboard.isShown, self.habitatView?.dragging == nil, let button = self.statusItem.button, let window = button.window {
                tidy.keepLeftmost(own: window.convertToScreen(button.convert(button.bounds, to: nil)), extras: snapshot.extras)
            }
            guard generation == self.epoch, !self.paused, !self.suspended else { return }
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
    func applicationWillTerminate(_ notification: Notification) { MenuBarTidy.shared.stop(); animationTimer?.invalidate(); layoutTimer?.invalidate(); wheelTimer?.invalidate(); overlay?.close(); FaceStream.shared.stopNow() }
}
