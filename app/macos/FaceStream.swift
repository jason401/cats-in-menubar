import Cocoa

/// The CPU wheel as the AI Face board shows it: the round 240 x 240 LCD next to the Mac. Drawn here like the
/// menu bar wheel, only bigger and in fixed colors (the board has no menu bar appearance to follow).
enum WheelScene {
    static let size = 240
    static let frameBytes = size * size * 2
    /// Board pixels per wheel point: the teeth tips (9.75 pt from the hub) stay inside the round edge.
    static let scale: CGFloat = 11.5
    static let background = NSColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1)
    static let wheel = NSColor(srgbRed: 0.86, green: 0.86, blue: 0.88, alpha: 1)
    static let green = NSColor(srgbRed: 0.2, green: 0.82, blue: 0.36, alpha: 1)
    static let red = NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1)

    /// One picture as AI Face takes it: RGB565 little-endian, rows top to bottom, 115,200 bytes.
    static func frame(angle: Double, cell: Int, coat: Int, battery: WheelBattery) -> Data {
        rgb565(rgba(angle: angle, cell: cell, coat: coat, battery: battery))
    }
    /// The same picture as RGBA bytes, rows top to bottom.
    static func rgba(angle: Double, cell: Int, coat: Int, battery: WheelBattery) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            background.setFill(); NSRect(x: 0, y: 0, width: size, height: size).fill()
            // The hub in the middle of the screen.
            let transform = NSAffineTransform()
            transform.translateX(by: CGFloat(size) / 2, yBy: CGFloat(size) / 2); transform.scale(by: scale)
            transform.translateX(by: -TowerIcon.wheelCenter.x, yBy: -TowerIcon.wheelCenter.y); transform.concat()
            wheel.set()
            TowerIcon.drawWheel(angle: angle, battery: battery)
            switch battery.ink {
            case .template: break
            case .green: green.setFill(); TowerIcon.drawShare(level: battery.share)
            case .red: red.setFill(); TowerIcon.drawShare(level: battery.share)
            }
            WheelOverlayView.draw(cell: cell, coat: coat)
            NSGraphicsContext.restoreGraphicsState()
        }
        return pixels
    }
    /// Opaque RGBA (the background fills every pixel) to RGB565, low byte first.
    static func rgb565(_ rgba: [UInt8]) -> Data {
        var out = Data(count: rgba.count / 2)
        out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
            for i in 0..<rgba.count / 4 {
                let v = UInt16(rgba[i * 4] >> 3) << 11 | UInt16(rgba[i * 4 + 1] >> 2) << 5 | UInt16(rgba[i * 4 + 2] >> 3)
                dst[i * 2] = UInt8(v & 0xFF); dst[i * 2 + 1] = UInt8(v >> 8)
            }
        }
        return out
    }
}

/// Streams the wheel to the AI Face board through the AI Face app (its docs/STREAMING_API.md): pictures go
/// one at a time, the next only after AI Face says the board drew the last one. The board keeps its own
/// wheel angle and cell, so a slow USB line slows the board's wheel instead of making the teeth jump.
/// A swipe on the board (or another screen picked in AI Face) is the user's choice: the stream stays off
/// until the setting is switched off and on again. A missing AI Face, board or busy board is tried again.
final class FaceStream: ObservableObject {
    static let shared = FaceStream()
    static let app = "Cats in Menubar"
    /// Board pictures a second at most. With the motion capped to this, a frame turns the teeth 7.5° at most.
    static let maxFPS = 12.0
    /// Degrees the teeth may turn between two board pictures, under half the 30° between teeth, so they
    /// never seem to spin backwards even when the board shows fewer pictures than asked.
    static let maxTurn = 10.0
    /// Seconds AI Face keeps the board after our last request (a hung app loses it quickly).
    static let lease = 3
    static let retryDelay = 5.0
    static let discovery = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AI Face/controller.json")

    struct Input: Equatable { var gait: WheelPace.Gait; var motion: WheelPace.Motion; var coat: Int; var battery: WheelBattery }
    struct Endpoint: Equatable { var port: Int; var token: String }
    enum State: Equatable { case off, connecting, waiting(String), streaming, left }
    @Published private(set) var state = State.off { didSet { if state != oldValue { changed?() } } }
    /// Called when `state` changes (the menu bar hides its wheel while the board shows it).
    var changed: (() -> Void)?
    @Published private(set) var fps = 0.0

    /// The wheel to show now; nil while there is none.
    var source: (() -> Input?)?
    /// One request to AI Face: path, body, session, timeout; replies (HTTP status, JSON) on the main thread. 0 = no answer.
    typealias Transport = (_ endpoint: Endpoint, _ method: String, _ path: String, _ body: Data, _ session: String?, _ timeout: Double,
                           _ done: @escaping (Int, [String: Any]) -> Void) -> Void
    var transport: Transport = FaceStream.http
    var locate: () -> Endpoint? = FaceStream.readDiscovery
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    /// Schedules the next step; tests run steps by hand.
    var schedule: (Double, @escaping () -> Void) -> Timer? = { delay, work in
        let timer = Timer(timeInterval: max(0.001, delay), repeats: false) { _ in work() }
        RunLoop.main.add(timer, forMode: .common); return timer
    }

    private var left = false
    private var endpoint: Endpoint?
    private var session: String?
    private var timer: Timer?
    private var busy = false
    private var generation = 0   // bumped on every stop, so a late reply from before is dropped
    private var angle = 0.0, step = 0.0, gait = WheelPace.Gait.rest, last = 0.0
    private var sent: Data?
    private var answered = 0.0   // when AI Face last renewed our lease
    private var counted = 0, countedSince = 0.0
    private(set) var framesSent = 0

    /// `enabled`: the setting. `available`: the wheel is on and the Mac awake. Safe to call often.
    func update(enabled: Bool, available: Bool) {
        if !enabled { left = false }
        if enabled && available && !left {
            if state == .off { connect() }
            return
        }
        stop()
        let rest: State = left ? .left : .off
        if state != rest { state = rest }
    }

    private func connect() {
        timer?.invalidate(); timer = nil
        if state == .off { state = .connecting }
        if endpoint == nil { endpoint = locate() }
        guard let endpoint else { retry("AI Face isn't running."); return }
        let body = (try? JSONSerialization.data(withJSONObject: ["app": Self.app, "lease": Self.lease])) ?? Data()
        let ticket = generation
        busy = true
        transport(endpoint, "POST", "stream/start", body, nil, 10) { [weak self] code, reply in
            guard let self, ticket == self.generation else { return }
            self.busy = false
            guard code == 200, let session = reply["session"] as? String else { self.failed(code, reply); return }
            self.session = session; self.sent = nil
            self.answered = self.clock(); self.last = self.answered
            self.counted = 0; self.countedSince = self.answered; self.fps = 0
            self.state = .streaming
            AppModel.log("AI Face: streaming the wheel")
            self.pump()
        }
    }

    /// Why AI Face said no, and when to ask again.
    private func failed(_ code: Int, _ reply: [String: Any]) {
        session = nil
        switch code {
        case 0: endpoint = nil; retry("AI Face isn't running.")
        case 403: endpoint = nil; retry("AI Face restarted.", after: 1)
        case 409: retry("\(reply["busy_by"] as? String ?? "Another app") is using the board.")
        case 503: retry("AI Face is installing an update.")
        default: retry(reply["message"] as? String ?? "AI Face can't stream now.")
        }
    }
    private func retry(_ why: String, after delay: Double = FaceStream.retryDelay) {
        state = .waiting(why)
        timer?.invalidate()
        timer = schedule(delay) { [weak self] in self?.connect() }
    }

    /// One board picture: the next cell and teeth angle, sent when it differs from the last one.
    func pump() {
        timer?.invalidate(); timer = nil
        guard state == .streaming, !busy, let endpoint, let session else { return }
        guard let input = source?() else { return }
        let started = clock(), dt = min(0.25, max(0, started - last)); last = started
        if input.gait != gait { gait = input.gait; step = 0 } else { step += dt * input.motion.frameRate }
        angle = (angle - min(Self.maxTurn, dt * input.motion.degreesPerSecond)).truncatingRemainder(dividingBy: 360)
        let picture = WheelScene.frame(angle: angle, cell: WheelOverlayView.cell(gait, step: Int(step), coat: input.coat),
                                       coat: input.coat, battery: input.battery)
        // A resting wheel looks again four times a second (a new cat, the battery) and renews the lease every second.
        let interval = input.motion.frameRate > 0 ? 1 / min(Self.maxFPS, input.motion.frameRate) : 0.25
        let same = picture == sent
        if same && started - answered < 1 { timer = schedule(interval) { [weak self] in self?.pump() }; return }
        let ticket = generation
        busy = true
        transport(endpoint, "POST", same ? "stream/keepalive" : "stream/frame", same ? Data() : picture, session, 5) { [weak self] code, reply in
            guard let self, ticket == self.generation else { return }
            self.busy = false
            guard code == 200 else {
                // 400 leaves a running stream alone when `streaming` still says so.
                if code == 400, reply["streaming"] as? Bool == true { self.timer = self.schedule(1) { [weak self] in self?.pump() }; return }
                self.failed(code, reply); return
            }
            let now = self.clock()
            guard reply["streaming"] as? Bool == true else { self.ended(lapsed: now - self.answered > Double(Self.lease) - 0.5); return }
            self.answered = now
            if !same {
                self.sent = (reply["lost"] as? Bool == true) ? nil : picture
                self.framesSent += 1; self.counted += 1
                if now - self.countedSince >= 1 { self.fps = Double(self.counted) / (now - self.countedSince); self.counted = 0; self.countedSince = now }
            }
            self.timer = self.schedule(max(0, interval - (now - started))) { [weak self] in self?.pump() }
        }
    }

    /// The board left our stream. Our own lease running out (a stalled Mac) or an unplugged board comes back
    /// by itself; a swipe or another screen stays as the user left it.
    private func ended(lapsed: Bool) {
        session = nil; sent = nil
        guard !lapsed, let endpoint else { connect(); return }
        let ticket = generation
        transport(endpoint, "GET", "stream/info", Data(), nil, 5) { [weak self] code, info in
            guard let self, ticket == self.generation else { return }
            if code == 200, info["board"] as? Bool == false { self.retry("Connect the AI Face board."); return }
            self.left = true; self.state = .left
            AppModel.log("AI Face: the board left the stream")
        }
    }

    /// Gives the board back to AI Face (its last screen returns at once instead of after the lease).
    func stop() {
        generation += 1
        timer?.invalidate(); timer = nil
        busy = false; sent = nil
        if fps != 0 { fps = 0 }
        if let endpoint, let session { transport(endpoint, "POST", "stream/stop", Data(), session, 2) { _, _ in } }
        session = nil
    }
    /// At quit: stop and wait a moment for AI Face to take the board back.
    func stopNow() {
        guard let endpoint, let session else { return }
        generation += 1
        let done = DispatchSemaphore(value: 0)
        Self.send(endpoint, "POST", "stream/stop", Data(), session, 0.5) { _, _ in done.signal() }
        _ = done.wait(timeout: .now() + 0.6)
        self.session = nil
    }

    // MARK: AI Face's local server

    /// Port and token AI Face writes each time it starts; nil while it is not running.
    static func readDiscovery() -> Endpoint? {
        guard let data = try? Data(contentsOf: discovery), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = json["port"] as? Int, let token = json["token"] as? String, (1...65535).contains(port) else { return nil }
        if let pid = json["pid"] as? Int32, kill(pid, 0) != 0, errno == ESRCH { return nil }   // left behind by a crash
        return Endpoint(port: port, token: token)
    }
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]   // never through a proxy: 127.0.0.1 only
        return URLSession(configuration: configuration)
    }()
    /// The request itself; `done` runs on URLSession's queue.
    private static func send(_ endpoint: Endpoint, _ method: String, _ path: String, _ body: Data, _ stream: String?, _ timeout: Double,
                             _ done: @escaping (Int, [String: Any]) -> Void) {
        // "127.0.0.1:<port>" is also the Host header, which AI Face checks.
        guard let url = URL(string: "http://127.0.0.1:\(endpoint.port)/\(path)") else { done(0, [:]); return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue(endpoint.token, forHTTPHeaderField: "X-ESP-Token")
        if let stream { request.setValue(stream, forHTTPHeaderField: "X-Stream-Session") }
        if method == "POST" {
            request.setValue(path == "stream/start" ? "application/json" : "application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        session.dataTask(with: request) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            done(code, reply)
        }.resume()
    }
    static func http(_ endpoint: Endpoint, _ method: String, _ path: String, _ body: Data, _ stream: String?, _ timeout: Double,
                     _ done: @escaping (Int, [String: Any]) -> Void) {
        send(endpoint, method, path, body, stream, timeout) { code, reply in DispatchQueue.main.async { done(code, reply) } }
    }

    /// The line under the switch in Settings → Monitor.
    var note: String {
        switch state {
        case .off: return "Shows the wheel cat on the AI Face board instead of the menu bar. Needs the AI Face app with a board that has the streaming firmware."
        case .connecting: return "Connecting to AI Face…"
        case .waiting(let why): return "\(why) Trying again…"
        case .streaming: return fps > 0 ? String(format: "On the AI Face board · %.0f fps. The menu bar shows only the tower.", fps) : "On the AI Face board. The menu bar shows only the tower."
        case .left: return "The board went back to its own screen. Switch this off and on to show the wheel again."
        }
    }
}
