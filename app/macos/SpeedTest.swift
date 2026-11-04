import SwiftUI

/// Internet speed test, the way Speediness does it: macOS's own `networkQuality` tool (Apple's test
/// servers) measures download and upload capacity, idle latency and responsiveness under load.
/// Runs only when asked, since a test fills the connection for about 20 seconds. The last 20 results
/// stay on this Mac, so a new one can be compared with what is usual on the same network.
final class SpeedTest: ObservableObject {
    static let shared = SpeedTest()
    struct Result: Codable, Equatable {
        var download: Double     // bits per second
        var upload: Double       // bits per second
        var responsiveness: Double?  // round-trips per minute under load
        var latency: Double?     // idle round-trip time, milliseconds
        var date: Date
        var network: String? = nil   // Wi-Fi name (or connection type) when measured
        /// Delay while the connection is busy, from responsiveness: one round trip takes 60,000 / RPM ms.
        var loadedLatency: Double? { responsiveness.flatMap { $0 > 0 ? 60_000 / $0 : nil } }
    }
    @Published private(set) var running = false
    @Published private(set) var history: [Result] = []   // newest first
    @Published private(set) var failure: String?
    /// The panel shows a fresh result (or failure) for a moment, then goes back to live traffic.
    @Published private(set) var showing = false
    static let showFor: TimeInterval = 20
    private var hideWork: DispatchWorkItem?
    var result: Result? { history.first }
    static let keep = 20
    private static let key = "speedTestHistory", oldKey = "speedTestResult"

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode([Result].self, from: data) {
            history = saved
        } else if let data = defaults.data(forKey: Self.oldKey), let single = try? JSONDecoder().decode(Result.self, from: data) {
            history = [single]
        }
    }

    func run(network: String?) {
        guard !running else { return }
        running = true; failure = nil; showing = false; hideWork?.cancel()
        DispatchQueue.global(qos: .utility).async {
            let outcome = Self.measure()
            DispatchQueue.main.async {
                self.running = false
                switch outcome {
                case .success(var result):
                    result.network = network
                    self.history = Array(([result] + self.history).prefix(Self.keep))
                    self.save()
                    AppModel.log("Speed test: ↓ \(Self.rate(result.download)) ↑ \(Self.rate(result.upload)) · \(Self.grade(result).label)")
                case .failure(let error):
                    self.failure = error.description
                    AppModel.log("Speed test failed: \(error.description)")
                }
                self.showBriefly()
            }
        }
    }
    private func showBriefly() {
        showing = true
        let work = DispatchWorkItem { [weak self] in self?.showing = false }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showFor, execute: work)
    }
    func clear() { history = []; failure = nil; save() }
    private func save() {
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: Self.key) }
        UserDefaults.standard.removeObject(forKey: Self.oldKey)
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

    // MARK: Is it fast?

    /// Our own scale, by what the connection is good for. Apple shows Low/Medium/High
    /// responsiveness but publishes no RPM cutoffs, so these are stated here instead.
    enum Grade: Int, Comparable, CaseIterable {
        case slow, fair, fast, veryFast
        static func < (a: Grade, b: Grade) -> Bool { a.rawValue < b.rawValue }
        var label: String { switch self { case .slow: "Slow"; case .fair: "Fair"; case .fast: "Fast"; case .veryFast: "Very fast" } }
        var color: Color { switch self { case .slow: .red; case .fair: .orange; case .fast: .green; case .veryFast: .mint } }
        var meaning: String {
            switch self {
            case .slow: "HD video may stall and calls may break up."
            case .fair: "HD video and a video call are fine; busy moments may stutter."
            case .fast: "4K video and group calls run smoothly."
            case .veryFast: "Room for 4K on several devices and big downloads at once."
            }
        }
    }
    /// Download: under 10 / 50 / 200 Mbps. Upload: under 3 / 10 / 50 Mbps. Delay while busy: over 150 / 50 / 20 ms.
    static func grade(download bps: Double) -> Grade { let m = bps / 1e6; return m < 10 ? .slow : m < 50 ? .fair : m < 200 ? .fast : .veryFast }
    static func grade(upload bps: Double) -> Grade { let m = bps / 1e6; return m < 3 ? .slow : m < 10 ? .fair : m < 50 ? .fast : .veryFast }
    static func grade(loadedLatency ms: Double) -> Grade { ms > 150 ? .slow : ms > 50 ? .fair : ms > 20 ? .fast : .veryFast }
    /// The connection is as good as its weakest part.
    static func grade(_ r: Result) -> Grade {
        [grade(download: r.download), grade(upload: r.upload), r.loadedLatency.map(grade(loadedLatency:))].compactMap { $0 }.min() ?? .fair
    }
    static let scale = "Slow, Fair, Fast below download 10 / 50 / 200 Mbps, upload 3 / 10 / 50 Mbps, or above a busy delay of 150 / 50 / 20 ms; otherwise Very fast."
    static let scaleRule = "The weakest of the three sets the grade."

    /// Download compared with earlier tests on the same network: "20% slower than usual". Needs two earlier results.
    func comparison(for result: Result) -> String? {
        guard let network = result.network else { return nil }
        let earlier = history.filter { $0 != result && $0.network == network }
        guard earlier.count >= 2 else { return nil }
        let usual = earlier.map(\.download).reduce(0, +) / Double(earlier.count)
        let change = (result.download - usual) / usual
        if abs(change) < 0.15 { return "About usual for this network" }
        return "\(Int((abs(change) * 100).rounded()))% \(change < 0 ? "slower" : "faster") than usual"
    }
    /// Average download, upload and idle latency per network, most used first.
    struct Usual { let network: String; let download: Double; let upload: Double; let count: Int }
    var usual: [Usual] {
        let groups = Dictionary(grouping: history.filter { $0.network != nil }, by: { $0.network ?? "" })
        let averages: [Usual] = groups.map { network, results in
            let n = Double(results.count)
            let down: Double = results.map(\.download).reduce(0, +) / n
            let up: Double = results.map(\.upload).reduce(0, +) / n
            return Usual(network: network, download: down, upload: up, count: results.count)
        }
        return averages.sorted { $0.count > $1.count }
    }
}
