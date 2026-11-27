import Cocoa
import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

// Finder shortcuts, both off by default (Settings > Accessibility). They work as Vorssaint's do, written anew:
// - Cut and paste: ⌘X in Finder marks the selected items (and copies them, so other apps can still paste
//   them), and ⌘V in another folder moves them there. More ⌘X add to the cut, from any folder, unless
//   "Add to cut items" is off (then each ⌘X starts over, as in Vorssaint). This app moves the files itself; items it may not
//   touch are handed to Finder, which asks for a password if needed. A floating panel shows what is cut.
// - Paste images as files: ⌘V in a Finder folder while the clipboard holds an image (and no files) saves
//   it there as a PNG.
// Finder is asked for its selection and its current folder over Automation (asked for once, the first
// time). Text fields (renaming, search) always get the keys unchanged. Needs Accessibility, like the cats.

/// What the tap does with one key press. A pure decision, so it can be tested without a keyboard.
enum FinderKeyAction: Equatable {
    case pass            // leave the key alone
    case cut             // swallow ⌘X and mark Finder's selection
    case move            // swallow ⌘V and move the marked items here
    case swallow         // swallow ⌘V while a move is still running
    case pasteImage      // swallow ⌘V and paste the clipboard's image as a file (or replay ⌘V if it holds none)
}

struct FinderKeyContext: Equatable {
    var cutPaste = false, pasteImages = false
    var finderFront = false, editingText = false
    var marked = false                  // items are cut
    var clipboardUnchanged = false      // the clipboard is still the one the cut wrote
    var moving = false, pastingImage = false
}

enum FinderKeys {
    static let x: Int64 = 7, c: Int64 = 8, v: Int64 = 9

    /// ⌘ held, without ⌃ or ⌥ (those are other commands, such as Finder's own ⌥⌘V). ⇧ may be held.
    static func command(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand) && flags.intersection([.maskControl, .maskAlternate]).isEmpty
    }

    /// The action, and whether the cut is dropped first (⌘C, or ⌘V once something else was copied).
    static func route(key: Int64, flags: CGEventFlags, _ k: FinderKeyContext) -> (action: FinderKeyAction, forgetCut: Bool) {
        guard [x, c, v].contains(key), command(flags), k.finderFront, !k.editingText else { return (.pass, false) }
        switch key {
        case x: return (k.cutPaste ? .cut : .pass, false)
        case c: return (.pass, k.cutPaste && k.marked)
        default:
            var forget = false
            if k.cutPaste && k.marked {
                if k.clipboardUnchanged { return (k.moving ? .swallow : .move, false) }
                forget = true
            }
            if k.pasteImages && !flags.contains(.maskShift) && !k.pastingImage { return (.pasteImage, forget) }
            return (.pass, forget)
        }
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

/// What the floating panel shows.
struct CutHUDState: Equatable {
    struct Item: Equatable, Identifiable { let url: URL; var id: URL { url }; var name: String { url.lastPathComponent } }
    struct Progress: Equatable { var done = 0, total = 0; var name = ""; var fraction: Double? }
    struct Result: Equatable { var moved = 0, failed = 0 }
    var items: [Item] = []
    var progress: Progress?
    var result: Result?
}

/// The tap runs on its own thread, like scroll direction, so a busy main thread never delays typing.
/// Finder and file work runs on background queues; the panel on the main thread.
final class FinderShortcuts: ObservableObject {
    static let shared = FinderShortcuts()
    static let finderID = "com.apple.finder"
    /// Marks the ⌘V this app replays, so the tap lets it through.
    static let replayMarker: Int64 = 0x4361_7473   // "Cats"
    @Published private(set) var running = false
    @Published private(set) var hud = CutHUDState()

    private let lock = NSLock()
    // Guarded by lock; shared with the tap thread.
    private var cutPaste = false, pasteImages = false, showHUD = true, addToCut = true, finderFront = false
    private var marks: [URL] = []
    private var markedCount = 0          // the clipboard the cut wrote
    private var moving = false, pastingImage = false
    private var generation = 0           // bumped by every cut, move and reset; late answers of older ones are dropped
    private var tapPort: CFMachPort?
    private var tapLoop: CFRunLoop?
    private var thread: Thread?

    private let work = DispatchQueue(label: "Finder shortcuts", qos: .userInitiated)
    private let pasteboard = DispatchQueue(label: "Finder shortcuts clipboard", qos: .utility)
    private var panel: NSPanel?
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
        let (wanted, cutOn): (Bool, Bool) = locked {
            cutPaste = defaults.bool(forKey: Pref.finderCutPaste)
            pasteImages = defaults.bool(forKey: Pref.finderPasteImages)
            showHUD = defaults.object(forKey: Pref.finderCutPasteHUD) as? Bool ?? true
            addToCut = defaults.object(forKey: Pref.finderCutAdds) as? Bool ?? true
            return ((cutPaste || pasteImages) && MenuBarMonitor.trusted, cutPaste)
        }
        if !cutOn { reset() }
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
        guard [FinderKeys.x, FinderKeys.c, FinderKeys.v].contains(key), FinderKeys.command(event.flags) else { return event }
        let count = NSPasteboard.general.changeCount
        var context: FinderKeyContext = locked {
            FinderKeyContext(cutPaste: cutPaste, pasteImages: pasteImages, finderFront: finderFront, marked: !marks.isEmpty,
                             clipboardUnchanged: !marks.isEmpty && markedCount == count, moving: moving, pastingImage: pastingImage)
        }
        guard context.finderFront, AXIsProcessTrusted() else { return event }
        // Only ask for focus when the key might change: the lookup goes to Finder over Accessibility.
        let first = FinderKeys.route(key: key, flags: event.flags, context)
        guard first.action != .pass || first.forgetCut else { return event }
        context.editingText = editingText()
        let (action, forget) = FinderKeys.route(key: key, flags: event.flags, context)
        if forget { DispatchQueue.main.async { self.reset() } }
        switch action {
        case .pass:
            return event
        case .swallow:
            return nil
        case .cut:
            cut()
            return nil
        case .move:
            locked { moving = true }
            move()
            return nil
        case .pasteImage:
            locked { pastingImage = true }
            pasteImage(into: Self.finderPID, expecting: count)
            return nil
        }
    }

    private static var finderPID: pid_t { NSRunningApplication.runningApplications(withBundleIdentifier: finderID).first?.processIdentifier ?? 0 }

    /// Asks Finder itself, with a short timeout on Finder's element only: a timeout set on the system-wide
    /// element would become the default for every Accessibility question this app asks.
    private func editingText() -> Bool {
        let pid = Self.finderPID
        guard pid != 0 else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role) == .success else { return false }
        return FinderKeys.textRoles.contains(role as? String ?? "")
    }

    // MARK: Cut

    private func cut() {
        let token: Int = locked { generation += 1; return generation }
        work.async {
            let urls = FinderBridge.selection()
            DispatchQueue.main.async {
                guard self.locked({ self.generation }) == token else { return }
                let board = NSPasteboard.general
                // With "Add to cut items" a cut still on the clipboard grows; otherwise a new cut replaces it.
                let earlier: [URL] = self.locked { self.addToCut && !self.marks.isEmpty && self.markedCount == board.changeCount ? self.marks : [] }
                guard !urls.isEmpty else { if earlier.isEmpty { self.reset() }; return }
                let items = FinderKeys.merge(earlier, adding: urls)
                board.clearContents()
                board.writeObjects(items as [NSURL])
                self.locked { self.marks = items; self.markedCount = board.changeCount; self.moving = false }
                self.dismiss?.cancel()
                self.hud = CutHUDState(items: items.map { .init(url: $0) })
                self.refreshPanel()
                AppModel.log("Finder: cut \(urls.count) items" + (earlier.isEmpty ? "" : ", \(items.count) in all"))
            }
        }
    }

    /// Drops the cut. `clearClipboard` also empties the clipboard the cut wrote, if it is still current.
    func reset(clearClipboard: Bool = false) {
        let (hadMarks, count): (Bool, Int) = locked {
            let had = !marks.isEmpty, count = markedCount
            generation += 1; marks = []; moving = false; markedCount = 0
            return (had, count)
        }
        if clearClipboard && hadMarks && NSPasteboard.general.changeCount == count { NSPasteboard.general.clearContents() }
        guard hud != CutHUDState() else { return }
        dismiss?.cancel()
        hud = CutHUDState()
        refreshPanel()
    }

    // MARK: Move

    private func move() {
        let (urls, token): ([URL], Int) = locked { generation += 1; return (marks, generation) }
        work.async {
            guard let folder = FinderBridge.insertionLocation() else {
                DispatchQueue.main.async { self.finishMove(token, moved: 0, failed: urls.count, stillCut: []) }
                return
            }
            let fm = FileManager.default
            let folderVolume = Self.volume(folder)
            let crossVolume = urls.contains { url in
                guard let a = Self.volume(url), let b = folderVolume else { return false }
                return !a.isEqual(b)
            }
            var sizes: [Int64] = []
            var allFiles = true
            for url in urls {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values?.isRegularFile != true { allFiles = false }
                sizes.append(Int64(values?.fileSize ?? 0))
            }
            let total: Int64 = allFiles ? sizes.reduce(0, +) : 0
            var moved = 0, failed = 0, finished: Int64 = 0
            var refused: [URL] = []
            for (index, source) in urls.enumerated() {
                if crossVolume {
                    self.publish(token, .init(done: index, total: urls.count, name: source.lastPathComponent,
                                              fraction: total > 0 ? Double(finished) / Double(total) : nil))
                }
                var poll: DispatchSourceTimer?
                if source.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path {
                    moved += 1
                } else if !fm.fileExists(atPath: source.path) {
                    failed += 1
                } else {
                    let name = FinderKeys.freeName(source.lastPathComponent) { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
                    let destination = folder.appendingPathComponent(name)
                    if crossVolume && total > 0 {
                        let base = finished
                        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                        timer.schedule(deadline: .now() + 0.3, repeating: 0.3)
                        timer.setEventHandler {
                            let size = ((try? fm.attributesOfItem(atPath: destination.path))?[.size] as? NSNumber)?.int64Value ?? 0
                            self.publish(token, .init(done: index, total: urls.count, name: source.lastPathComponent,
                                                      fraction: Double(min(base + size, total)) / Double(total)))
                        }
                        timer.resume()
                        poll = timer
                    }
                    do { try fm.moveItem(at: source, to: destination); moved += 1 }
                    catch { if FinderKeys.needsFinder(error) { refused.append(source) } else { failed += 1 } }
                }
                poll?.cancel()
                finished += sizes[index]
            }
            var stillCut: [URL] = []
            if !refused.isEmpty {
                let canceled = FinderBridge.move(refused, to: folder)
                let left = FinderKeys.remaining(refused, sourceGone: { url in
                    var info = stat()
                    return lstat(url.path, &info) != 0 && errno == ENOENT
                }, arrived: { fm.fileExists(atPath: folder.appendingPathComponent($0.lastPathComponent).path) })
                moved += refused.count - left.count
                if canceled { stillCut = left } else { failed += left.count }
            }
            DispatchQueue.main.async { self.finishMove(token, moved: moved, failed: failed, stillCut: stillCut) }
        }
    }

    private static func volume(_ url: URL) -> NSObjectProtocol? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObjectProtocol
    }

    private func publish(_ token: Int, _ progress: CutHUDState.Progress) {
        DispatchQueue.main.async {
            guard self.locked({ self.generation == token && self.moving }) else { return }
            self.hud.progress = progress
            self.refreshPanel()
        }
    }

    private func finishMove(_ token: Int, moved: Int, failed: Int, stillCut: [URL]) {
        guard locked({ generation }) == token else { return }
        locked {
            generation += 1; moving = false
            marks = stillCut
            if stillCut.isEmpty { markedCount = 0 }
        }
        AppModel.log("Finder: moved \(moved) items" + (failed > 0 ? ", \(failed) could not be moved" : ""))
        let result: CutHUDState.Result? = moved == 0 && failed == 0 ? nil : .init(moved: moved, failed: failed)
        hud = CutHUDState(items: stillCut.map { .init(url: $0) }, progress: nil, result: result)
        refreshPanel()
        guard result != nil else { return }
        let later = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hud.result = nil
            self.refreshPanel()
        }
        dismiss?.cancel()
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
        case .notImage: replayPaste(ifFront: target)
        }
    }

    /// Finder's own ⌘V, when the clipboard held no image. Marked, so the tap lets it through.
    private func replayPaste(ifFront target: pid_t) {
        guard target != 0, NSWorkspace.shared.frontmostApplication?.processIdentifier == target else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = Self.replayMarker
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(FinderKeys.v), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(FinderKeys.v), keyDown: false) else { return }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { up.post(tap: .cghidEventTap) }
    }

    // MARK: The floating panel

    /// Shown while items are cut and Finder is in front; a move's progress and result show anywhere.
    private func refreshPanel() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.refreshPanel() }; return }
        let (show, front) = locked { (showHUD, finderFront) }
        let visible = show && (hud.progress != nil || hud.result != nil || (!hud.items.isEmpty && front))
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

/// The panel's look: what is cut, a move under way, or how it went.
struct CutHUDView: View {
    static let width: CGFloat = 286
    @ObservedObject var shortcuts: FinderShortcuts
    var body: some View {
        let hud = shortcuts.hud
        VStack(alignment: .leading, spacing: 8) {
            if let result = hud.result {
                HStack(spacing: 8) {
                    Image(systemName: result.failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(result.failed > 0 ? Color.orange : Color.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Moved!").font(.system(size: 13, weight: .semibold))
                        Text(result.moved == 1 ? "1 item moved" : "\(result.moved) items moved").font(.system(size: 11)).foregroundStyle(.secondary)
                        if result.failed > 0 { Text("Some items couldn't be moved").font(.system(size: 11)).foregroundStyle(.orange) }
                    }
                }
            } else if let progress = hud.progress {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.forward.circle").foregroundStyle(.blue)
                    Text("Moving…").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let position = FinderKeys.position(progress.done, of: progress.total) { Text(position).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                if let fraction = progress.fraction { ProgressView(value: fraction).progressViewStyle(.linear) }
                else { ProgressView().progressViewStyle(.linear) }
                Text(progress.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "scissors").foregroundStyle(.orange)
                    Text("Cut").font(.system(size: 13, weight: .semibold))
                    Text("\(hud.items.count)").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                    Spacer()
                    Button { shortcuts.reset(clearClipboard: true) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Cancel cut")
                }
                ForEach(hud.items.prefix(5)) { item in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 17, height: 17)
                        Text(item.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    }
                }
                if hud.items.count > 5 { Text("+\(hud.items.count - 5)").font(.system(size: 11)).foregroundStyle(.secondary) }
                HStack(spacing: 4) {
                    Text("⌘V").font(.system(size: 10, weight: .semibold, design: .rounded)).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5)))
                    Text("in the destination folder to move").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
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
    static func run(_ source: String, canceled: UnsafeMutablePointer<Bool>? = nil) -> String? {
        queue.sync {
            guard mayControlFinder(), let script = NSAppleScript(source: source) else { return nil }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error {
                if (error[NSAppleScript.errorNumber] as? Int) == -128 { canceled?.pointee = true }
                return nil
            }
            return result.stringValue ?? ""
        }
    }

    static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Finder's selected items.
    static func selection() -> [URL] {
        let script = """
        tell application "Finder"
            set out to ""
            repeat with f in (get selection)
                set out to out & POSIX path of (f as alias) & linefeed
            end repeat
            return out
        end tell
        """
        return (run(script) ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    /// The folder Finder would paste into.
    static func insertionLocation() -> URL? {
        guard let path = run("tell application \"Finder\" to return POSIX path of (insertion location as alias)")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
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
