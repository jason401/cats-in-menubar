import Cocoa
import ApplicationServices

struct MenuBarSnapshot {
    var obstacles: [Lane]
    var reliable: Bool
    var message: String
}

final class MenuBarMonitor {
    private let queue = DispatchQueue(label: "local.catsinmenubar.menu-layout", qos: .utility)
    private var scanning = false
    // Asking for trust goes through tccd; once every few seconds is plenty.
    private static var trustedCache = (value: false, at: -100.0)
    static var trusted: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - trustedCache.at > 3 { trustedCache = (AXIsProcessTrusted(), now) }
        return trustedCache.value
    }
    // Whether a process can own menu bar items, looked up once per process (bundle lookups are slow).
    private var candidates: [pid_t: Bool] = [:]
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    // Status-item owners seen recently; only these can make a scan incomplete when they time out.
    private var knownExtras = Set<pid_t>()
    static let systemBars: Set<String> = ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"]

    func scan(screen: NSRect, barHeight: CGFloat, ownItem: NSRect?, completion: @escaping (MenuBarSnapshot) -> Void) {
        guard !scanning else { return }
        guard Self.trusted else {
            completion(MenuBarSnapshot(obstacles: [], reliable: false, message: "Accessibility access is needed to find empty space.")); return
        }
        scanning = true
        // Helpers such as WebKit or XPC services never own menu bar items.
        let running = NSWorkspace.shared.runningApplications
        let alive = Set(running.map(\.processIdentifier))
        candidates = candidates.filter { alive.contains($0.key) }
        let apps = running.filter { app in
            if let known = candidates[app.processIdentifier] { return known }
            let relevant = app.bundleURL?.pathExtension == "app" || Self.systemBars.contains(app.bundleIdentifier ?? "")
            candidates[app.processIdentifier] = relevant
            return relevant
        }
        // Clicking a status item activates an agent app that has no menus; the bar keeps the previous app's menus.
        let front = (NSWorkspace.shared.menuBarOwningApplication ?? NSWorkspace.shared.frontmostApplication)?.processIdentifier
        // AX x coordinates match AppKit; y uses a top-left origin. Every display mirrors the menu bar,
        // and AX may report items on any of them: app menus align left, status items align right.
        let screens = NSScreen.screens.map(\.frame)
        let known = knownExtras
        queue.async {
            var obstacles: [Lane] = []
            var frontRead = false
            var systemRead = false
            var unreadableApps: [String] = []
            var extrasOwners = Set<pid_t>()
            func lanes(_ frames: [CGRect], rightAligned: Bool) -> [Lane] {
                frames.compactMap { frame in
                    guard frame.minY < barHeight, frame.maxY > 0,
                          let display = screens.first(where: { $0.minX <= frame.midX && frame.midX < $0.maxX }) else { return nil }
                    let lower = rightAligned ? frame.minX - display.maxX + screen.maxX : frame.minX - display.minX + screen.minX
                    return Lane(lower: lower - screen.minX, upper: lower + frame.width - screen.minX)
                }
            }
            for app in apps {
                let element = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(element, 0.1)
                let id = app.bundleIdentifier ?? "unknown"
                if app.processIdentifier == front {
                    let result = Self.attribute(element, kAXMenuBarAttribute)
                    if result.0 == .success, let root = result.1 {
                        let found = Self.items(root)
                        obstacles += lanes(found.0, rightAligned: false)
                        frontRead = found.1 && !found.0.isEmpty
                    }
                }
                let extras = Self.attribute(element, kAXExtrasMenuBarAttribute)
                if extras.0 == .success, let root = extras.1 {
                    extrasOwners.insert(app.processIdentifier)
                    let found = Self.items(root)
                    obstacles += lanes(found.0, rightAligned: true)
                    if !found.1 { unreadableApps.append(id) }
                    if Self.systemBars.contains(id) && found.1 && !found.0.isEmpty { systemRead = true }
                } else if extras.0 == .cannotComplete && known.contains(app.processIdentifier) {
                    // A temporarily unresponsive status app must not turn its space into a playground.
                    extrasOwners.insert(app.processIdentifier)
                    unreadableApps.append(id)
                }
            }
            if let ownItem { obstacles.append(Lane(lower: ownItem.minX - screen.minX, upper: ownItem.maxX - screen.minX)) }
            let reliable = frontRead && systemRead && unreadableApps.isEmpty
            let snapshot = MenuBarSnapshot(obstacles: obstacles, reliable: reliable,
                message: reliable ? "Menu layout detected" : "Waiting for menu layout (app menu: \(frontRead), system icons: \(systemRead)). Unreadable: \(unreadableApps.joined(separator: ", "))")
            DispatchQueue.main.async { self.knownExtras = extrasOwners; self.scanning = false; completion(snapshot) }
        }
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> (AXError, AXUIElement?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (error, nil) }
        return (error, unsafeBitCast(value, to: AXUIElement.self))
    }
    private static func rect(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    /// Top-level item frames of a menu bar. Dropdown contents are never visited.
    private static func items(_ root: AXUIElement) -> ([CGRect], Bool) {
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return ([], false) }
        var rectangles: [CGRect] = []
        var reliable = true
        for child in children {
            if let frame = rect(child), frame.width > 0, frame.height > 0 { rectangles.append(frame); continue }
            var hidden: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(child, "AXHidden" as CFString, &hidden)
            if (hidden as? Bool) != true { reliable = false }
        }
        return (rectangles, reliable)
    }
}
