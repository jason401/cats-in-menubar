import Cocoa
import ApplicationServices

// Finder shortcuts, both off by default (Settings > Accessibility):
// - Cut and paste: ⌘X in Finder copies the selection (Finder itself sends ⌘C), and the next ⌘V becomes
//   Finder's own "Move Item Here" (⌥⌘V). Finder does the move, so Undo, name conflicts, permissions and
//   progress work as usual, and no Automation permission is needed.
// - Paste images as files: ⌘V in a Finder folder while the clipboard holds an image (and no files) saves
//   it as a PNG in a private folder, offers that file to Finder and replays ⌘V, so Finder copies it in
//   where it would paste. The clipboard is put back as it was a moment later.
// Text fields (renaming, search) always get the keys unchanged. Needs Accessibility, like the cats.

/// What the tap does with one key press. A pure decision, so it can be tested without a keyboard.
enum FinderKeyAction: Equatable {
    case pass            // leave the key alone
    case cutAsCopy       // ⌘X → ⌘C, and remember a cut
    case moveHere        // ⌘V → ⌥⌘V
    case pasteImage      // swallow ⌘V and paste the image as a file
    case forgetCut       // let the key through and drop the pending cut (⌘C, Escape)
}

struct FinderKeyContext: Equatable {
    var cutPaste = false, pasteImages = false
    var finderFront = false, editingText = false
    var cutPending = false              // a cut whose clipboard is still the current one
    var clipboardHasFiles = false, clipboardHasImage = false
}

enum FinderKeys {
    static let x: Int64 = 7, c: Int64 = 8, v: Int64 = 9, escape: Int64 = 53

    /// Only ⌘ alone (⇧, ⌃ and ⌥ combinations are other commands, such as ⌥⌘V itself).
    static func commandOnly(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand) && flags.intersection([.maskShift, .maskControl, .maskAlternate]).isEmpty
    }

    static func action(key: Int64, flags: CGEventFlags, _ context: FinderKeyContext) -> FinderKeyAction {
        let k = context
        guard k.finderFront, k.cutPaste || k.pasteImages else { return .pass }
        if key == escape { return k.cutPending && !k.editingText ? .forgetCut : .pass }
        guard commandOnly(flags), !k.editingText else { return .pass }
        if key == x { return k.cutPaste ? .cutAsCopy : .pass }
        if key == c { return k.cutPending ? .forgetCut : .pass }
        guard key == v else { return .pass }
        if k.cutPaste && k.cutPending && k.clipboardHasFiles { return .moveHere }
        if k.pasteImages && k.clipboardHasImage && !k.clipboardHasFiles { return .pasteImage }
        return .pass
    }

    /// Focused roles that take typing; the keys stay theirs.
    static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField", "AXSecureTextField"]

    /// "Pasted Image 2026-11-23 at 21.30.15.png", like macOS names screenshots.
    static func imageName(at date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Pasted Image \(format.string(from: date)).png"
    }
}

/// Runs the tap on its own thread, like scroll direction, so a busy main thread never delays typing.
final class FinderShortcuts: ObservableObject {
    static let shared = FinderShortcuts()
    static let finderID = "com.apple.finder"
    /// Marks the ⌘V this app replays, so the tap lets it through.
    static let replayMarker: Int64 = 0x4361_7473   // "Cats"
    @Published private(set) var running = false

    private let lock = NSLock()
    // Guarded by lock; shared with the tap thread.
    private var cutPaste = false, pasteImages = false, finderFront = false
    private var cutChangeCount: Int?        // the clipboard of the last cut
    private var tapPort: CFMachPort?
    private var tapLoop: CFRunLoop?
    private var thread: Thread?
    private var restore: (count: Int, items: [[NSPasteboard.PasteboardType: Data]])?

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.setFinderFront(app?.bundleIdentifier == Self.finderID)
        }
    }

    private func setFinderFront(_ front: Bool) { lock.lock(); finderFront = front; lock.unlock() }

    /// Starts or stops the tap from the settings and the Accessibility permission.
    func apply() {
        let defaults = UserDefaults.standard
        lock.lock()
        cutPaste = defaults.bool(forKey: Pref.finderCutPaste)
        pasteImages = defaults.bool(forKey: Pref.finderPasteImages)
        if !cutPaste { cutChangeCount = nil }
        let wanted = (cutPaste || pasteImages) && MenuBarMonitor.trusted
        lock.unlock()
        setFinderFront(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderID)
        if wanted && thread == nil { start() } else if !wanted && thread != nil { stop() }
    }

    private func start() {
        let thread = Thread { [weak self] in self?.runTap() }
        thread.name = "Finder shortcuts"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }
    private func stop() {
        lock.lock(); let loop = tapLoop; cutChangeCount = nil; lock.unlock()
        if let loop { CFRunLoopStop(loop) }
        thread = nil
        running = false
        AppModel.log("Finder shortcuts stopped")
    }
    private func runTap() {
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: finderTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            AppModel.log("Finder shortcuts could not start their event tap (Accessibility needed)")
            DispatchQueue.main.async { self.thread = nil; self.running = false }
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        lock.lock(); tapPort = port; tapLoop = CFRunLoopGetCurrent(); lock.unlock()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        DispatchQueue.main.async { self.running = true }
        AppModel.log("Finder shortcuts started")
        CFRunLoopRun()
        CFMachPortInvalidate(port)
        lock.lock(); tapPort = nil; tapLoop = nil; lock.unlock()
    }
    fileprivate func reenable() { lock.lock(); if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }; lock.unlock() }

    /// The tap's work for one key press, on the tap thread. Returns nil to swallow the key.
    fileprivate func handle(_ event: CGEvent) -> CGEvent? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker { return event }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard [FinderKeys.x, FinderKeys.c, FinderKeys.v, FinderKeys.escape].contains(key) else { return event }
        lock.lock()
        var context = FinderKeyContext(cutPaste: cutPaste, pasteImages: pasteImages, finderFront: finderFront)
        let cut = cutChangeCount
        lock.unlock()
        guard context.finderFront else { return event }
        let board = NSPasteboard.general
        context.cutPending = cut != nil && cut == board.changeCount
        if key == FinderKeys.v {
            let types = board.types ?? []
            context.clipboardHasFiles = types.contains(.fileURL)
            context.clipboardHasImage = types.contains(.png) || types.contains(.tiff)
        }
        // Only ask for focus when the key might change: the lookup goes to Finder over Accessibility.
        if FinderKeys.action(key: key, flags: event.flags, context) != .pass { context.editingText = editingText() }
        switch FinderKeys.action(key: key, flags: event.flags, context) {
        case .pass:
            return event
        case .forgetCut:
            lock.lock(); cutChangeCount = nil; lock.unlock()
            return event
        case .cutAsCopy:
            event.setIntegerValueField(.keyboardEventKeycode, value: FinderKeys.c)
            let before = board.changeCount
            DispatchQueue.main.async { self.noteCut(after: before, tries: 20) }
            return event
        case .moveHere:
            event.flags.insert(.maskAlternate)
            lock.lock(); cutChangeCount = nil; lock.unlock()
            AppModel.log("Finder: moved the cut items")
            return event
        case .pasteImage:
            DispatchQueue.main.async { self.pasteImage() }
            return nil
        }
    }

    /// Asks Finder itself, with a short timeout on Finder's element only: a timeout set on the system-wide
    /// element would become the default for every Accessibility question this app asks.
    private func editingText() -> Bool {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: Self.finderID).first else { return false }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role) == .success else { return false }
        return FinderKeys.textRoles.contains(role as? String ?? "")
    }

    /// Finder writes the copied files a moment after ⌘C; the cut is that clipboard. Nothing selected, no cut.
    private func noteCut(after before: Int, tries: Int) {
        let board = NSPasteboard.general
        if board.changeCount != before {
            let files = board.types?.contains(.fileURL) ?? false
            lock.lock(); cutChangeCount = files ? board.changeCount : nil; lock.unlock()
            if files { AppModel.log("Finder: cut \(board.pasteboardItems?.count ?? 0) items") }
        } else if tries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.noteCut(after: before, tries: tries - 1) }
        }
    }

    // MARK: Pasting an image as a file

    static var imageFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.catsinmenubar").appendingPathComponent("Pasted Images")
    }

    /// The clipboard's image as PNG data: PNG as it is, anything else converted. Very large images are left alone.
    static func pngData(from board: NSPasteboard) -> Data? {
        if let png = board.data(forType: .png) { return png.count <= 64 << 20 ? png : nil }
        guard let tiff = board.data(forType: .tiff), tiff.count <= 256 << 20, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let png = rep.representation(using: .png, properties: [:])
        return png.flatMap { $0.count <= 64 << 20 ? $0 : nil }
    }

    private func pasteImage() {
        let board = NSPasteboard.general
        guard let png = Self.pngData(from: board) else { NSSound.beep(); return }
        let fm = FileManager.default
        let folder = Self.imageFolder.appendingPathComponent(UUID().uuidString)
        // Earlier pastes are done: Finder copied those files long ago.
        if let old = try? fm.contentsOfDirectory(at: Self.imageFolder, includingPropertiesForKeys: nil) { old.forEach { try? fm.removeItem(at: $0) } }
        let file = folder.appendingPathComponent(FinderKeys.imageName(at: Date()))
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: file)
        } catch { AppModel.log("Finder: could not save the pasted image: \(error.localizedDescription)"); NSSound.beep(); return }
        // Keep what was on the clipboard, offer the file, replay ⌘V, then put the clipboard back.
        let saved = (board.pasteboardItems ?? []).map { item in
            Dictionary(item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }, uniquingKeysWith: { a, _ in a })
        }
        board.clearContents()
        board.writeObjects([file as NSURL])
        restore = (board.changeCount, saved)
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let key = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(FinderKeys.v), keyDown: down) else { continue }
            key.flags = .maskCommand
            key.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            key.post(tap: .cghidEventTap)
        }
        AppModel.log("Finder: pasted an image as \(file.lastPathComponent)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.restoreClipboard() }
    }

    /// Puts the clipboard back unless something else was copied in the meantime.
    private func restoreClipboard() {
        guard let restore else { return }
        self.restore = nil
        let board = NSPasteboard.general
        guard board.changeCount == restore.count else { return }
        board.clearContents()
        let items = restore.items.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        board.writeObjects(items)
    }
}

private func finderTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let shortcuts = Unmanaged<FinderShortcuts>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { shortcuts.reenable(); return Unmanaged.passUnretained(event) }
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    return shortcuts.handle(event).map { Unmanaged.passUnretained($0) }
}
