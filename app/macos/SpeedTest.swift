import Foundation

/// Internet speed test, the way Speediness does it: macOS's own `networkQuality` tool (Apple's test
/// servers) measures download and upload capacity, idle latency and responsiveness under load.
/// Runs only when asked, since a test fills the connection for about 20 seconds.
final class SpeedTest: ObservableObject {
    static let shared = SpeedTest()
    struct Result: Codable, Equatable {
        var download: Double     // bits per second
        var upload: Double       // bits per second
        var responsiveness: Double?  // round-trips per minute under load
        var latency: Double?     // idle round-trip time, milliseconds
        var date: Date
    }
    @Published private(set) var running = false
    @Published private(set) var result: Result?
    @Published private(set) var failure: String?
    private static let key = "speedTestResult"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) { result = try? JSONDecoder().decode(Result.self, from: data) }
    }

    func run() {
        guard !running else { return }
        running = true; failure = nil
        DispatchQueue.global(qos: .utility).async {
            let outcome = Self.measure()
            DispatchQueue.main.async {
                self.running = false
                switch outcome {
                case .success(let result):
                    self.result = result
                    if let data = try? JSONEncoder().encode(result) { UserDefaults.standard.set(data, forKey: Self.key) }
                    AppModel.log("Speed test: ↓ \(Self.rate(result.download)) ↑ \(Self.rate(result.upload))")
                case .failure(let error):
                    self.failure = error.description
                    AppModel.log("Speed test failed: \(error.description)")
                }
            }
        }
    }

    struct Failure: Error, CustomStringConvertible { let description: String }

    private static func measure() -> Swift.Result<Result, Failure> {
        let process = Process(), out = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        process.arguments = ["-c"]   // JSON on standard output
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(Failure(description: "networkQuality is not available")) }
        // A stuck test is stopped after a minute.
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        guard process.terminationStatus == 0 else { return .failure(Failure(description: "No connection, or the test was stopped")) }
        guard let result = parse(data, date: Date()) else { return .failure(Failure(description: "Unexpected test output")) }
        return .success(result)
    }

    /// Reads `networkQuality -c` output: dl_throughput and ul_throughput in bits per second,
    /// responsiveness in RPM, base_rtt in milliseconds.
    static func parse(_ data: Data, date: Date) -> Result? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let down = (json["dl_throughput"] as? NSNumber)?.doubleValue,
              let up = (json["ul_throughput"] as? NSNumber)?.doubleValue else { return nil }
        return Result(download: down, upload: up, responsiveness: (json["responsiveness"] as? NSNumber)?.doubleValue,
                      latency: (json["base_rtt"] as? NSNumber)?.doubleValue, date: date)
    }

    static func rate(_ bitsPerSecond: Double) -> String {
        let mbps = bitsPerSecond / 1_000_000
        return mbps >= 100 ? "\(Int(mbps.rounded())) Mbps" : String(format: "%.1f Mbps", mbps)
    }
}
