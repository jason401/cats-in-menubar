import Cocoa
import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

// Finder shortcuts (Settings > Accessibility).
// ⌘X collects items to move. With copy accumulation enabled, ⌘C collects items to copy.
// ⌘V uses the batch while its clipboard is current. ⌃⌘V applies the batch after another copy.
// The image shortcut saves a clipboard image as PNG in the current folder.
// Finder Automation reads the selection and destination, and Accessibility identifies text fields.

/// What the tap does with one key press. A pure decision, so it can be tested without a keyboard.
enum FinderKeyAction: Equatable {
    case pass
    case collect(FinderTransfer)
    case transfer(FinderTransfer)
    case waitForSelection
    case swallow
    case pasteImage
}

struct FinderKeyContext: Equatable {
    var cutPaste = false, copyAdds = false, pasteImages = false
    var finderFront = false, editingText = false
    var batchKind: FinderTransfer?
    var clipboardUnchanged = false
    var collecting = false, transferring = false, pastingImage = false
}

enum FinderKeys {
    static let x: Int64 = 7, c: Int64 = 8, v: Int64 = 9
    static let batchShortcut = "⌃⌘V"
    private static let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// ⌘ held, without ⌃ or ⌥. ⇧ may be held.
    static func command(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand) && flags.intersection([.maskControl, .maskAlternate]).isEmpty
    }

    static func explicitTransfer(_ flags: CGEventFlags) -> Bool {
        flags.intersection(modifiers) == [.maskControl, .maskCommand]
    }

    static func plainCopy(_ flags: CGEventFlags) -> Bool {
        flags.intersection(modifiers) == .maskCommand
    }

    static func route(key: Int64, flags: CGEventFlags, _ k: FinderKeyContext) -> FinderKeyAction {
        guard k.finderFront, !k.editingText else { return .pass }
        if k.cutPaste && key == x && command(flags) { return k.transferring ? .swallow : .collect(.move) }
        if k.cutPaste && k.copyAdds && key == c && plainCopy(flags) && !k.transferring { return .collect(.copy) }
        guard key == v, command(flags) || explicitTransfer(flags) else { return .pass }

        let explicit = explicitTransfer(flags)
        if k.cutPaste {
            if k.collecting { return .waitForSelection }
            if let kind = k.batchKind, explicit || k.clipboardUnchanged {
                return k.transferring ? .swallow : .transfer(kind)
            }
        }
        if !explicit && k.pasteImages && !flags.contains(.maskShift) && !k.pastingImage { return .pasteImage }
        return .pass
    }

    /// Focused roles that take typing; the keys stay theirs.
    static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSecureTextField"]

    /// Neither the copied image nor its PNG may be larger than this.
    static let maxImageBytes = 64 << 20

    /// Which clipboard type holds the image: none when files are copied (they carry icons as images),
    /// PNG first, then any other image type.
    static func imageType(_ types: [String]) -> String? {
        if types.contains(UTType.fileURL.identifier) { return nil }
        if types.contains(UTType.png.identifier) { return UTType.png.identifier }
        return types.first { UTType($0)?.conforms(to: .image) == true }
    }

    /// "Pasted_Image_20261123_213005.png".
    static func imageName(at date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.timeZone = .current
        format.dateFormat = "'Pasted_Image_'yyyyMMdd_HHmmss'.png'"
        return format.string(from: date)
    }

    /// A free name like Finder picks: "name.ext", then "name 2.ext", "name 3.ext"…
    static func freeName(_ name: String, taken: (String) -> Bool) -> String {
        guard taken(name) else { return name }
        let ext = (name as NSString).pathExtension, base = (name as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !taken(candidate) { return candidate }
            n += 1
        }
    }

    /// Errors that mean this app may not touch the item, so Finder is asked to move it instead.
    static func needsFinder(_ error: Error) -> Bool {
        func check(_ e: NSError) -> Bool {
            if e.domain == NSCocoaErrorDomain && (e.code == NSFileWriteNoPermissionError || e.code == NSFileReadNoPermissionError) { return true }
            if e.domain == NSPOSIXErrorDomain && (e.code == Int(EACCES) || e.code == Int(EPERM)) { return true }
            return false
        }
        let e = error as NSError
        if check(e) { return true }
        if let under = e.userInfo[NSUnderlyingErrorKey] as? NSError { return check(under) }
        return false
    }

    /// After Finder's move: the items not moved. An item moved once its source is gone ("no such file",
    /// not any other trouble) and its name is in the folder.
    static func remaining(_ items: [URL], sourceGone: (URL) -> Bool, arrived: (URL) -> Bool) -> [URL] {
        items.filter { !(sourceGone($0) && arrived($0)) }
    }

    /// A later ⌘X adds to the cut: new items join the end, once each. An item inside a cut folder is
    /// already part of it, so it is left out (and folders cut later take in what was cut from inside them).
    static func merge(_ cut: [URL], adding new: [URL]) -> [URL] {
        func path(_ url: URL) -> String { url.standardizedFileURL.path }
        func inside(_ item: URL, _ folder: URL) -> Bool { path(item).hasPrefix(path(folder).hasSuffix("/") ? path(folder) : path(folder) + "/") }
        var all: [URL] = []
        for url in cut + new where !all.contains(where: { path($0) == path(url) }) { all.append(url) }
        return all.filter { item in !all.contains { inside(item, $0) } }
    }

    /// "2 of 5", shown only for more than one item.
    static func position(_ done: Int, of total: Int) -> String? {
        total > 1 ? "\(min(max(done + 1, 1), total)) of \(total)" : nil
    }
}

enum FinderTransfer: Equatable { case move, copy }

struct FinderFileBatch {
    private(set) var kind: FinderTransfer = .move
    private(set) var urls: [URL] = []
    private var pastedCopy = false
    var clipboardCount: Int?

    mutating func collect(_ new: [URL], as kind: FinderTransfer, appending: Bool) {
        let earlier = appending && self.kind == kind && !pastedCopy ? urls : []
        self.kind = kind
        urls = FinderKeys.merge(earlier, adding: new)
        pastedCopy = false
    }

    mutating func remove(_ url: URL, from clipboard: NSPasteboard) -> Bool {
        guard let index = urls.firstIndex(of: url) else { return false }
        urls.remove(at: index)
        let expected = clipboardCount
        syncClipboard(clipboard, expecting: expected)
        return true
    }

    /// Replaces the file list only while the expected clipboard is still current.
    mutating func syncClipboard(_ clipboard: NSPasteboard, expecting expected: Int?) {
        clipboardCount = nil
        guard let expected, clipboard.changeCount == expected else { return }
        clipboard.clearContents()
        if !urls.isEmpty && clipboard.writeObjects(urls as [NSURL]) { clipboardCount = clipboard.changeCount }
    }

    mutating func finish(_ transfer: FinderTransfer, remaining: [URL], succeeded: Bool) {
        urls = remaining
        if urls.isEmpty { clipboardCount = nil }
        if kind == .copy && transfer == .copy && succeeded { pastedCopy = true }
    }
}

/// What the floating panel shows.
struct CutHUDState: Equatable {
    struct Item: Equatable, Identifiable { let url: URL; var id: URL { url }; var name: String { url.lastPathComponent } }
    struct Progress: Equatable {
        var transfer: FinderTransfer
        var done = 0, total = 0
        var name = ""
        var fraction: Double?
    }
    struct Result: Equatable { var transfer: FinderTransfer; var count = 0, failed = 0 }
    var items: [Item] = []
    var kind: FinderTransfer = .move
    var clipboardUnchanged = false
    var progress: Progress?
    var result: Result?
}

/// The tap runs on its own thread, like scroll direction, so a busy main thread never delays typing.
/// Finder and file work runs on background queues; the panel on the main thread.
final class FinderShortcuts: ObservableObject {
    static let shared = FinderShortcuts()
    static let finderID = "com.apple.finder"
    /// Marks synthetic keys so the tap lets them through.
    static let replayMarker: Int64 = 0x4361_7473   // "Cats"
    @Published private(set) var running = false
    @Published private(set) var hud = CutHUDState()

    private let lock = NSLock()
    // Guarded by lock; shared with the tap thread.
    private var cutPaste = false, copyAdds = true, pasteImages = false, showHUD = true, addToCut = true, finderFront = false
    private var batch = FinderFileBatch()
    private var pendingSelections = 0
    private var transferring = false, pastingImage = false
    private var generation = 0           // invalidates work when the list is cleared or transferred
    private var tapPort: CFMachPort?
    private var tapLoop: CFRunLoop?
    private var thread: Thread?

    private let work = DispatchQueue(label: "Finder shortcuts", qos: .userInitiated)
    private let pasteboard = DispatchQueue(label: "Finder shortcuts clipboard", qos: .utility)
    private var panel: NSPanel?
    private var clipboardWatch: Timer?
    private var dismiss: DispatchWorkItem?

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.setFinderFront(app?.bundleIdentifier == Self.finderID)
        }
    }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    private func setFinderFront(_ front: Bool) {
        locked { finderFront = front }
        refreshPanel()
    }

    /// Starts or stops the tap from the settings and the Accessibility permission.
    func apply() {
        let defaults = UserDefaults.standard
        let (wanted, clearBatch): (Bool, Bool) = locked {
            cutPaste = defaults.bool(forKey: Pref.finderCutPaste)
            copyAdds = defaults.object(forKey: Pref.finderCopyAdds) as? Bool ?? true
            pasteImages = defaults.bool(forKey: Pref.finderPasteImages)
            showHUD = defaults.object(forKey: Pref.finderCutPasteHUD) as? Bool ?? true
            addToCut = defaults.object(forKey: Pref.finderCutAdds) as? Bool ?? true
            return ((cutPaste || pasteImages) && MenuBarMonitor.trusted, !cutPaste || (!copyAdds && batch.kind == .copy))
        }
        if clearBatch { reset() }
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
        let loop = locked { tapLoop }
        if let loop { CFRunLoopStop(loop) }
        thread = nil
        running = false
        reset()
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
        locked { tapPort = port; tapLoop = CFRunLoopGetCurrent() }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        DispatchQueue.main.async { self.running = true }
        AppModel.log("Finder shortcuts started")
        CFRunLoopRun()
        CFMachPortInvalidate(port)
        locked { tapPort = nil; tapLoop = nil }
    }
    fileprivate func reenable() {
        locked { if let tapPort, AXIsProcessTrusted() { CGEvent.tapEnable(tap: tapPort, enable: true) } }
    }

    /// The tap's work for one key press, on the tap thread. Returns nil to swallow the key.
    fileprivate func handle(_ event: CGEvent) -> CGEvent? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker { return event }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        guard (key == FinderKeys.x && FinderKeys.command(flags)) ||
              (key == FinderKeys.c && FinderKeys.plainCopy(flags)) ||
              (key == FinderKeys.v && (FinderKeys.command(flags) || FinderKeys.explicitTransfer(flags))) else { return event }
        let initialCount = NSPasteboard.general.changeCount
        let context = keyContext(clipboardCount: initialCount)
        guard FinderKeys.route(key: key, flags: flags, context) != .pass, AXIsProcessTrusted() else { return event }
        let editing = editingText()
        // If Finder cannot identify focus, keep its native copy action available.
        guard editing != true, key != FinderKeys.c || editing == false else { return event }
        let count = NSPasteboard.general.changeCount
        let action = FinderKeys.route(key: key, flags: flags, keyContext(clipboardCount: count))
        switch action {
        case .pass:
            return event
        case .collect(let kind):
            return collect(kind, expecting: initialCount) ? nil : event
        case .waitForSelection:
            deferPaste(flags: flags, target: Self.finderPID)
            return nil
        default:
            return performPaste(action, flags: flags, clipboardCount: count, target: Self.finderPID) ? nil : event
        }
    }

    private func keyContext(clipboardCount: Int, waitForSelection: Bool = true) -> FinderKeyContext {
        locked {
            FinderKeyContext(cutPaste: cutPaste, copyAdds: copyAdds, pasteImages: pasteImages, finderFront: finderFront,
                             batchKind: batch.urls.isEmpty ? nil : batch.kind, clipboardUnchanged: batch.clipboardCount == clipboardCount,
                             collecting: waitForSelection && pendingSelections != 0, transferring: transferring, pastingImage: pastingImage)
        }
    }

    private func performPaste(_ action: FinderKeyAction, flags: CGEventFlags, clipboardCount: Int, target: pid_t) -> Bool {
        switch action {
        case .transfer(let kind):
            let expected: Int? = FinderKeys.explicitTransfer(flags) ? nil : clipboardCount
            return beginTransfer(kind, expectingClipboard: expected)
        case .pasteImage:
            guard locked({
                guard pasteImages, !pastingImage else { return false }
                pastingImage = true
                return true
            }) else { return false }
            pasteImage(into: target, expecting: clipboardCount)
            return true
        case .swallow:
            return true
        default:
            return false
        }
    }

    /// A paste pressed while Finder is answering a selection query runs after that selection is applied.
    private func deferPaste(flags: CGEventFlags, target: pid_t) {
        work.async {
            let editing = self.editingText() == true
            DispatchQueue.main.async {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target else { return }
                let count = NSPasteboard.general.changeCount
                var context = self.keyContext(clipboardCount: count, waitForSelection: false)
                context.editingText = editing
                let action = FinderKeys.route(key: FinderKeys.v, flags: flags, context)
                if !self.performPaste(action, flags: flags, clipboardCount: count, target: target) {
                    self.replay(FinderKeys.v, flags: flags, ifFront: target)
                }
            }
        }
    }

    private static var finderPID: pid_t { NSRunningApplication.runningApplications(withBundleIdentifier: finderID).first?.processIdentifier ?? 0 }

    /// Asks Finder itself, with a short timeout on Finder's element only: a timeout set on the system-wide
    /// element would become the default for every Accessibility question this app asks.
    private func editingText() -> Bool? {
        let pid = Self.finderPID
        guard pid != 0 else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
        if status == .noValue { return false }
        guard status == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String else { return nil }
        return FinderKeys.textRoles.contains(role)
    }

    // MARK: Collecting items

    private func collect(_ kind: FinderTransfer, expecting clipboardCount: Int) -> Bool {
        guard let token = locked({ () -> Int? in
            guard cutPaste, finderFront, !transferring, kind == .move || copyAdds else { return nil }
            pendingSelections += 1
            return generation
        }) else { return false }
        let target = Self.finderPID
        work.async {
            let urls = FinderBridge.selection()
            DispatchQueue.main.async {
                let board = NSPasteboard.general
                let updated = self.locked { () -> FinderFileBatch? in
                    guard self.generation == token else { return nil }
                    self.pendingSelections -= 1
                    guard !urls.isEmpty, self.cutPaste, kind == .move || self.copyAdds else { return nil }
                    let count = board.changeCount
                    let canWrite = count == clipboardCount || self.batch.clipboardCount == count
                    self.batch.collect(urls, as: kind, appending: kind == .copy || self.addToCut)
                    // A copy made while Finder was answering takes precedence.
                    self.batch.syncClipboard(board, expecting: canWrite ? count : nil)
                    return self.batch
                }
                if let updated {
                    self.dismiss?.cancel()
                    self.hud = CutHUDState(items: updated.urls.map { .init(url: $0) }, kind: updated.kind)
                    self.refreshPanel()
                    let verb = kind == .move ? "cut" : "copied"
                    AppModel.log("Finder: \(verb) \(urls.count) items, \(updated.urls.count) in the list")
                } else if kind == .copy, board.changeCount == clipboardCount, self.locked({ self.generation == token }) {
                    self.replay(FinderKeys.c, ifFront: target)
                }
            }
        }
        return true
    }

    func removeItem(_ url: URL) {
        guard let updated = locked({ () -> FinderFileBatch? in
            guard !transferring, batch.remove(url, from: .general) else { return nil }
            return batch
        }) else { return }
        dismiss?.cancel()
        hud = CutHUDState(items: updated.urls.map { .init(url: $0) }, kind: updated.kind)
        refreshPanel()
    }

    /// Clears the batch and, if requested, its clipboard while that clipboard is still current.
    func reset(clearClipboard: Bool = false) {
        let count: Int? = locked {
            let count = batch.clipboardCount
            generation += 1
            pendingSelections = 0
            batch = FinderFileBatch()
            transferring = false
            return count
        }
        if clearClipboard, let count, NSPasteboard.general.changeCount == count { NSPasteboard.general.clearContents() }
        guard hud != CutHUDState() else { return }
        dismiss?.cancel()
        hud = CutHUDState()
        refreshPanel()
    }

    // MARK: Moving or copying marked items

    func transferFromPanel(_ transfer: FinderTransfer) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderID else { return }
        _ = beginTransfer(transfer, fromPanel: true)
    }

    private func beginTransfer(_ transfer: FinderTransfer, expectingClipboard expected: Int? = nil, fromPanel: Bool = false) -> Bool {
        guard let operation = locked({ () -> (urls: [URL], token: Int)? in
            guard cutPaste, finderFront, !transferring, !batch.urls.isEmpty,
                  fromPanel ? pendingSelections == 0 && (transfer == .copy || batch.kind == .move) : transfer == batch.kind else { return nil }
            if let expected {
                guard batch.clipboardCount == expected, NSPasteboard.general.changeCount == expected else { return nil }
            }
            generation += 1
            pendingSelections = 0
            transferring = true
            return (batch.urls, generation)
        }) else { return false }
        let (urls, token) = operation
        publish(token, .init(transfer: transfer, total: urls.count))
        work.async {
            guard let folder = FinderBridge.insertionLocation() else {
                DispatchQueue.main.async { self.finishTransfer(token, transfer, count: 0, failed: urls.count, remaining: urls) }
                return
            }
            let fm = FileManager.default
            let folderVolume = Self.volume(folder)
            let trackBytes = transfer == .copy || urls.contains { url in
                guard let a = Self.volume(url), let b = folderVolume else { return false }
                return !a.isEqual(b)
            }
            let sizes: [Int64?] = urls.map { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true, let size = values?.fileSize else { return nil }
                return Int64(size)
            }
            let total = trackBytes && sizes.allSatisfy { $0 != nil } ? sizes.compactMap { $0 }.reduce(0, +) : 0
            let resolvedFolderPath = folder.resolvingSymlinksInPath().path
            var transferred = 0, failed = 0, finished: Int64 = 0
            var refused: [URL] = []
            for (index, source) in urls.enumerated() {
                self.publish(token, .init(transfer: transfer, done: index, total: urls.count, name: source.lastPathComponent,
                                          fraction: total > 0 ? Double(finished) / Double(total) : nil))
                var poll: DispatchSourceTimer?
                let sourcePath = source.resolvingSymlinksInPath().path
                if !fm.fileExists(atPath: source.path) {
                    failed += 1
                } else if transfer == .move && source.deletingLastPathComponent().resolvingSymlinksInPath().path == resolvedFolderPath {
                    transferred += 1
                } else if resolvedFolderPath == sourcePath || resolvedFolderPath.hasPrefix(sourcePath + "/") {
                    // A folder cannot be transferred into itself or one of its children.
                    failed += 1
                } else {
                    let name = FinderKeys.freeName(source.lastPathComponent) { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
                    let destination = folder.appendingPathComponent(name)
                    if total > 0 {
                        let base = finished
                        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                        timer.schedule(deadline: .now() + 0.3, repeating: 0.3)
                        timer.setEventHandler {
                            let size = ((try? fm.attributesOfItem(atPath: destination.path))?[.size] as? NSNumber)?.int64Value ?? 0
                            self.publish(token, .init(transfer: transfer, done: index, total: urls.count, name: source.lastPathComponent,
                                                      fraction: Double(min(base + size, total)) / Double(total)))
                        }
                        timer.resume()
                        poll = timer
                    }
                    do {
                        switch transfer {
                        case .move: try fm.moveItem(at: source, to: destination)
                        case .copy: try fm.copyItem(at: source, to: destination)
                        }
                        transferred += 1
                    } catch {
                        if transfer == .move && FinderKeys.needsFinder(error) { refused.append(source) }
                        else { failed += 1 }
                    }
                }
                poll?.cancel()
                finished += sizes[index] ?? 0
            }
            var remaining = transfer == .copy ? urls : []
            if !refused.isEmpty {
                let canceled = FinderBridge.move(refused, to: folder)
                let left = FinderKeys.remaining(refused, sourceGone: { url in
                    var info = stat()
                    return lstat(url.path, &info) != 0 && errno == ENOENT
                }, arrived: { fm.fileExists(atPath: folder.appendingPathComponent($0.lastPathComponent).path) })
                transferred += refused.count - left.count
                if canceled { remaining = left } else { failed += left.count }
            }
            DispatchQueue.main.async { self.finishTransfer(token, transfer, count: transferred, failed: failed, remaining: remaining) }
        }
        return true
    }

    private static func volume(_ url: URL) -> NSObjectProtocol? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObjectProtocol
    }

    private func publish(_ token: Int, _ progress: CutHUDState.Progress) {
        DispatchQueue.main.async {
            guard self.locked({ self.generation == token && self.transferring }) else { return }
            if let current = self.hud.progress, current.done > progress.done { return }
            self.dismiss?.cancel()
            self.hud.result = nil
            self.hud.progress = progress
            self.refreshPanel()
        }
    }

    private func finishTransfer(_ token: Int, _ transfer: FinderTransfer, count: Int, failed: Int, remaining: [URL]) {
        guard let kind = locked({ () -> FinderTransfer? in
            guard generation == token else { return nil }
            generation += 1
            transferring = false
            batch.finish(transfer, remaining: remaining, succeeded: count > 0)
            return batch.kind
        }) else { return }
        let verb = transfer == .move ? "moved" : "copied"
        AppModel.log("Finder: \(verb) \(count) items" + (failed > 0 ? ", \(failed) could not be \(verb)" : ""))
        let result = CutHUDState.Result(transfer: transfer, count: count, failed: failed)
        hud = CutHUDState(items: remaining.map { .init(url: $0) }, kind: kind, result: result)
        refreshPanel()
        dismiss?.cancel()
        let later = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hud.result = nil
            self.refreshPanel()
        }
        dismiss = later
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: later)
    }

    // MARK: Pasting an image as a file

    private enum ImagePaste { case notImage, saved, failed }

    private func pasteImage(into target: pid_t, expecting expected: Int) {
        pasteboard.async {
            let board = NSPasteboard.general
            guard board.changeCount == expected, let type = FinderKeys.imageType((board.types ?? []).map(\.rawValue)) else {
                DispatchQueue.main.async { self.finishImage(.notImage, target: target) }
                return
            }
            guard let data = board.data(forType: NSPasteboard.PasteboardType(type)), data.count <= FinderKeys.maxImageBytes,
                  let bitmap = NSBitmapImageRep(data: data),
                  let png = type == UTType.png.identifier ? data : bitmap.representation(using: .png, properties: [:]),
                  png.count <= FinderKeys.maxImageBytes else {
                DispatchQueue.main.async { self.finishImage(.failed, target: target) }
                return
            }
            self.work.async {
                guard let folder = FinderBridge.insertionLocation() else {
                    DispatchQueue.main.async { self.finishImage(.failed, target: target) }
                    return
                }
                let fm = FileManager.default
                let name = FinderKeys.freeName(FinderKeys.imageName(at: Date())) { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
                let saved = (try? png.write(to: folder.appendingPathComponent(name), options: .atomic)) != nil
                if saved { AppModel.log("Finder: pasted an image as \(name)") }
                DispatchQueue.main.async { self.finishImage(saved ? .saved : .failed, target: target) }
            }
        }
    }

    private func finishImage(_ result: ImagePaste, target: pid_t) {
        locked { pastingImage = false }
        switch result {
        case .saved: break
        case .failed: NSSound.beep()
        case .notImage: replay(FinderKeys.v, ifFront: target)
        }
    }

    /// Replays a key that Finder should handle itself.
    private func replay(_ key: Int64, flags: CGEventFlags = .maskCommand, ifFront target: pid_t) {
        guard target != 0, NSWorkspace.shared.frontmostApplication?.processIdentifier == target,
              let source = CGEventSource(stateID: .hidSystemState) else { return }
        source.userData = Self.replayMarker
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { up.post(tap: .cghidEventTap) }
    }

    // MARK: The floating panel

    private func updatePanelClipboardStatus() {
        let count = NSPasteboard.general.changeCount
        let current = locked { batch.clipboardCount == count }
        if hud.clipboardUnchanged != current { hud.clipboardUnchanged = current }
    }

    /// The file list shows in Finder. Transfer progress and results can show in any app.
    private func refreshPanel() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.refreshPanel() }; return }
        let (show, front) = locked { (showHUD, finderFront) }
        let showItems = show && front && !hud.items.isEmpty && hud.progress == nil && hud.result == nil
        if showItems {
            updatePanelClipboardStatus()
            if clipboardWatch == nil {
                let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.updatePanelClipboardStatus() }
                clipboardWatch = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        } else {
            clipboardWatch?.invalidate()
            clipboardWatch = nil
        }
        let visible = show && (hud.progress != nil || hud.result != nil || showItems)
        guard visible else { panel?.orderOut(nil); return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? NSSize(width: CutHUDView.width, height: 80)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - 14 - size.height, width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: CutHUDView.width, height: 80), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CutHUDView(shortcuts: self))
        return panel
    }
}

/// The file list and its transfer status.
struct CutHUDView: View {
    static let width: CGFloat = 286
    private let visibleRows = 5
    private let rowHeight: CGFloat = 22
    private let rowSpacing: CGFloat = 4
    @ObservedObject var shortcuts: FinderShortcuts
    var body: some View {
        let hud = shortcuts.hud
        VStack(alignment: .leading, spacing: 8) {
            if let result = hud.result {
                HStack(spacing: 8) {
                    Image(systemName: result.failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(result.failed > 0 ? Color.orange : Color.green)
                    VStack(alignment: .leading, spacing: 1) {
                        let verb = result.transfer == .move ? "moved" : "copied"
                        if result.count > 0 {
                            Text(result.count == 1 ? "1 item \(verb)" : "\(result.count) items \(verb)")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        if result.failed > 0 {
                            Text(result.failed == 1 ? "1 item couldn't be \(verb)" : "\(result.failed) items couldn't be \(verb)")
                                .font(.system(size: 11)).foregroundStyle(.orange)
                        }
                    }
                }
            } else if let progress = hud.progress {
                HStack(spacing: 8) {
                    Image(systemName: progress.transfer == .move ? "arrow.forward.circle" : "plus.circle").foregroundStyle(.blue)
                    Text(progress.transfer == .move ? "Moving…" : "Copying…").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let position = FinderKeys.position(progress.done, of: progress.total) { Text(position).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                if let fraction = progress.fraction { ProgressView(value: fraction).progressViewStyle(.linear) }
                else { ProgressView().progressViewStyle(.linear) }
                if !progress.name.isEmpty {
                    Text(progress.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: hud.kind == .move ? "scissors" : "document.on.document").foregroundStyle(.orange)
                    Text(hud.kind == .move ? "Cut" : "Copy").font(.system(size: 13, weight: .semibold))
                    Text("\(hud.items.count)").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                    Spacer()
                    Button { shortcuts.reset(clearClipboard: true) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Clear file list")
                }
                if hud.items.count > visibleRows {
                    ScrollView { fileRows(hud.items).padding(.trailing, 8) }
                        .frame(height: CGFloat(visibleRows) * rowHeight + CGFloat(visibleRows - 1) * rowSpacing)
                } else {
                    fileRows(hud.items)
                }
                HStack(spacing: 6) {
                    Button { shortcuts.transferFromPanel(hud.kind) } label: {
                        HStack(spacing: 5) {
                            Text(hud.kind == .move ? "Move \(hud.items.count) Here" : "Copy \(hud.items.count) Here")
                            Text(hud.clipboardUnchanged ? "⌘V" : FinderKeys.batchShortcut).foregroundStyle(.secondary)
                        }
                    }
                    if hud.kind == .move {
                        Button("Copy Here") { shortcuts.transferFromPanel(.copy) }
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func fileRows(_ items: [CutHUDState.Item]) -> some View {
        LazyVStack(spacing: rowSpacing) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 17, height: 17)
                    Text(item.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { shortcuts.removeItem(item.url) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: rowHeight, height: rowHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.name) from list")
                    .help("Remove from list")
                }
                .frame(height: rowHeight)
            }
        }
    }
}

/// Finder over Automation. macOS asks the user once, the first time.
enum FinderBridge {
    private static let queue = DispatchQueue(label: "Finder scripts")

    /// Whether this app may control Finder, asking the user if they have not decided yet.
    static func mayControlFinder() -> Bool {
        var target = AEAddressDesc()
        let created = FinderShortcuts.finderID.withCString { AECreateDesc(DescType(typeApplicationBundleID), $0, strlen($0), &target) }
        guard created == noErr else { return false }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), true) == noErr
    }

    /// Runs a script; nil on any error. `canceled` reports the user's Cancel (-128).
    private static func run(_ source: String, canceled: UnsafeMutablePointer<Bool>? = nil) -> NSAppleEventDescriptor? {
        queue.sync {
            guard mayControlFinder(), let script = NSAppleScript(source: source) else { return nil }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error {
                if (error[NSAppleScript.errorNumber] as? Int) == -128 { canceled?.pointee = true }
                return nil
            }
            return result
        }
    }

    static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Finder's selected items.
    static func selection() -> [URL] {
        let script = """
        tell application "Finder"
            set paths to {}
            repeat with f in (get selection)
                set end of paths to POSIX path of (f as alias)
            end repeat
            return paths
        end tell
        """
        guard let result = run(script), result.numberOfItems > 0 else { return [] }
        var urls: [URL] = []
        for index in 1...result.numberOfItems {
            guard let path = result.atIndex(index)?.stringValue, path.hasPrefix("/") else { return [] }
            urls.append(URL(fileURLWithPath: path))
        }
        return urls
    }

    /// The folder Finder would paste into.
    static func insertionLocation() -> URL? {
        guard let path = run("tell application \"Finder\" to return POSIX path of (insertion location as alias)")?.stringValue,
              path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Has Finder move items this app may not touch (Finder asks for a password if needed). True when canceled.
    static func move(_ items: [URL], to folder: URL) -> Bool {
        let targets = items.map { "POSIX file \(literal($0.path)) as alias" }.joined(separator: ", ")
        let script = """
        with timeout of 600 seconds
            tell application "Finder"
                set targets to {\(targets)}
                move targets to folder (POSIX file \(literal(folder.path)) as alias) without replacing
            end tell
        end timeout
        """
        var canceled = false
        _ = run(script, canceled: &canceled)
        return canceled
    }
}

private func finderTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let shortcuts = Unmanaged<FinderShortcuts>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { shortcuts.reenable(); return Unmanaged.passUnretained(event) }
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    return shortcuts.handle(event).map { Unmanaged.passUnretained($0) }
}
