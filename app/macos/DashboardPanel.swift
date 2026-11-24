import Cocoa
import SwiftUI

// The panel under the menu bar icon: the summary (DashboardView) and, beside it, the section of the row
// the pointer rests on (DashboardDetailView).
// - Resting on the icon opens it (Settings > General > Open on hover, on by default). It closes once the
//   pointer has been away from the icon and both panels for a moment, or on a click elsewhere. A click
//   inside does not keep it: most looks are a glance at a number.
// - A click on the icon opens it at once and it closes the same way, so it never depends on whether the click
//   landed before or after the rest delay. A click on the icon while it is open does nothing.
// - With Open on hover off, a click opens it until a click elsewhere, another click on the icon, or Esc.
// Both are non-activating panels, like the cats' overlay, so showing them never takes the keyboard from the
// app in front. A tracking area on the icon starts a 30 Hz check of the pointer, which runs only while the
// pointer is on the icon or a panel is open.

enum PanelHoverRules {
    /// Resting this long on the icon opens the panel; passing over it on the way across the menu bar does not.
    static let openDelay: TimeInterval = 0.15
    /// Away from the icon and the panels this long closes a panel opened by resting.
    static let closeDelay: TimeInterval = 0.35
    /// On another row this long changes the side panel, so crossing rows on the way to it does not.
    static let switchDelay: TimeInterval = 0.06
    /// How far around the icon and the panels still counts as being on them (as AI Face's folder panel does).
    static let iconSlack: CGFloat = 2, panelSlack: CGFloat = 12
    /// The summary hangs this far below the icon, the side panel this far from the summary, both this far from screen edges.
    static let drop: CGFloat = 6, gap: CGFloat = 6, margin: CGFloat = 8

    /// What stops a rest on the icon from opening the panel.
    struct Blockers: Equatable {
        var enabled = true
        var catBusy = false      // a cat under the pointer or held, one about to be dropped on the tower or wheel, the laser
        var buttonDown = false
        var command = false      // ⌘-dragging the icon somewhere else
        var towerMoving = false  // the menu bar tidy is ⌘-dragging the tower itself
    }
    static func mayOpen(_ b: Blockers) -> Bool { b.enabled && !b.catBusy && !b.buttonDown && !b.command && !b.towerMoving }

    /// Whether the pointer is still on the icon or a panel; the slack also bridges the gaps between them.
    static func near(_ mouse: NSPoint, icon: NSRect, panels: [NSRect]) -> Bool {
        icon.insetBy(dx: -iconSlack, dy: -iconSlack).contains(mouse) || panels.contains { $0.insetBy(dx: -panelSlack, dy: -panelSlack).contains(mouse) }
    }

    static func due(_ since: TimeInterval?, _ now: TimeInterval, _ delay: TimeInterval) -> Bool {
        guard let since else { return false }
        return now - since >= delay
    }

    /// The summary: centered under the icon, kept on screen.
    static func summaryFrame(size: NSSize, icon: NSRect, screen: NSRect) -> NSRect {
        let x = max(screen.minX + margin, min(icon.midX - size.width / 2, screen.maxX - margin - size.width))
        return NSRect(x: x, y: icon.minY - drop - size.height, width: size.width, height: size.height)
    }

    /// The side panel: level with its row, on the left where status icons usually leave room, else on the right.
    static func detailFrame(size: NSSize, summary: NSRect, row: NSRect, screen: NSRect) -> NSRect {
        let left = summary.minX - gap - size.width, right = summary.maxX + gap
        let x = left >= screen.minX + margin || right + size.width > screen.maxX - margin ? max(screen.minX + margin, left) : right
        let top = min(row.maxY, summary.maxY, screen.maxY)
        return NSRect(x: x, y: max(screen.minY + margin, top - size.height), width: size.width, height: size.height)
    }
}

final class DashboardWindow: NSPanel {
    /// Only a panel opened by a click takes the keyboard (for Esc); one opened by resting never does.
    var keyable = false
    override var canBecomeKey: Bool { keyable }
}

/// Buttons take the first click even while another app is in front.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DashboardPanel: NSResponder {
    enum Mode { case hover, click }
    private(set) var mode: Mode?
    var isShown: Bool { mode != nil }

    /// The icon on screen; nil while it has none.
    var icon: () -> NSRect? = { nil }
    var blockers: () -> PanelHoverRules.Blockers = { .init() }
    /// Settings > General > Open on hover.
    var hoverOn: () -> Bool = { true }
    /// About to show: time for fresh stats.
    var willShow: () -> Void = {}
    /// Opened or kept by a click.
    var clicked: () -> Void = {}
    var didHide: () -> Void = {}
    /// The pointer and the clock; the self-test swaps in its own.
    var pointer: () -> NSPoint = { NSEvent.mouseLocation }
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    let hover: DashboardHover
    private let system: SystemMonitor
    private let summaryHost: FirstClickHostingView<DashboardView>
    private let detailHost: FirstClickHostingView<DashboardDetailView>
    private let summary: DashboardWindow
    private let detail: DashboardWindow
    private var timer: Timer?
    private var restingSince: TimeInterval?
    private var outsideSince: TimeInterval?
    /// The row under the pointer that is not shown yet (nil: no row), and since when.
    private var pending: (row: DashboardStat?, since: TimeInterval)?
    /// Closed while the pointer was on the icon: it opens again only after leaving.
    private var waitForExit = false
    private var menuOpen = false { didSet { if !menuOpen { menuLogged = false } } }
    private var menuLogged = false
    private var monitors: [Any] = []

    init(model: AppModel, system: SystemMonitor, openSettings: @escaping () -> Void, play: @escaping () -> Void) {
        let hover = DashboardHover()
        self.hover = hover
        self.system = system
        summaryHost = FirstClickHostingView(rootView: DashboardView(model: model, system: system, hover: hover, openSettings: openSettings, play: play))
        detailHost = FirstClickHostingView(rootView: DashboardDetailView(system: system, stat: .cpu))
        summary = Self.window(summaryHost)
        detail = Self.window(detailHost)
        super.init()
        hover.close = { [weak self] in self?.hide() }
        // The "+N" menu of hidden apps: the pointer may leave the panels while it is open.
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in self?.menuOpen = true }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.menuOpen = false; self?.outsideSince = nil
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private static func window(_ content: NSView) -> DashboardWindow {
        let panel = DashboardWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
        return panel
    }

    // MARK: The pointer

    /// The icon's tracking area: the pointer arrived, so watch it until it leaves.
    override func mouseEntered(with event: NSEvent) { startTimer() }
    override func mouseExited(with event: NSEvent) {}

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func stopTimer() {
        timer?.invalidate(); timer = nil
        restingSince = nil
    }

    func tick() {
        let now = clock(), mouse = pointer()
        guard let icon = icon() else { hide(); stopTimer(); return }
        guard let mode else {
            guard icon.contains(mouse) else { waitForExit = false; stopTimer(); return }
            guard !waitForExit, PanelHoverRules.mayOpen(blockers()) else { restingSince = nil; return }
            if restingSince == nil { restingSince = now }
            if PanelHoverRules.due(restingSince, now, PanelHoverRules.openDelay) { show(.hover) }
            return
        }
        follow(mouse, now)
        guard mode == .hover else { return }
        let near = PanelHoverRules.near(mouse, icon: icon, panels: panelFrames)
        if menuOpen && !near && !menuLogged {
            menuLogged = true
            AppModel.log("Panel: a menu is open, so the panel waits with the pointer away")
        }
        if menuOpen || near {
            outsideSince = nil
        } else if outsideSince == nil {
            outsideSince = now
        } else if PanelHoverRules.due(outsideSince, now, PanelHoverRules.closeDelay) {
            hide()
        }
    }

    /// The section beside the summary, while it shows (for the self-test).
    var detailShown: DashboardStat? { detail.isVisible ? hover.detail : nil }
    var frames: (summary: NSRect, detail: NSRect?) { (summary.frame, detail.isVisible ? detail.frame : nil) }
    func rowOnScreen(_ stat: DashboardStat) -> NSRect? { hover.rows[stat].map(screenRect(of:)) }

    private var panelFrames: [NSRect] { [summary.frame] + (detail.isVisible ? [detail.frame] : []) }

    /// The side panel follows the row under the pointer, and stays while the pointer is on it or off the summary.
    private func follow(_ mouse: NSPoint, _ now: TimeInterval) {
        guard !(detail.isVisible && detail.frame.contains(mouse)), summary.frame.contains(mouse) else { pending = nil; return }
        let row = row(at: mouse)
        if row == hover.detail { pending = nil; return }
        if let pending, pending.row == row {
            if PanelHoverRules.due(pending.since, now, PanelHoverRules.switchDelay) { self.pending = nil; showDetail(row) }
        } else {
            pending = (row, now)
        }
    }

    /// Row frames come from SwiftUI, top-left based; the hosting view is flipped the same way.
    private func row(at mouse: NSPoint) -> DashboardStat? {
        var point = summaryHost.convert(summary.convertPoint(fromScreen: mouse), from: nil)
        if !summaryHost.isFlipped { point.y = summaryHost.bounds.height - point.y }
        // The rows' 2 pt spacing belongs to the rows, so moving down the list never shows nothing in between.
        return hover.rows.first { $0.value.insetBy(dx: 0, dy: -1.5).contains(point) }?.key
    }

    private func screenRect(of rect: CGRect) -> NSRect {
        var local = rect
        if !summaryHost.isFlipped { local.origin.y = summaryHost.bounds.height - rect.maxY }
        return summary.convertToScreen(summaryHost.convert(local, to: nil))
    }

    // MARK: Showing and hiding

    /// The status item's click.
    func click() {
        switch mode {
        case .click: hide()
        // Often the click comes just after the rest opened it: leave it as it is.
        case .hover: break
        case nil:
            show(hoverOn() ? .hover : .click)
            clicked()
        }
    }

    private func show(_ mode: Mode) {
        guard let icon = icon() else { return }
        willShow()
        self.mode = mode
        restingSince = nil; outsideSince = nil; pending = nil
        menuOpen = false   // no menu of ours can be open yet; a begin without its end must not keep the panel
        hover.detail = nil; detail.orderOut(nil)
        place(under: icon)
        summary.alphaValue = 0
        summary.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.08; summary.animator().alphaValue = 1 }
        summary.keyable = mode == .click
        if mode == .click { summary.makeKey() }
        watchClicks()
        startTimer()
    }

    func hide() {
        guard mode != nil else { return }
        mode = nil
        outsideSince = nil; pending = nil
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        if let icon = icon(), icon.contains(pointer()) { waitForExit = true }
        hover.detail = nil
        detail.orderOut(nil)
        summary.keyable = false
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.08; summary.animator().alphaValue = 0 }) { [weak self] in
            guard let self, self.mode == nil else { return }
            self.summary.orderOut(nil)
        }
        didHide()
    }

    /// A click anywhere else closes the panel; one on the icon is the icon's own (see `click`).
    private func watchClicks() {
        guard monitors.isEmpty else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in self?.hide() }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53, self.mode == .click { self.hide(); return nil }
                return event
            }
            if event.window === self.summary || event.window === self.detail || self.icon()?.contains(self.pointer()) == true { return event }
            self.hide()
            return event
        }) { monitors.append(local) }
    }

    private func screen(for icon: NSRect) -> NSRect {
        (NSScreen.screens.first { $0.frame.contains(NSPoint(x: icon.midX, y: icon.midY)) } ?? NSScreen.main)?.visibleFrame ?? .zero
    }

    private func place(under icon: NSRect) {
        summaryHost.layoutSubtreeIfNeeded()
        let size = summary.contentView?.fittingSize ?? summaryHost.fittingSize
        let frame = PanelHoverRules.summaryFrame(size: size, icon: icon, screen: screen(for: icon))
        if frame != summary.frame { summary.setFrame(frame, display: true); summary.invalidateShadow() }
    }

    private func showDetail(_ stat: DashboardStat?) {
        hover.detail = stat
        guard let stat else { detail.orderOut(nil); return }
        detailHost.rootView = DashboardDetailView(system: system, stat: stat)
        placeDetail()
        if hover.detail != nil && !detail.isVisible { detail.orderFrontRegardless() }
    }

    private func placeDetail() {
        guard let stat = hover.detail, let row = hover.rows[stat], let icon = icon() else {
            hover.detail = nil; detail.orderOut(nil); return
        }
        detailHost.layoutSubtreeIfNeeded()
        let size = detail.contentView?.fittingSize ?? detailHost.fittingSize
        let frame = PanelHoverRules.detailFrame(size: size, summary: summary.frame, row: screenRect(of: row), screen: screen(for: icon))
        if frame != detail.frame { detail.setFrame(frame, display: true); detail.invalidateShadow() }
    }

    /// New stats can change the sizes (top apps, a speed test, an update banner): both stay where they hang.
    func resize() {
        guard isShown, let icon = icon() else { return }
        place(under: icon)
        if hover.detail != nil { placeDetail() }
    }
}
