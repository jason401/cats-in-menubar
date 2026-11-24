import Foundation
import IOKit

/// How busy the GPU is, as shares from 0 to 1. Renderer and tiler are the two halves of Apple's GPU
/// pipeline; not every GPU reports them.
struct GPULoad: Equatable {
    var device: Double
    var renderer: Double?
    var tiler: Double?
}

/// GPU load and power draw from read-only IOKit lookups: the GPU driver's own statistics and the
/// System Management Controller's power sensor. Neither needs a permission, and nothing is written.
enum Sensors {
    /// The busiest GPU's load, or nil when no GPU reports statistics (a virtual machine, for one).
    static func gpu() -> GPULoad? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var busiest: GPULoad?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any], let load = gpuLoad(from: stats) else { continue }
            if load.device > busiest?.device ?? -1 { busiest = load }
        }
        return busiest
    }

    /// Reads the driver's percentages; the device share is required, the other two are optional.
    static func gpuLoad(from stats: [String: Any]) -> GPULoad? {
        func share(_ key: String) -> Double? {
            guard let value = (stats[key] as? NSNumber)?.doubleValue, value.isFinite else { return nil }
            return min(1, max(0, value / 100))
        }
        guard let device = share("Device Utilization %") else { return nil }
        return GPULoad(device: device, renderer: share("Renderer Utilization %"), tiler: share("Tiler Utilization %"))
    }

    /// The whole Mac's power use in watts. The SMC's system power sensor (PSTR) updates about once a
    /// second; a MacBook's battery gauge reports a slower estimate, used only if the SMC has no reading.
    static func power() -> Double? {
        plausibleWatts(SMC.shared.float("PSTR").map(Double.init)) ?? plausibleWatts(batterySystemLoad())
    }

    /// Readings outside 0–500 W are a sensor that is missing or not ready, not real use.
    static func plausibleWatts(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value < 500 else { return nil }
        return value
    }

    private static func batterySystemLoad() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let telemetry = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        return telemetry.flatMap(systemLoadWatts)
    }

    /// The battery gauge reports the system's load in milliwatts.
    static func systemLoadWatts(_ telemetry: [String: Any]) -> Double? {
        (telemetry["SystemLoad"] as? NSNumber).map { $0.doubleValue / 1000 }
    }
}

/// A read-only connection to the System Management Controller, kept open for the app's lifetime.
/// Only four-byte float keys are read, which is how Apple silicon reports its power sensors.
final class SMC {
    static let shared = SMC()

    /// The SMC's request and reply share this C struct layout (80 bytes).
    struct Message {
        var key: UInt32 = 0
        var version: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
        var limits: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
        var size: UInt32 = 0, type: UInt32 = 0, attributes: UInt8 = 0
        var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)       // the C struct pads its key info to 12 bytes
        var result: UInt8 = 0, status: UInt8 = 0, command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }
    static let readKey: UInt8 = 5, readKeyInfo: UInt8 = 9
    static let floatType = code("flt ")

    private var connection: io_connect_t = 0
    private var opened = false

    static func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    /// Decodes a reply's value when it is a four-byte float, stored little-endian.
    static func float(type: UInt32, size: UInt32, bytes: (UInt64, UInt64, UInt64, UInt64)) -> Float? {
        guard type == floatType, size == 4 else { return nil }
        var bytes = bytes
        return withUnsafeBytes(of: &bytes) { $0.load(as: Float.self) }
    }

    func float(_ key: String) -> Float? {
        guard open() else { return nil }
        var request = Message(); request.key = Self.code(key); request.command = Self.readKeyInfo
        guard let info = call(&request) else { return nil }
        request = Message(); request.key = Self.code(key); request.size = info.size; request.command = Self.readKey
        guard let reply = call(&request) else { return nil }
        return Self.float(type: info.type, size: info.size, bytes: reply.bytes)
    }

    private func open() -> Bool {
        if opened { return connection != 0 }
        opened = true
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
        return connection != 0
    }

    private func call(_ request: inout Message) -> Message? {
        var reply = Message()
        var size = MemoryLayout<Message>.stride
        let result = IOConnectCallStructMethod(connection, 2, &request, MemoryLayout<Message>.stride, &reply, &size)
        return result == kIOReturnSuccess && reply.result == 0 ? reply : nil
    }
}
