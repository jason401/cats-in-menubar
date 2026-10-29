import Cocoa

if let index = CommandLine.arguments.firstIndex(of: "--render-iconset"), CommandLine.arguments.count > index + 1 {
    TowerIcon.writeIconset(to: CommandLine.arguments[index + 1]); exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-panels"), CommandLine.arguments.count > index + 1 {
    renderPanels(to: CommandLine.arguments[index + 1]); exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-scenario"), CommandLine.arguments.count > index + 1 {
    renderScenario(to: CommandLine.arguments[index + 1]); exit(0)
}
if CommandLine.arguments.contains("--probe") { runProbe(); exit(0) }
if let index = CommandLine.arguments.firstIndex(of: "--render-lineup"), CommandLine.arguments.count > index + 1 {
    renderLineup(to: CommandLine.arguments[index + 1]); exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-motion"), CommandLine.arguments.count > index + 1 {
    renderMotion(to: CommandLine.arguments[index + 1]); exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-held"), CommandLine.arguments.count > index + 1 {
    renderHeld(to: CommandLine.arguments[index + 1]); exit(0)
}
if CommandLine.arguments.contains("--self-test") { runSelfTests(); exit(0) }
if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
    renderPreview(to: CommandLine.arguments[index + 1]); exit(0)
}
if CommandLine.arguments.contains("--diagnostics") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let monitor = MenuBarMonitor()
    guard let screen = NSScreen.screens.first else { print("No screen"); exit(1) }
    print("Accessibility: \(MenuBarMonitor.trusted), screen: \(screen.frame), visible: \(screen.visibleFrame)")
    monitor.scan(screen: screen.frame, barHeight: max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top), ownItem: nil) { snapshot in
        print("Reliable: \(snapshot.reliable); \(snapshot.message)")
        print("Occupied intervals: \(snapshot.obstacles)")
        exit(snapshot.reliable ? 0 : 2)
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 15))
    print("Scan timed out"); exit(3)
}
let app = NSApplication.shared
if !NSRunningApplication.runningApplications(withBundleIdentifier: "local.catsinmenubar")
    .filter({ $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }).isEmpty { exit(0) }
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
