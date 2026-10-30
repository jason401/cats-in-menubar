import Cocoa
import IOKit
import IOKit.hid

// Scroll reversing, per scrolling source, the way Scroll Reverser 2 does it
// (https://github.com/pilotmoon/Scroll-Reverser, Apache License 2.0; the event tap, source
// identification and reversing rule follow its MouseTap, ScrollSource and SourceTable).
// An event tap sees every scroll event before apps do, attributes it to a device or app,
// and flips the sign of its deltas when that source's setting asks for it.

// MARK: Private APIs (the same four Scroll Reverser declares in IOKitSPI.h / CoreGraphicsSPI.h)
@_silgen_name("CGEventCopyIOHIDEvent") private func CGEventCopyIOHIDEvent(_ event: CGEvent) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetSenderID") private func IOHIDEventGetSenderID(_ event: CFTypeRef) -> UInt64
@_silgen_name("IOHIDEventGetFloatValue") private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: UInt32) -> Double
@_silgen_name("IOHIDEventSetFloatValue") private func IOHIDEventSetFloatValue(_ event: CFTypeRef, _ field: UInt32, _ value: Double)
private let hidScrollX: UInt32 = 6 << 16, hidScrollY: UInt32 = 6 << 16 | 1

// MARK: Sources and settings

enum ScrollMode: Int, Codable, CaseIterable {
    case natural, classic, unchanged, reversed, matchVertical
    var label: String {
        switch self {
        case .natural: "Natural"; case .classic: "Classic"; case .unchanged: "Unchanged"
        case .reversed: "Reversed"; case .matchVertical: "Match vertical"
        }
    }
    /// Whether this mode flips an event; `natural` says whether macOS already made it natural.
    func reverses(natural: Bool) -> Bool {
        self == .reversed || (self == .natural && !natural) || (self == .classic && natural)
    }
}

/// One row of settings: a device (trackpad or mouse), an app that posts scroll events, or an unknown source.
/// Continuous (trackpad, Magic Mouse) and discrete (wheel) scrolling from the same source are separate rows.
struct ScrollSourceRow: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case device, remote, app, unidentified }
    enum Category: String, Codable { case trackpad, mouse, other }
    var key: String
    var kind: Kind
    var category: Category
    var name: String?
    var continuous: Bool
    var vertical: ScrollMode
    var horizontal: ScrollMode = .matchVertical
    var stepEnabled = true
    var stepSize = 3
    var lastUsed = Date()
    var id: String { key }
    /// Devices say which way macOS already scrolls them; apps and unknown sources do not.
    var hasDeviceDirection: Bool { kind == .device || kind == .remote }

    init(key: String, kind: Kind, category: Category, name: String?, continuous: Bool) {
        self.key = key; self.kind = kind; self.category = category; self.name = name; self.continuous = continuous
        // Same defaults as Scroll Reverser: trackpads natural, other devices classic, apps unchanged.
        vertical = !(kind == .device || kind == .remote) ? .unchanged : category == .trackpad ? .natural : .classic
    }
    var title: String {
        switch kind {
        case .device, .remote: (name ?? (category == .trackpad ? "Trackpad" : "Mouse")) + (kind == .remote ? " (Universal Control)" : "")
        case .app: name ?? "Unknown app"
        case .unidentified: "Unidentified"
        }
    }
    var subtitle: String {
        let type = switch category { case .trackpad: "Trackpad"; case .mouse: "Mouse"; case .other: kind == .app ? "App" : "Other" }
        return type + (continuous ? " · smooth scrolling" : " · scroll wheel")
    }
    struct Adjustment: Equatable { var reverseVertical: Bool; var reverseHorizontal: Bool; var stepSize: Int }
    func adjustment(natural: Bool) -> Adjustment {
        let vertical = self.vertical.reverses(natural: natural)
        return Adjustment(reverseVertical: vertical,
                          reverseHorizontal: horizontal == .matchVertical ? vertical : horizontal.reverses(natural: natural),
                          stepSize: continuous || !stepEnabled ? 0 : min(max(stepSize, 1), 30))
    }
}

/// Changes one scroll event in place: flips the signs a row asks for and applies a wheel step size.
/// Point and fixed-point deltas are set after the line delta, since setting the line delta makes
/// macOS recompute them (smooth scrolling would be lost otherwise).
func applyScrollAdjustment(_ adjustment: ScrollSourceRow.Adjustment, to event: CGEvent, hid: CFTypeRef?) {
    let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1), axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let point1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), point2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
    let fixed1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), fixed2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
    let hid1 = hid.map { IOHIDEventGetFloatValue($0, hidScrollY) } ?? 0, hid2 = hid.map { IOHIDEventGetFloatValue($0, hidScrollX) } ?? 0
    // A wheel click (one line) becomes `stepSize` lines, so each click scrolls a fixed amount.
    let vDiscrete = adjustment.stepSize > 0 && abs(axis1) == 1, hDiscrete = adjustment.stepSize > 0 && abs(axis2) == 1
    let vStep = Int64(vDiscrete ? adjustment.stepSize : 1), hStep = Int64(hDiscrete ? adjustment.stepSize : 1)
    let vMul = adjustment.reverseVertical ? -vStep : vStep, hMul = adjustment.reverseHorizontal ? -hStep : hStep
    if vDiscrete || vMul != 1 { event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: axis1 * vMul) }
    if !vDiscrete && vMul != 1 {
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed1 * Double(vMul))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: point1 * vMul)
        if let hid { IOHIDEventSetFloatValue(hid, hidScrollY, hid1 * Double(vMul)) }
    }
    if hDiscrete || hMul != 1 { event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: axis2 * hMul) }
    if !hDiscrete && hMul != 1 {
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed2 * Double(hMul))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: point2 * hMul)
        if let hid { IOHIDEventSetFloatValue(hid, hidScrollX, hid2 * Double(hMul)) }
    }
}

// MARK: Identifying where a scroll event came from

private func escaped(_ field: String) -> String {
    field.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "|", with: "%7C").replacingOccurrences(of: "#", with: "%23")
}

/// What identifies a scrolling device; the sender ID is not part of it (it changes on every reconnect).
private let identityKeys = [kIOHIDProductKey, kIOHIDTransportKey, kIOHIDVendorIDKey, kIOHIDProductIDKey, kIOHIDSerialNumberKey, "HIDScrollAccelerationType"]

struct ScrollSourceInfo: Equatable {
    var key: String; var kind: ScrollSourceRow.Kind; var category: ScrollSourceRow.Category; var name: String?
}

func deviceSource(kind: ScrollSourceRow.Kind, properties: [String: Any], trackpadDriver: Bool) -> ScrollSourceInfo {
    let product = (properties[kIOHIDProductKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let transport = (properties[kIOHIDTransportKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let vendor = properties[kIOHIDVendorIDKey] as? NSNumber, productID = properties[kIOHIDProductIDKey] as? NSNumber
    var parts = [kind == .device ? "device" : "remote", transport.map(escaped) ?? "", vendor?.stringValue ?? "", productID?.stringValue ?? ""]
    if let serial = (properties[kIOHIDSerialNumberKey] as? String).flatMap({ $0.isEmpty ? nil : $0 }) {
        parts.append("sn:" + escaped(serial))
    } else if (vendor?.intValue ?? 0) == 0 && (productID?.intValue ?? 0) == 0 {
        parts.append(product.map(escaped) ?? "")   // such as the built-in trackpad, which has a fixed name
    }
    let trackpad = trackpadDriver || (properties["HIDScrollAccelerationType"] as? String) == "HIDTrackpadScrollAcceleration"
    return ScrollSourceInfo(key: parts.joined(separator: "|"), kind: kind, category: trackpad ? .trackpad : .mouse, name: product)
}

/// Runs only on the tap thread. Results are cached per sender and per process.
private final class ScrollSourceIdentifier {
    private var senders: [UInt64: ScrollSourceInfo] = [:]
    private var retryAt: [UInt64: UInt64] = [:]
    private var pids: [pid_t: ScrollSourceInfo] = [:]
    private lazy var hidClient = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private let unidentifiedDevice = ScrollSourceInfo(key: "unidentified-device", kind: .unidentified, category: .other, name: nil)
    private let unknownApp = ScrollSourceInfo(key: "unknown-app", kind: .app, category: .other, name: nil)
    private let unidentified = ScrollSourceInfo(key: "unidentified", kind: .unidentified, category: .other, name: nil)

    func source(hid: CFTypeRef?, pid: pid_t) -> ScrollSourceInfo {
        if let hid {
            let sender = IOHIDEventGetSenderID(hid)
            return sender == 0 ? unidentifiedDevice : source(sender: sender)
        }
        return pid != 0 ? source(pid: pid) : unidentified
    }
    /// Registry IDs are not reused within a boot. A brand-new virtual device may send before it is
    /// listed, so an unidentified sender is looked up again at most every 250 ms.
    private func source(sender: UInt64) -> ScrollSourceInfo {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        if let known = senders[sender], known != unidentifiedDevice || now < retryAt[sender, default: 0] { return known }
        let found = localDevice(sender) ?? remoteDevice(sender)
        if found == nil { retryAt[sender] = now + 250_000_000 } else { retryAt[sender] = nil }
        senders[sender] = found ?? unidentifiedDevice
        return found ?? unidentifiedDevice
    }
    private func localDevice(_ sender: UInt64) -> ScrollSourceInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(sender))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: [String: Any] = [:]
        for key in identityKeys {
            properties[key] = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        // A trackpad whose node lacks the scroll acceleration type: the multitouch driver's
        // AppleMultitouchDevice child sends the events, so check the parent's class too.
        var trackpadDriver = IOObjectConformsTo(service, "AppleMultitouchTrackpadHIDEventDriver") != 0
        var parent: io_registry_entry_t = 0
        if !trackpadDriver, IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
            trackpadDriver = IOObjectConformsTo(parent, "AppleMultitouchTrackpadHIDEventDriver") != 0
            IOObjectRelease(parent)
        }
        return deviceSource(kind: .device, properties: properties, trackpadDriver: trackpadDriver)
    }
    /// Universal Control's mirrored devices live only in the HID event system, not the registry.
    private func remoteDevice(_ sender: UInt64) -> ScrollSourceInfo? {
        guard let services = IOHIDEventSystemClientCopyServices(hidClient) as? [IOHIDServiceClient] else { return nil }
        for service in services where (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value == sender {
            var properties: [String: Any] = [:]
            for key in identityKeys { properties[key] = IOHIDServiceClientCopyProperty(service, key as CFString) }
            return deviceSource(kind: .remote, properties: properties, trackpadDriver: false)
        }
        return nil
    }
    /// Apps by bundle ID (or executable path), never by pid, which changes on every launch.
    private func source(pid: pid_t) -> ScrollSourceInfo {
        if let known = pids[pid] { return known }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return unknownApp }
        let id = app.bundleIdentifier ?? app.executableURL?.path ?? "pid"
        let info = ScrollSourceInfo(key: "app|" + escaped(id), kind: .app, category: .other, name: app.localizedName)
        pids[pid] = info
        return info
    }
}

// MARK: The event tap

/// Runs the tap on its own thread, so cat drawing never delays scrolling.
final class ScrollReverser: ObservableObject {
    static let shared = ScrollReverser()
    static let scrollReverserID = "com.pilotmoon.scroll-reverser"
    /// Rows the user sees, most recently used first. Main thread only.
    @Published private(set) var rows: [ScrollSourceRow] = []
    @Published private(set) var running = false
    @Published private(set) var otherAppRunning = false
    private let lock = NSLock()
    private var table: [String: ScrollSourceRow] = [:]   // guarded by lock; shared with the tap thread
    private var tapPort: CFMachPort?
    private var tapLoop: CFRunLoop?
    private var thread: Thread?
    private var identifier = ScrollSourceIdentifier()
    private var saveScheduled = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Pref.scrollSources),
           let saved = try? JSONDecoder().decode([ScrollSourceRow].self, from: data) {
            for row in saved { table[row.key] = row }
        }
        rows = sortedRows()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appsChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appsChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    /// Starts or stops the tap from the setting. It stays off while Scroll Reverser itself runs,
    /// since two reversers would flip each event twice.
    func apply() {
        otherAppRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.scrollReverserID).isEmpty
        let wanted = UserDefaults.standard.bool(forKey: Pref.scrollReverse) && !otherAppRunning && MenuBarMonitor.trusted
        if wanted && thread == nil { start() } else if !wanted && thread != nil { stop() }
    }
    @objc private func appsChanged() { DispatchQueue.main.async { self.apply() } }

    private func start() {
        let thread = Thread { [weak self] in self?.runTap() }
        thread.name = "Scroll reverser"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }
    private func stop() {
        lock.lock(); let loop = tapLoop; lock.unlock()
        if let loop { CFRunLoopStop(loop) }
        thread = nil
        running = false
        AppModel.log("Scroll reverser stopped")
    }
    private func runTap() {
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: scrollTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            AppModel.log("Scroll reverser could not start its event tap (Accessibility needed)")
            DispatchQueue.main.async { self.thread = nil; self.running = false }
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        lock.lock(); tapPort = port; tapLoop = CFRunLoopGetCurrent(); lock.unlock()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        DispatchQueue.main.async { self.running = true }
        AppModel.log("Scroll reverser started")
        CFRunLoopRun()
        CFMachPortInvalidate(port)
        lock.lock(); tapPort = nil; tapLoop = nil; lock.unlock()
    }
    fileprivate func reenable() { lock.lock(); if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }; lock.unlock() }

    /// The tap's work for one event, on the tap thread.
    fileprivate func handle(_ event: CGEvent) {
        let natural = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let hid = CGEventCopyIOHIDEvent(event)?.takeRetainedValue()
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        let info = identifier.source(hid: hid, pid: pid)
        let row = record(info, continuous: continuous)
        applyScrollAdjustment(row.adjustment(natural: natural), to: event, hid: hid)
    }

    private func record(_ info: ScrollSourceInfo, continuous: Bool) -> ScrollSourceRow {
        let key = info.key + (continuous ? "#continuous" : "#discrete")
        lock.lock()
        var row = table[key] ?? ScrollSourceRow(key: key, kind: info.kind, category: info.category, name: info.name, continuous: continuous)
        let isNew = table[key] == nil
        // Remember use about once a minute, which is enough for ordering and costs nothing per event.
        let stale = Date().timeIntervalSince(row.lastUsed) > 60
        if isNew || stale { row.lastUsed = Date(); if info.name != nil { row.name = info.name }; table[key] = row }
        lock.unlock()
        if isNew || stale { scheduleSave() }
        return row
    }

    // MARK: Settings, main thread

    func update(_ row: ScrollSourceRow) {
        lock.lock(); table[row.key] = row; lock.unlock()
        rows = sortedRows()
        scheduleSave()
    }
    func forget(_ key: String) {
        lock.lock(); table[key] = nil; lock.unlock()
        rows = sortedRows()
        scheduleSave()
    }
    private func sortedRows() -> [ScrollSourceRow] {
        lock.lock(); defer { lock.unlock() }
        return table.values.sorted { $0.lastUsed > $1.lastUsed }
    }
    private func scheduleSave() {
        DispatchQueue.main.async {
            guard !self.saveScheduled else { return }
            self.saveScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.saveScheduled = false
                let rows = self.sortedRows()
                self.rows = rows
                if let data = try? JSONEncoder().encode(rows) { UserDefaults.standard.set(data, forKey: Pref.scrollSources) }
            }
        }
    }
}

private func scrollTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let reverser = Unmanaged<ScrollReverser>.fromOpaque(userInfo).takeUnretainedValue()
    // macOS switches a slow or interrupted tap off; switch it straight back on.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { reverser.reenable(); return Unmanaged.passUnretained(event) }
    if type == .scrollWheel { reverser.handle(event) }
    return Unmanaged.passUnretained(event)
}
