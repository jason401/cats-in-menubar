import Cocoa
import Darwin
import ServiceManagement

// stable is the deployment channel (same scheme as AI Illuminati). Only the app-owned checkout in
// Application Support is ever changed; developer folders are never read or updated by the app.
// Each Mac tests and builds with its own local signing identity.
final class Updater: ObservableObject {
    static let shared = Updater()
    // Only checks run on their own; installing always waits for the button.
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "autoUpdate") }
    }
    @Published private(set) var checking = false
    @Published private(set) var status = ""
    @Published private(set) var available: String?
    /// True while the user is dragging a cat; installation waits until it ends.
    var isBusy: () -> Bool = { false }

    static let every: TimeInterval = 3 * 3600, retry: TimeInterval = 600, first: TimeInterval = 60
    static let repository = "https://github.com/jason401/cats-in-menubar.git"
    static let channel = "stable"
    static let bundleID = "local.catsinmenubar"
    static let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cats in Menubar")
    static let target = URL(fileURLWithPath: "/Applications/Cats in Menubar.app")
    let root = Updater.support.appendingPathComponent("source")
    var revision: String { Bundle.main.object(forInfoDictionaryKey: "CatsSourceRevision") as? String ?? "" }
    /// Only the copy in /Applications updates itself. A development build runs as it is.
    var installed: Bool { Bundle.main.bundleURL.standardizedFileURL == Self.target.standardizedFileURL }
    private var installing = false
    private var updates: URL { Self.support.appendingPathComponent("updates") }
    private var staged: URL { root.appendingPathComponent("build/Cats in Menubar.app") }
    private var stateFile: URL { Self.support.appendingPathComponent("update.json") }
    private let work = DispatchQueue(label: "updater")
    private var timer: Timer?

    private init() {
        enabled = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
        let state = loadState()
        status = Self.describe(state)
        if state["status"] == "available", let next = state["next"], next != revision { available = next }
    }

    func start() {
        acknowledgeInstallation()
        guard installed else {
            status = "Development copy: updates run only in /Applications."
            return
        }
        schedule(after: Self.first) { if $0.enabled { $0.check() } }
        timer = Timer.scheduledTimer(withTimeInterval: Self.every, repeats: true) { [weak self] _ in
            guard let self, self.enabled else { return }
            self.check()
        }
    }

    private func schedule(after seconds: TimeInterval, _ step: @escaping (Updater) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if let self { step(self) }
        }
    }

    /// Looks for a new version on the stable channel. Changes nothing on this Mac's app.
    func check() {
        guard installed, !checking, !installing else { return }
        checking = true
        report(["status": "checking"], save: false)
        work.async {
            defer { DispatchQueue.main.async { self.checking = false } }
            do {
                try self.withSource { _, new in
                    self.report(["status": "available", "current": self.revision, "next": new])
                    self.setAvailable(new)
                }
            } catch {
                self.report(["status": "failed", "current": self.revision, "detail": String(describing: error)])
            }
        }
    }

    /// Runs only after the user asks: tests, builds and installs the stable version.
    func install() {
        guard installed, !checking, !installing else { return }
        if isBusy() {
            report(["status": "waiting", "current": revision])
            return schedule(after: Self.retry) { $0.install() }
        }
        checking = true
        report(["status": "checking"], save: false)
        work.async {
            defer { DispatchQueue.main.async { self.checking = false } }
            do {
                try self.withSource { old, new in
                    // A build made earlier for this version is reused.
                    let ready = (try? self.git("rev-parse", "HEAD")) == new
                        && (NSDictionary(contentsOf: self.staged.appendingPathComponent("Contents/Info.plist"))?["CatsSourceRevision"] as? String) == new
                    if !ready {
                        do {
                            try self.git("merge", "--ff-only", "-q", new)
                            self.report(["status": "building", "current": self.revision, "next": new], save: false)
                            // test.sh builds the app into build/ and runs the full self-test.
                            defer { self.dropCompilerCache() }
                            try self.shell(["zsh", "tools/test.sh"], timeout: 30 * 60, step: "build and test")
                        } catch {
                            // Only this private, clean checkout can be reset; never a developer folder.
                            _ = try? self.git("reset", "-q", "--hard", old)
                            throw error
                        }
                    }
                    self.handoff(staged: self.staged, next: new)
                }
            } catch {
                self.report(["status": "failed", "current": self.revision, "detail": String(describing: error)])
            }
        }
    }

    /// One-time move of a development build into /Applications, asked for explicitly (`--install-self`).
    func installSelf() {
        guard !installed else { return }
        handoff(staged: Bundle.main.bundleURL, next: revision)
    }

    /// The Swift module cache (about 280 MB of prebuilt Apple frameworks) is only reused by the next
    /// build, hours away; dropping it keeps the update folder small at the cost of a slower build.
    private func dropCompilerCache() {
        try? FileManager.default.removeItem(at: root.appendingPathComponent("build/module-cache"))
    }

    private func setAvailable(_ next: String?) {
        DispatchQueue.main.async { if self.available != next { self.available = next } }
    }

    // MARK: Steps

    /// Holds the source lock, fetches stable and calls `body(old, new)` only when stable is newer
    /// than the running app. Other outcomes are reported here.
    private func withSource(_ body: (String, String) throws -> Void) throws {
        try FileManager.default.createDirectory(at: Self.support, withIntermediateDirectories: true)
        let lockFD = open(Self.support.appendingPathComponent("source.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw Failure(description: "Cannot open update lock") }
        defer { close(lockFD) }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { return report(["status": "postponed"]) }
        defer { flock(lockFD, LOCK_UN) }
        guard root.resolvingSymlinksInPath().path == root.path else {
            throw Failure(description: "Update source must not be a symbolic link")
        }
        // The checkout keeps all commits (for the ancestry checks below) but only the file contents it
        // actually checks out, so old artwork in the history is never downloaded. An older full clone
        // is only a cache of this app, and is replaced once.
        if FileManager.default.fileExists(atPath: root.path),
           (try? git("config", "--get", "remote.origin.partialclonefilter")) != "blob:none" {
            try FileManager.default.removeItem(at: root)
        }
        if !FileManager.default.fileExists(atPath: root.path) {
            let temporary = Self.support.appendingPathComponent("source-clone-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary) }
            _ = try execute(["/usr/bin/git", "clone", "--filter=blob:none", "--branch", Self.channel, "--single-branch", Self.repository, temporary.path],
                            timeout: 180, step: "clone", directory: Self.support)
            try FileManager.default.moveItem(at: temporary, to: root)
        }
        guard try git("remote", "get-url", "origin") == Self.repository else {
            throw Failure(description: "Unexpected update repository")
        }
        guard try git("status", "--porcelain", "--untracked-files=normal").isEmpty else {
            return report(["status": "local-changes"])
        }
        try git("fetch", "-q", "origin", Self.channel, timeout: 90)
        let old = try git("rev-parse", "HEAD"), new = try git("rev-parse", "origin/" + Self.channel)
        // Compare against the running app, not only the checkout (a failed build may leave the checkout newer).
        if revision == new {
            setAvailable(nil)
            return report(["status": "current", "current": revision])
        }
        guard (try? git("merge-base", "--is-ancestor", "HEAD", new)) != nil else {
            return report(["status": "local-commits"])
        }
        // Refuse a stable rewind relative to the running app when its commit is known.
        if !revision.isEmpty, (try? git("cat-file", "-e", revision + "^{commit}")) != nil,
           (try? git("merge-base", "--is-ancestor", revision, new)) == nil {
            throw Failure(description: "Stable channel is older than the running app")
        }
        try body(old, new)
    }

    private func handoff(staged: URL, next: String) {
        DispatchQueue.main.async {
            guard !self.isBusy() else {
                self.report(["status": "waiting", "current": self.revision, "next": next])
                self.schedule(after: Self.retry) { $0.installed ? $0.install() : $0.installSelf() }
                return
            }
            do {
                try FileManager.default.createDirectory(at: self.updates, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let token = UUID().uuidString
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                var args = [staged.appendingPathComponent("Contents/Resources/install_app.py").path,
                            "--staged", staged.path, "--current", Bundle.main.bundleURL.path,
                            "--target", Self.target.path, "--support", Self.support.path,
                            "--pid", String(ProcessInfo.processInfo.processIdentifier), "--token", token]
                if SMAppService.mainApp.status == .enabled { args.append("--restore-login") }
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: "/")
                process.environment = Self.cleanEnvironment()
                process.standardInput = FileHandle.nullDevice
                let log = self.updates.appendingPathComponent("install.log")
                if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
                let output = try FileHandle(forWritingTo: log)
                try output.seekToEnd()
                process.standardOutput = output
                process.standardError = output
                try process.run()
                self.installing = true
                self.report(["status": "installing", "current": self.revision, "next": next], save: false)
                self.waitForInstaller(process, token: token, next: next, deadline: Date().addingTimeInterval(120))
            } catch { self.report(["status": "failed", "detail": String(describing: error)]) }
        }
    }

    private func waitForInstaller(_ process: Process, token: String, next: String, deadline: Date) {
        // Poll without blocking the UI. Recheck busy immediately before quitting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let ready = self.updates.appendingPathComponent(token + ".ready")
            if FileManager.default.fileExists(atPath: ready.path) {
                guard !self.isBusy() else {
                    process.terminate()
                    self.installing = false
                    self.report(["status": "waiting", "current": self.revision, "next": next])
                    self.schedule(after: Self.retry) { $0.installed ? $0.install() : $0.installSelf() }
                    return
                }
                if SMAppService.mainApp.status == .enabled {
                    do { try SMAppService.mainApp.unregister() }
                    catch {
                        process.terminate()
                        self.installing = false
                        self.report(["status": "failed", "detail": "Could not unregister old login item: \(error)"])
                        return
                    }
                }
                NSApp.terminate(nil)
            } else if !process.isRunning || Date() > deadline {
                if process.isRunning { process.terminate() }
                self.installing = false
                self.report(["status": "failed", "detail": "Installer preparation failed; see updates/install.log"])
            } else { self.waitForInstaller(process, token: token, next: next, deadline: deadline) }
        }
    }

    /// The new app confirms it started, so the installer can finish (or roll back if it never does).
    private func acknowledgeInstallation() {
        let journal = updates.appendingPathComponent("transaction.json")
        guard let data = try? Data(contentsOf: journal),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if record["phase"] as? String == "starting",
           record["target"] as? String == Bundle.main.bundleURL.path,
           record["revision"] as? String == revision, let token = record["token"] as? String,
           UUID(uuidString: token) != nil {
            if record["restoreLogin"] as? Bool == true {
                do { try SMAppService.mainApp.register() }
                catch { report(["status": "failed", "detail": "Login item registration failed: \(error)"]) }
            }
            let confirmation: [String: Any] = ["revision": revision, "pid": ProcessInfo.processInfo.processIdentifier]
            if let ack = try? JSONSerialization.data(withJSONObject: confirmation) {
                try? ack.write(to: updates.appendingPathComponent(token + ".ack"), options: .atomic)
            }
        } else if record["phase"] as? String == "failed", record["restoreLogin"] as? Bool == true {
            try? SMAppService.mainApp.register()
        }
    }

    struct Failure: Error, CustomStringConvertible { let description: String }

    @discardableResult
    private func git(_ arguments: String..., timeout: TimeInterval = 60) throws -> String {
        try execute(["/usr/bin/git", "-C", root.path] + arguments, timeout: timeout, step: "git " + (arguments.first ?? ""))
    }

    private func shell(_ arguments: [String], timeout: TimeInterval, step: String) throws {
        _ = try execute(["/usr/bin/env"] + arguments, timeout: timeout, step: step)
    }

    private static func cleanEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in ["PWD", "OLDPWD"] { env.removeValue(forKey: key) }
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        return env
    }

    private func execute(_ command: [String], timeout: TimeInterval, step: String, directory: URL? = nil) throws -> String {
        let process = Process(), out = Pipe()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        process.currentDirectoryURL = directory ?? root
        process.environment = Self.cleanEnvironment()
        process.standardOutput = out
        process.standardError = out
        process.standardInput = FileHandle.nullDevice
        try process.run()
        var data = Data()
        let reader = DispatchQueue(label: "updater-read"), done = DispatchSemaphore(value: 0)
        reader.async { data = out.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            throw Failure(description: "\(step) timed out")
        }
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw Failure(description: "\(step) failed" + (text.isEmpty ? "" : ": " + String(text.suffix(160))))
        }
        return text
    }

    // MARK: State

    private func loadState() -> [String: String] {
        guard let data = try? Data(contentsOf: stateFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return json
    }

    private func report(_ state: [String: String], save: Bool = true) {
        var state = state
        state["at"] = ISO8601DateFormatter().string(from: Date())
        if save {
            try? FileManager.default.createDirectory(at: Self.support, withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: stateFile, options: .atomic)
            }
        }
        let text = Self.describe(state)
        AppModel.log("Update: \(text)")
        DispatchQueue.main.async { self.status = text }
    }

    static func describe(_ s: [String: String]) -> String {
        func short(_ rev: String?) -> String { String((rev ?? "").prefix(7)) }
        let when: String = {
            guard let at = s["at"].flatMap({ ISO8601DateFormatter().date(from: $0) }) else { return "" }
            let f = DateFormatter()
            f.dateFormat = Calendar.current.isDateInToday(at) ? "h:mm a" : "M/d h:mm a"
            return " · " + f.string(from: at)
        }()
        switch s["status"] ?? "" {
        case "checking": return "Checking for a new version…"
        case "building": return "Testing and building \(short(s["next"]))…"
        case "installing": return "Installing \(short(s["next"]))…"
        case "available": return "New version \(short(s["next"])) is available. Click Update Now to install." + when
        case "waiting": return "Updating after you put the cat down."
        case "current": return "Up to date (\(short(s["current"])))" + when
        case "updated":
            if s["previous"] == nil || s["previous"] == s["current"] { return "Installed: \(short(s["current"]))" + when }
            return "Updated: \(short(s["previous"])) → \(short(s["current"]))" + when
        case "postponed": return "Another update step is running" + when
        case "local-changes": return "Skipped: the update copy has local changes" + when
        case "local-commits": return "Skipped: the update copy has commits not on GitHub" + when
        case "failed": return "Update failed; keeping this version: " + (s["detail"] ?? "") + when
        default: return ""
        }
    }
}
