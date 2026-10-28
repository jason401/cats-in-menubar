import Cocoa
import ApplicationServices

// Development probe: logs Accessibility roles and frames (never titles) of menu bar trees.
func runProbe() {
    func copy(_ e: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
        var v: CFTypeRef?; let err = AXUIElementCopyAttributeValue(e, name as CFString, &v); return (err, v)
    }
    func frame(_ e: AXUIElement) -> String {
        var p = CGPoint.zero, s = CGSize.zero
        if let v = copy(e, kAXPositionAttribute).1, CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        if let v = copy(e, kAXSizeAttribute).1, CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgSize, &s) }
        return "(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height)))"
    }
    func dump(_ e: AXUIElement, _ depth: Int, _ out: inout [String]) {
        let role = copy(e, kAXRoleAttribute).1 as? String ?? "?"
        let sub = copy(e, kAXSubroleAttribute).1 as? String ?? ""
        let children = copy(e, kAXChildrenAttribute)
        let list = children.1 as? [AXUIElement] ?? []
        out.append(String(repeating: "  ", count: depth) + "\(role) \(sub) \(frame(e)) children \(list.count) err \(children.0.rawValue)")
        if depth < 2 && role != kAXMenuBarItemRole { for c in list.prefix(40) { dump(c, depth + 1, &out) } }
    }
    var out = ["PROBE trusted \(AXIsProcessTrusted()) statusbar \(NSStatusBar.system.thickness) screens \(NSScreen.screens.map { "\($0.frame) visible \($0.visibleFrame)" })"]
    let front = NSWorkspace.shared.frontmostApplication
    let ids = Set([front?.bundleIdentifier ?? "", "com.apple.controlcenter", "com.apple.systemuiserver"])
    for app in NSWorkspace.shared.runningApplications where ids.contains(app.bundleIdentifier ?? "") {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 1)
        var names: CFArray?
        AXUIElementCopyAttributeNames(el, &names)
        out.append("APP \(app.bundleIdentifier ?? "?") policy \(app.activationPolicy.rawValue) attrs \((names as? [String]) ?? [])")
        for attr in [kAXMenuBarAttribute, kAXExtrasMenuBarAttribute] {
            let r = copy(el, attr)
            out.append(" \(attr) err \(r.0.rawValue)")
            if let v = r.1, CFGetTypeID(v) == AXUIElementGetTypeID() { dump(v as! AXUIElement, 1, &out) }
        }
        let windows = copy(el, kAXWindowsAttribute).1 as? [AXUIElement] ?? []
        out.append(" windows \(windows.count)")
        for w in windows.prefix(30) { dump(w, 1, &out) }
    }
    for app in NSWorkspace.shared.runningApplications {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.3)
        let r = copy(el, kAXExtrasMenuBarAttribute)
        if r.0 == .success, let v = r.1, CFGetTypeID(v) == AXUIElementGetTypeID() { out.append("EXTRAS \(app.bundleIdentifier ?? "?") policy \(app.activationPolicy.rawValue)"); dump(v as! AXUIElement, 1, &out) }
    }
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.3)
    var last = ""
    for x in stride(from: Float(0), through: 1920, by: 4) {
        var hit: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(system, x, 15, &hit)
        var pid: pid_t = 0
        var line = "err \(err.rawValue)"
        if let hit { AXUIElementGetPid(hit, &pid); line = "\(copy(hit, kAXRoleAttribute).1 as? String ?? "?") \(copy(hit, kAXSubroleAttribute).1 as? String ?? "") \(frame(hit)) pid \(pid) \(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?")" }
        if line != last { out.append("HIT x=\(Int(x)) \(line)"); last = line }
    }
    let wl = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in wl where (w[kCGWindowLayer as String] as? Int ?? 0) >= 20 && (w[kCGWindowLayer as String] as? Int ?? 0) <= 30 {
        out.append("WIN layer \(w[kCGWindowLayer as String] ?? 0) owner \(w[kCGWindowOwnerName as String] ?? "?") bounds \((w[kCGWindowBounds as String] as? [String: Any]).map { "\($0["X"] ?? 0),\($0["Y"] ?? 0) \($0["Width"] ?? 0)x\($0["Height"] ?? 0)" } ?? "")")
    }
    for line in out { AppModel.log(line) }
}
