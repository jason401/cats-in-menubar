import Cocoa
import SwiftUI

final class AppModel: ObservableObject {
    @Published var paused: Bool { didSet { UserDefaults.standard.set(paused, forKey: "paused"); changed?() } }
    @Published var quiet: Bool { didSet { UserDefaults.standard.set(quiet, forKey: "quiet"); changed?() } }
    @Published var count: Int { didSet { UserDefaults.standard.set(count, forKey: "catCount"); changed?() } }
    @Published var debug = false { didSet { changed?() } }
    @Published var status = "Checking menu layout…"
    @Published var access = MenuBarMonitor.trusted
    var changed: (() -> Void)?
    var play: (() -> Void)?
    init() {
        let defaults = UserDefaults.standard
        paused = defaults.bool(forKey: "paused")
        quiet = defaults.bool(forKey: "quiet")
        count = defaults.object(forKey: "catCount") == nil ? 3 : max(1, min(3, defaults.integer(forKey: "catCount")))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "cat.fill").font(.system(size: 30)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cats in Menubar").font(.title2.bold())
                    Text("A little life in the empty space.").foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack { Text("Cats"); Spacer(); Picker("Cats", selection: $model.count) { Text("2").tag(2); Text("3").tag(3) }.labelsHidden().pickerStyle(.segmented).frame(width: 120) }
            Toggle("Quiet time", isOn: $model.quiet)
            Text("Let everyone sleep. Turn off to resume their usual routine.").font(.caption).foregroundStyle(.secondary)
            Toggle("Pause and hide cats", isOn: $model.paused)
            HStack {
                Button("Bring out a ball") { model.play?() }.disabled(model.quiet || model.paused || !model.access)
                Spacer()
                Toggle("Show safe space", isOn: $model.debug).toggleStyle(.checkbox)
            }
            Divider()
            HStack {
                Image(systemName: model.access ? "checkmark.shield.fill" : "lock.fill").foregroundStyle(model.access ? .green : .orange)
                Text(model.access ? "Accessibility access granted" : "Accessibility access required").font(.headline)
            }
            Text("The app reads menu item positions to keep cats away from menus and icons. It does not capture your screen or read menu item text.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.access {
                Button("Allow Accessibility Access…") {
                    MenuBarMonitor.requestAccess()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                }
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Preview · Primary display only · Hidden when the menu bar is hidden").font(.caption2).foregroundStyle(.tertiary)
            HStack { Spacer(); Button("Quit Cats in Menubar") { NSApp.terminate(nil) } }
        }.padding(24).frame(width: 410)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    let colony = Colony()
    let monitor = MenuBarMonitor()
    var statusItem: NSStatusItem!
    var overlay: NSPanel?
    var habitatView: HabitatView?
    var settings: NSWindow?
    var animationTimer: Timer?
    var layoutTimer: Timer?
    var lastTick = ProcessInfo.processInfo.systemUptime
    var epoch = 0
    var lastScreen: NSRect = .zero
    var lastHeight: CGFloat = 0
    var suspended = false
    var lastScan = 0.0
    var menuOpen = false
    var scanStarted = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Cats in Menubar")
        statusItem.button?.toolTip = "Cats in Menubar"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Cats in Menubar…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Pause / Resume", action: #selector(togglePause), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Bring out a ball", action: #selector(play), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cats in Menubar", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        model.changed = { [weak self] in self?.applyOptions() }
        model.play = { [weak self] in self?.play() }
        applyOptions()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(layoutChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(layoutChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(layoutChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let animate = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(animate, forMode: .common); animationTimer = animate
        let layout = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(layout, forMode: .common); layoutTimer = layout
        scan()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || !MenuBarMonitor.trusted {
            showSettings(); UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }
    func applyOptions() {
        colony.setCount(model.count); colony.quiet = model.quiet
        habitatView?.showLanes = model.debug
        if model.paused { overlay?.orderOut(nil) }
        else { scan() }
    }
    @objc func togglePause() { model.paused.toggle() }
    @objc func play() { guard !model.paused else { return }; colony.play() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 458, height: 490), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Cats in Menubar"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }
    @objc func layoutChanged() {
        epoch += 1
        colony.updateLanes([])
        overlay?.orderOut(nil)
        scan()
    }
    @objc func willSleep() { suspended = true; layoutChanged() }
    @objc func didWake() { suspended = false; lastTick = ProcessInfo.processInfo.systemUptime; layoutChanged() }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; overlay?.orderOut(nil) }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; layoutChanged() }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTick; lastTick = now
        // Do not keep using a stale obstacle map when the AX server stalls.
        if now - lastScan > 1.5 { overlay?.orderOut(nil); return }
        guard !model.paused, !suspended, !menuOpen, overlay?.isVisible == true else { return }
        colony.step(dt)
        habitatView?.needsDisplay = true
    }
    func scan() {
        model.access = MenuBarMonitor.trusted
        guard !suspended, !model.paused, !menuOpen, let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        // A hidden/auto-hidden menu bar is deliberately not a playground.
        guard frame.maxY - screen.visibleFrame.maxY >= height - 2 else {
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
        let ownRect = statusItem.button.flatMap { button in button.window?.convertToScreen(button.convert(button.bounds, to: nil)) }
        monitor.scan(screen: frame, barHeight: height, ownItem: ownRect) { [weak self] snapshot in
            guard let self, generation == self.epoch, !self.model.paused, !self.suspended, !self.menuOpen else { return }
            self.lastScan = ProcessInfo.processInfo.systemUptime
            var obstacles = snapshot.obstacles
            if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                obstacles.append(Lane(lower: left.maxX - frame.minX, upper: right.minX - frame.minX))
            }
            let lanes = snapshot.reliable ? Habitat.freeLanes(width: frame.width, obstacles: obstacles) : []
            self.colony.updateLanes(lanes)
            self.model.status = lanes.isEmpty ? (snapshot.reliable ? "No room right now. Cats will return when space opens up." : snapshot.message) : "\(lanes.count) safe area(s) · \(Int(lanes.reduce(0) { $0 + $1.width })) pt available"
            self.habitatView?.needsDisplay = true
            if lanes.isEmpty { self.overlay?.orderOut(nil) } else { self.overlay?.orderFrontRegardless() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { animationTimer?.invalidate(); layoutTimer?.invalidate(); overlay?.close() }
}
