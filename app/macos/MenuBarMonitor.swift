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
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func scan(screen: NSRect, barHeight: CGFloat, ownItem: NSRect?, completion: @escaping (MenuBarSnapshot) -> Void) {
        guard !scanning else { return }
        guard Self.trusted else {
            completion(MenuBarSnapshot(obstacles: [], reliable: false, message: "Accessibility access is needed to find empty space.")); return
        }
        scanning = true
        let apps = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && ($0.activationPolicy != .prohibited ||
                $0.bundleIdentifier == "com.apple.controlcenter" || $0.bundleIdentifier == "com.apple.systemuiserver")
        }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // AX coordinates use a top-left origin relative to the primary display.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.maxY
        let band = CGRect(x: screen.minX, y: primaryTop - screen.maxY, width: screen.width, height: barHeight)
        queue.async {
            var obstacles: [Lane] = []
            var frontRead = false
            var systemRead = false
            var incomplete = false
            var unreadableApps: [String] = []
            for app in apps {
                let element = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(element, 0.06)
                if app.processIdentifier == front {
                    let result = Self.attribute(element, kAXMenuBarAttribute)
                    if result.0 == .success, let root = result.1 {
                        let found = Self.items(root, band: band)
                        obstacles += found.0.map { Lane(lower: $0.minX - screen.minX, upper: $0.maxX - screen.minX) }
                        frontRead = found.1 && !found.0.isEmpty
                    }
                }
                let isSystemBar = app.bundleIdentifier == "com.apple.controlcenter" || app.bundleIdentifier == "com.apple.systemuiserver"
                var extras = Self.attribute(element, kAXExtrasMenuBarAttribute)
                if isSystemBar && (extras.0 == .attributeUnsupported || extras.0 == .noValue) {
                    extras = Self.attribute(element, kAXMenuBarAttribute)
                }
                if extras.0 == .success, let root = extras.1 {
                    let found = Self.items(root, band: band)
                    obstacles += found.0.map { Lane(lower: $0.minX - screen.minX, upper: $0.maxX - screen.minX) }
                    if !found.1 { incomplete = true; unreadableApps.append(app.bundleIdentifier ?? "unknown") }
                    if isSystemBar { systemRead = found.1 && (systemRead || !found.0.isEmpty) }
                } else if extras.0 == .cannotComplete && (app.activationPolicy != .prohibited) {
                    // A temporarily unresponsive status app must not turn its space into a playground.
                    incomplete = true
                    unreadableApps.append(app.bundleIdentifier ?? "unknown")
                }
            }
            if let ownItem { obstacles.append(Lane(lower: ownItem.minX - screen.minX, upper: ownItem.maxX - screen.minX)) }
            let reliable = frontRead && systemRead && !incomplete
            let snapshot = MenuBarSnapshot(obstacles: obstacles, reliable: reliable,
                message: reliable ? "Menu layout detected" : "Waiting for menu layout (app menu: \(frontRead), system icons: \(systemRead)). Unreadable: \(unreadableApps.joined(separator: ", "))")
            DispatchQueue.main.async { self.scanning = false; completion(snapshot) }
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
    private static func items(_ root: AXUIElement, band: CGRect) -> ([CGRect], Bool) {
        var rectangles: [CGRect] = []
        var reliable = true
        func visit(_ element: AXUIElement, depth: Int) {
            guard depth < 5 else { reliable = false; return }
            var roleValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String ?? ""
            var childrenValue: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
            let children = childrenValue as? [AXUIElement] ?? []
            if role == kAXMenuBarItemRole || (depth > 0 && children.isEmpty) {
                if let frame = rect(element), frame.width > 0, frame.height > 0 {
                    if frame.intersects(band) { rectangles.append(frame.intersection(band)) }
                } else {
                    var hidden: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(element, "AXHidden" as CFString, &hidden)
                    if (hidden as? Bool) != true { reliable = false }
                }
                return // Never descend into dropdown contents.
            }
            if error == .cannotComplete { reliable = false }
            for child in children { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return (rectangles, reliable)
    }
}
