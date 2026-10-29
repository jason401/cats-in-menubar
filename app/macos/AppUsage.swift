import AppKit
import CoreLocation
import CoreWLAN
import Darwin

/// One app in a top list: CPU as a share of the whole Mac (like the CPU total), memory in bytes.
struct AppUsage: Equatable {
    var name: String
    var value: Double
}

/// Ranks apps by recent CPU and current memory. Helper processes (web content, renderers, XPC services)
/// count toward the app responsible for them, as in Activity Monitor. Only processes of this user can be
/// read without privileges; system daemons are left out, and the CPU total's System share covers them.
final class AppUsageSampler {
    static let window = 60.0
    private typealias Responsible = @convention(c) (pid_t) -> pid_t
    private static let responsible: Responsible? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: Responsible.self) }
    private static let tick: Double = {
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        return Double(base.numer) / Double(base.denom) / 1e9
    }()
    private static let cores = Double(ProcessInfo.processInfo.activeProcessorCount)

    private var lastCPU: [pid_t: UInt64] = [:]
    private var names: [pid_t: String] = [:]
    private var history: [(time: Date, span: Double, cpu: [String: Double])] = []
    private var lastSample: Date?

    /// Reads every readable process once; about a millisecond for a few hundred processes.
    func sample(now: Date = Date()) -> (cpu: [AppUsage], memory: [AppUsage]) {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return ([], []) }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var cpu: [String: Double] = [:], memory: [String: Double] = [:], seen: [pid_t: UInt64] = [:]
        for pid in pids.prefix(Int(max(0, filled))) where pid > 0 {
            var info = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard ok == 0 else { continue }
            let name = appName(pid)
            let time = info.ri_user_time + info.ri_system_time
            seen[pid] = time
            if let last = lastCPU[pid], time >= last { cpu[name, default: 0] += Double(time - last) * Self.tick }
            memory[name, default: 0] += Double(info.ri_phys_footprint)
        }
        lastCPU = seen
        names = names.filter { seen[$0.key] != nil }
        if let lastSample { history.append((now, now.timeIntervalSince(lastSample), cpu)) }
        lastSample = now
        history.removeAll { now.timeIntervalSince($0.time) > Self.window }
        let span = history.reduce(0) { $0 + $1.span }
        var total: [String: Double] = [:]
        for entry in history { for (name, seconds) in entry.cpu { total[name, default: 0] += seconds } }
        let topCPU = span > 0 ? total.map { AppUsage(name: $0.key, value: $0.value / span / Self.cores) } : []
        return (Self.top(topCPU), Self.top(memory.map { AppUsage(name: $0.key, value: $0.value) }))
    }

    private static func top(_ list: [AppUsage]) -> [AppUsage] {
        Array(list.sorted { $0.value > $1.value || ($0.value == $1.value && $0.name < $1.name) }.prefix(3))
    }

    /// The app a process works for: its responsible process's app name, else the outermost .app in its
    /// path, else the process name.
    private func appName(_ pid: pid_t) -> String {
        if let name = names[pid] { return name }
        let owner = Self.responsible?(pid) ?? pid
        let id = owner > 0 ? owner : pid
        var name = NSRunningApplication(processIdentifier: id)?.localizedName
        if name == nil {
            var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            if proc_pidpath(id, &buffer, UInt32(buffer.count)) > 0,
               let app = String(cString: buffer).components(separatedBy: "/").first(where: { $0.hasSuffix(".app") }) {
                name = String(app.dropLast(4))
            }
        }
        if name == nil {
            var buffer = [CChar](repeating: 0, count: 256)
            if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 { name = String(cString: buffer) }
        }
        let result = name ?? "pid \(pid)"
        names[pid] = result
        return result
    }
}

/// The connected Wi-Fi network. The name needs Location Services (macOS rule since Sonoma); without it
/// everything else still shows.
struct WiFiInfo: Equatable {
    var name: String?
    var security: String
    var secure: Bool
    var rssi: Int
    var band: String
    var rate: Double

    var signal: String {
        switch rssi {
        case -55...0: "Excellent"
        case -67 ..< -55: "Good"
        case -75 ..< -67: "Fair"
        default: "Weak"
        }
    }

    static func read() -> WiFiInfo? {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn(), interface.rssiValue() != 0 else { return nil }
        let (security, secure) = describe(interface.security())
        let band: String
        switch interface.wlanChannel()?.channelBand {
        case .band2GHz: band = "2.4 GHz"
        case .band5GHz: band = "5 GHz"
        case .band6GHz: band = "6 GHz"
        default: band = "—"
        }
        return WiFiInfo(name: interface.ssid(), security: security, secure: secure, rssi: interface.rssiValue(), band: band, rate: interface.transmitRate())
    }

    private static func describe(_ security: CWSecurity) -> (String, Bool) {
        switch security {
        case .none: ("Open (no password)", false)
        case .WEP, .dynamicWEP: ("WEP (outdated)", false)
        case .wpaPersonal, .wpaPersonalMixed: ("WPA Personal", true)
        case .wpa2Personal, .personal: ("WPA2 Personal", true)
        case .wpa3Personal: ("WPA3 Personal", true)
        case .wpa3Transition: ("WPA2/WPA3 Personal", true)
        case .wpaEnterprise, .wpaEnterpriseMixed: ("WPA Enterprise", true)
        case .wpa2Enterprise, .enterprise: ("WPA2 Enterprise", true)
        case .wpa3Enterprise: ("WPA3 Enterprise", true)
        case .OWE, .oweTransition: ("Enhanced Open", true)
        default: ("Unknown", true)
        }
    }
}

/// Asks for Location Services once, only so the Wi-Fi name can be shown. The location itself is never read.
final class WiFiNamePermission: NSObject, CLLocationManagerDelegate {
    static let shared = WiFiNamePermission()
    private let manager = CLLocationManager()
    var changed: (() -> Void)?
    override init() { super.init(); manager.delegate = self }
    func askIfNeeded() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { changed?() }
}
