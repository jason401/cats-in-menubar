import Cocoa
import ServiceManagement
import SwiftUI

/// Preference keys in the app's own UserDefaults domain.
enum Pref {
    static let count = "catCount", paused = "paused", quiet = "quiet"
    static let activity = "activity", reactToCPU = "reactToCPU", allowDrag = "allowDrag"
    static let nightQuiet = "nightQuiet", nightFrom = "nightFrom", nightTo = "nightTo"
    static let cpuInBar = "showCPUInBar", interval = "monitorInterval"
    static let showCPU = "showCPU", showMemory = "showMemory", showDisk = "showDisk", showBattery = "showBattery", showNetwork = "showNetwork"
    static let defaults: [String: Any] = [
        count: 3, paused: false, quiet: false, activity: 1, reactToCPU: true, allowDrag: true,
        nightQuiet: false, nightFrom: 23, nightTo: 7, cpuInBar: false, interval: 2.0,
        showCPU: true, showMemory: true, showDisk: true, showBattery: true, showNetwork: true,
    ]
}

private func bytes(_ value: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
}
private func rate(_ value: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) + "/s"
}
private func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }

// MARK: Dashboard (opens from the menu bar icon)

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var system: SystemMonitor
    @AppStorage(Pref.paused) private var paused = false
    @AppStorage(Pref.showCPU) private var showCPU = true
    @AppStorage(Pref.showMemory) private var showMemory = true
    @AppStorage(Pref.showDisk) private var showDisk = true
    @AppStorage(Pref.showBattery) private var showBattery = true
    @AppStorage(Pref.showNetwork) private var showNetwork = true
    var openSettings: () -> Void
    var play: () -> Void

    var body: some View {
        let s = system.stats
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: TowerIcon.app(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cats in Menubar").font(.headline)
                    Text(paused ? "Cats are paused" : model.catSummary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
            }
            VStack(spacing: 0) {
                if showCPU {
                    StatSection(icon: "cpu", title: "CPU: \(percent(s.cpu))") {
                        Detail("System", percent(s.cpuSystem)); Detail("User", percent(s.cpuUser)); Detail("Idle", percent(s.cpuIdle))
                        Sparkline(values: system.cpuHistory).frame(height: 22).padding(.top, 2)
                    }
                }
                if showMemory {
                    StatSection(icon: "memorychip", title: "Memory: \(percent(s.memoryUsed / max(1, s.memoryTotal)))") {
                        Detail("Pressure", percent(s.memoryPressure)); Detail("App Memory", bytes(s.memoryApp))
                        Detail("Wired Memory", bytes(s.memoryWired)); Detail("Compressed", bytes(s.memoryCompressed))
                        Meter(value: s.memoryUsed / max(1, s.memoryTotal))
                    }
                }
                if showDisk {
                    StatSection(icon: "internaldrive", title: "Storage: \(percent(s.diskUsed / max(1, s.diskTotal))) used") {
                        Detail(nil, "\(bytes(s.diskUsed)) / \(bytes(s.diskTotal))")
                        Meter(value: s.diskUsed / max(1, s.diskTotal))
                    }
                }
                if showBattery {
                    if s.hasBattery {
                        StatSection(icon: s.charging ? "battery.100.bolt" : "battery.75", title: "Battery: \(Int(s.batteryLevel * 100))%") {
                            Detail(nil, s.charging ? "Charging" : (s.onAC ? "On power adapter" : "On battery"))
                        }
                    } else {
                        StatSection(icon: "powerplug", title: "Power: Adapter") { EmptyView() }
                    }
                }
                if showNetwork {
                    StatSection(icon: "network", title: "Network: \(s.networkName)") {
                        Detail("Local IP", s.localIP); Detail("Upload", rate(s.upload)); Detail("Download", rate(s.download))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
            if s.thermal == .serious || s.thermal == .critical {
                Label("Your Mac is running hot", systemImage: "thermometer.high").font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 6) {
                PanelButton(icon: "circle.fill", label: "Ball", action: play).disabled(paused || !model.access)
                PanelButton(icon: paused ? "play.fill" : "pause.fill", label: paused ? "Resume" : "Pause") { paused.toggle() }
                PanelButton(icon: "gearshape", label: "Settings", action: openSettings)
                PanelButton(icon: "power", label: "Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct StatSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 20, weight: .regular)).frame(width: 30).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                content
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}

private struct Detail: View {
    let name: String?
    let value: String
    init(_ name: String?, _ value: String) { self.name = name; self.value = value }
    var body: some View {
        HStack(spacing: 4) {
            if let name { Text("\(name):").foregroundStyle(.secondary) }
            Text(value).monospacedDigit()
        }.font(.system(size: 11))
    }
}

private struct Meter: View {
    let value: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(value > 0.9 ? Color.orange : Color.accentColor).frame(width: geometry.size.width * min(1, max(0, value)))
            }
        }.frame(height: 6).padding(.top, 4)
    }
}

private struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geometry in
            let points = values.enumerated().map { index, value in
                CGPoint(x: geometry.size.width * CGFloat(index) / CGFloat(max(1, 59)) + geometry.size.width * CGFloat(60 - values.count) / 59,
                        y: geometry.size.height * (1 - CGFloat(min(1, value))))
            }
            if let first = points.first, let last = points.last {
                Path { path in
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                }.fill(Color.accentColor.opacity(0.75))
            }
        }
    }
}

private struct PanelButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 14))
                Text(label).font(.system(size: 10))
            }.frame(maxWidth: .infinity).padding(.vertical, 6)
        }.buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: Settings window

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", cats = "Cats", behavior = "Behavior", monitor = "System Monitor", permissions = "Permissions", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .cats: "pawprint"
        case .behavior: "figure.run"
        case .monitor: "gauge.with.dots.needle.33percent"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

/// Window state lives in a class: the Command Line Tools toolchain lacks the macro plugin behind SwiftUI's @State.
final class SettingsState: ObservableObject {
    @Published var page: SettingsPage? = .general
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: SettingsState
    var body: some View {
        let page = state.page
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $state.page) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            Form {
                switch page ?? .general {
                case .general: GeneralPage(state: state)
                case .cats: CatsPage(model: model)
                case .behavior: BehaviorPage()
                case .monitor: MonitorPage()
                case .permissions: PermissionsPage(model: model)
                case .about: AboutPage()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((page ?? .general).rawValue)
        }
        .frame(minWidth: 640, minHeight: 440)
    }
}

private struct GeneralPage: View {
    @ObservedObject var state: SettingsState
    @AppStorage(Pref.cpuInBar) private var cpuInBar = false
    var body: some View {
        Section {
            Toggle("Open at login", isOn: Binding(get: { state.launchAtLogin }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    state.loginError = nil
                } catch { state.loginError = error.localizedDescription }
                state.launchAtLogin = SMAppService.mainApp.status == .enabled
            }))
            if let error = state.loginError { Text(error).font(.caption).foregroundStyle(.red) }
        }
        Section("Menu bar") {
            Toggle("Show CPU usage next to the icon", isOn: $cpuInBar)
        }
    }
}

private struct CatsPage: View {
    @ObservedObject var model: AppModel
    @AppStorage(Pref.count) private var count = 3
    @AppStorage(Pref.paused) private var paused = false
    @AppStorage(Pref.allowDrag) private var allowDrag = true
    var body: some View {
        Section {
            Picker("Number of cats", selection: $count) { Text("1").tag(1); Text("2").tag(2); Text("3").tag(3) }.pickerStyle(.segmented)
            Toggle("Pause and hide cats", isOn: $paused)
            Toggle("Let me pick cats up and move them", isOn: $allowDrag)
        }
        Section {
            Button("Bring out a ball") { model.play?() }.disabled(paused || !model.access)
        } footer: {
            Text("Cats only use empty menu bar space. A carried cat stays within its own free space.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct BehaviorPage: View {
    @AppStorage(Pref.activity) private var activity = 1
    @AppStorage(Pref.reactToCPU) private var reactToCPU = true
    @AppStorage(Pref.quiet) private var quiet = false
    @AppStorage(Pref.nightQuiet) private var nightQuiet = false
    @AppStorage(Pref.nightFrom) private var nightFrom = 23
    @AppStorage(Pref.nightTo) private var nightTo = 7
    var body: some View {
        Section {
            Picker("Activity", selection: $activity) { Text("Calm").tag(0); Text("Normal").tag(1); Text("Playful").tag(2) }.pickerStyle(.segmented)
            Toggle("Livelier when the Mac is busy", isOn: $reactToCPU)
        } footer: {
            Text("With this on, high CPU use makes the cats run around more, like a little load meter.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Quiet time") {
            Toggle("Quiet time now", isOn: $quiet)
            Toggle("Sleep at night", isOn: $nightQuiet)
            if nightQuiet {
                Picker("From", selection: $nightFrom) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Picker("Until", selection: $nightTo) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
            }
        }
    }
}

private struct MonitorPage: View {
    @AppStorage(Pref.interval) private var interval = 2.0
    @AppStorage(Pref.showCPU) private var showCPU = true
    @AppStorage(Pref.showMemory) private var showMemory = true
    @AppStorage(Pref.showDisk) private var showDisk = true
    @AppStorage(Pref.showBattery) private var showBattery = true
    @AppStorage(Pref.showNetwork) private var showNetwork = true
    var body: some View {
        Section {
            Picker("Update every", selection: $interval) { Text("1 second").tag(1.0); Text("2 seconds").tag(2.0); Text("5 seconds").tag(5.0) }
        }
        Section("Show in the panel") {
            Toggle("CPU", isOn: $showCPU); Toggle("Memory", isOn: $showMemory); Toggle("Storage", isOn: $showDisk)
            Toggle("Battery / power", isOn: $showBattery); Toggle("Network", isOn: $showNetwork)
        }
    }
}

private struct PermissionsPage: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Section {
            HStack {
                Image(systemName: model.access ? "checkmark.shield.fill" : "lock.fill").foregroundStyle(model.access ? .green : .orange)
                Text(model.access ? "Accessibility access granted" : "Accessibility access required")
            }
            if !model.access {
                Button("Allow Accessibility Access…") {
                    MenuBarMonitor.requestAccess()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                }
            }
        } footer: {
            Text("Used only to read where menus and icons are, so cats stay out of their way. The app never captures the screen or reads menu text.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Troubleshooting") {
            Toggle("Show safe space", isOn: $model.debug)
            Text(model.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Button("Open log") { NSWorkspace.shared.open(AppModel.logURL) }
        }
    }
}

private struct AboutPage: View {
    var body: some View {
        Section {
            HStack(spacing: 14) {
                Image(nsImage: TowerIcon.app(size: 64))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cats in Menubar").font(.title3.bold())
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")").foregroundStyle(.secondary)
                    Text("A little life in the empty space.").foregroundStyle(.secondary)
                }
            }
        }
        Section {
            Text("Everything stays on this Mac: no network requests, no screen capture, no analytics.").font(.callout)
        }
    }
}
