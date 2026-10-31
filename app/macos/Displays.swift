import Cocoa

/// A screen the cats can live on: its stable ID (it survives reconnects and restarts), name and
/// whether it has its own menu bar.
struct DisplayInfo: Equatable, Identifiable {
    let id: String
    let name: String
    let hasMenuBar: Bool
}

enum Displays {
    /// The display's UUID, which stays the same across reconnects, unlike its display number.
    static func id(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    /// Without "Displays have separate Spaces", only the main display has a menu bar.
    static func hasMenuBar(_ screen: NSScreen) -> Bool { screen == NSScreen.screens.first || NSScreen.screensHaveSeparateSpaces }
    /// The real bar height (30 pt on macOS 27, not NSStatusBar.thickness).
    static func barHeight(of screen: NSScreen) -> CGFloat { max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top) }
    static var all: [DisplayInfo] {
        NSScreen.screens.compactMap { screen in id(of: screen).map { DisplayInfo(id: $0, name: screen.localizedName, hasMenuBar: hasMenuBar(screen)) } }
    }
    static func screen(id: String) -> NSScreen? { NSScreen.screens.first { Self.id(of: $0) == id } }
    /// The chosen display, or the main one when none is chosen, it is not connected or it has no menu bar.
    static func pick(chosen: String, available: [DisplayInfo]) -> DisplayInfo? {
        available.first { $0.id == chosen && $0.hasMenuBar } ?? available.first
    }
    static func target(chosen: String) -> NSScreen? {
        pick(chosen: chosen, available: all).flatMap { screen(id: $0.id) } ?? NSScreen.screens.first
    }
    /// Status items sit at the same distance from the right edge on every menu bar.
    static func mapRightAligned(_ rect: NSRect, from: NSRect, to: NSRect) -> NSRect {
        rect.offsetBy(dx: to.maxX - from.maxX, dy: to.maxY - from.maxY)
    }
}
