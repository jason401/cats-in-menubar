import Foundation
import IOKit.ps
import SystemConfiguration

// Local system readings from public macOS APIs. Nothing is sent anywhere and no permission is needed.
struct SystemStats {
    var cpuUser = 0.0, cpuSystem = 0.0, cpuIdle = 1.0
    var cpu: Double { cpuUser + cpuSystem }
    var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var memoryApp = 0.0, memoryWired = 0.0, memoryCompressed = 0.0, memoryPressure = 0.0
    var memoryUsed: Double { memoryApp + memoryWired + memoryCompressed }
    var diskTotal = 0.0, diskFree = 0.0
    var diskUsed: Double { max(0, diskTotal - diskFree) }
    var hasBattery = false, batteryLevel = 0.0, charging = false, onAC = true
    var networkName = "—", localIP = "—"
    var upload = 0.0, download = 0.0          // bytes per second
    var thermal = ProcessInfo.ThermalState.nominal
}

final class SystemMonitor: ObservableObject {
    @Published private(set) var stats = SystemStats()
    @Published private(set) var cpuHistory: [Double] = []
    var updated: ((SystemStats) -> Void)?
    private var timer: Timer?
    private var lastTicks: [UInt32]?
    private var lastBytes: [String: (UInt32, UInt32)] = [:]
    private var lastSample = Date()
    private var namedInterface: String?? = .none

    func start(interval: Double) {
        timer?.invalidate()
        sample()
        let timer = Timer(timeInterval: max(0.5, interval), repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func sample() {
        var next = stats
        let now = Date()
        let elapsed = max(0.1, now.timeIntervalSince(lastSample))
        lastSample = now
        readCPU(into: &next)
        readMemory(into: &next)
        readDisk(into: &next)
        readBattery(into: &next)
        readNetwork(into: &next, elapsed: elapsed)
        next.thermal = ProcessInfo.processInfo.thermalState
        stats = next
        cpuHistory.append(next.cpu)
        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
        updated?(next)
    }

    private func readCPU(into stats: inout SystemStats) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]  // user, system, idle, nice
        defer { lastTicks = ticks }
        guard let last = lastTicks else { return }
        let delta = zip(ticks, last).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return }
        stats.cpuUser = (delta[0] + delta[3]) / total
        stats.cpuSystem = delta[1] / total
        stats.cpuIdle = delta[2] / total
    }

    private func readMemory(into stats: inout SystemStats) {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Double(vm_kernel_page_size)
        stats.memoryApp = Double(vm.internal_page_count > vm.purgeable_count ? vm.internal_page_count - vm.purgeable_count : 0) * page
        stats.memoryWired = Double(vm.wire_count) * page
        stats.memoryCompressed = Double(vm.compressor_page_count) * page
        // The kernel reports how much memory is still comfortably available; pressure is the rest.
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 { stats.memoryPressure = Double(100 - level) / 100 }
    }

    private func readDisk(into stats: inout SystemStats) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        stats.diskTotal = Double(values.volumeTotalCapacity ?? 0)
        stats.diskFree = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    private func readBattery(into stats: inout SystemStats) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        stats.hasBattery = false
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Double ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Double ?? 100
            stats.hasBattery = true
            stats.batteryLevel = maximum > 0 ? current / maximum : 0
            stats.charging = description[kIOPSIsChargingKey] as? Bool ?? false
            stats.onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        }
    }

    private func readNetwork(into stats: inout SystemStats, elapsed: Double) {
        let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let primary = global?["PrimaryInterface"] as? String
        var bytes: [String: (UInt32, UInt32)] = [:]
        var address: String?
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return }
        defer { freeifaddrs(pointer) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let item = entry.pointee
            let name = String(cString: item.ifa_name)
            guard let addr = item.ifa_addr, !name.hasPrefix("lo") else { continue }
            if addr.pointee.sa_family == UInt8(AF_LINK), let data = item.ifa_data?.assumingMemoryBound(to: if_data.self) {
                bytes[name] = (data.pointee.ifi_ibytes, data.pointee.ifi_obytes)
            } else if addr.pointee.sa_family == UInt8(AF_INET), name == primary {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: host)
                }
            }
        }
        // Interface counters are 32-bit and wrap, so differences use wrapping subtraction.
        var down = 0.0, up = 0.0
        for (name, value) in bytes {
            guard let last = lastBytes[name] else { continue }
            down += Double(value.0 &- last.0); up += Double(value.1 &- last.1)
        }
        if !lastBytes.isEmpty { stats.download = down / elapsed; stats.upload = up / elapsed }
        lastBytes = bytes
        stats.localIP = address ?? "—"
        // The display name only changes with the interface, so look it up once per interface.
        if primary != namedInterface {
            namedInterface = primary
            if let primary, let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface],
               let match = interfaces.first(where: { SCNetworkInterfaceGetBSDName($0) as String? == primary }) {
                stats.networkName = SCNetworkInterfaceGetLocalizedDisplayName(match) as String? ?? primary
            } else { stats.networkName = primary ?? "Offline" }
        }
    }
}
