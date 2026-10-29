import Cocoa
import ServiceManagement
import SwiftUI

/// Preference keys in the app's own UserDefaults domain.
enum Pref {
    static let count = "catCount", paused = "paused", quiet = "quiet"
    static let fixedLineup = "useCustomLineup", lineup = "catLineup"
    static let activity = "activity", adaptivePower = "adaptivePower", allowDrag = "allowDrag"
    static let nightQuiet = "nightQuiet", nightFrom = "nightFrom", nightTo = "nightTo"
    static let cpuInBar = "showCPUInBar", interval = "monitorInterval"
    static let showCPU = "showCPU", showMemory = "showMemory", showDisk = "showDisk", showBattery = "showBattery", showNetwork = "showNetwork"
    static let defaults: [String: Any] = [
        count: 3, fixedLineup: false, paused: false, quiet: false, activity: 1, adaptivePower: true, allowDrag: true,
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
                    StatSection(icon: "gauge.with.dots.needle.67percent", tint: .blue, title: "CPU: \(percent(s.cpu))") {
                        Detail("System", percent(s.cpuSystem)); Detail("User", percent(s.cpuUser)); Detail("Idle", percent(s.cpuIdle))
                        Sparkline(values: system.cpuHistory).frame(height: 22).padding(.top, 2)
                    }
                }
                if showMemory {
                    StatSection(icon: "square.stack.3d.up.fill", tint: .purple, title: "Memory: \(percent(s.memoryUsed / max(1, s.memoryTotal)))") {
                        Detail("Pressure", percent(s.memoryPressure)); Detail("App Memory", bytes(s.memoryApp))
                        Detail("Wired Memory", bytes(s.memoryWired)); Detail("Compressed", bytes(s.memoryCompressed))
                        Meter(value: s.memoryUsed / max(1, s.memoryTotal))
                    }
                }
                if showDisk {
                    StatSection(icon: "externaldrive.fill", tint: .orange, title: "Storage: \(percent(s.diskUsed / max(1, s.diskTotal))) used") {
                        Detail(nil, "\(bytes(s.diskUsed)) / \(bytes(s.diskTotal))")
                        Meter(value: s.diskUsed / max(1, s.diskTotal))
                    }
                }
                if showBattery {
                    if s.hasBattery {
                        StatSection(icon: s.charging ? "battery.100.bolt" : "battery.75", tint: .green, title: "Battery: \(Int(s.batteryLevel * 100))%") {
                            Detail(nil, s.charging ? "Charging" : (s.onAC ? "On power adapter" : "On battery"))
                        }
                    } else {
                        StatSection(icon: "bolt.fill", tint: .green, title: "Power: Adapter") { EmptyView() }
                    }
                }
                if showNetwork {
                    StatSection(icon: s.networkName.localizedCaseInsensitiveContains("wi-fi") ? "wifi" : (s.networkName == "Offline" ? "wifi.slash" : "cable.connector"), tint: .teal, title: "Network: \(s.networkName)") {
                        Detail("Local IP", s.localIP); Detail("Upload", rate(s.upload)); Detail("Download", rate(s.download))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
            if s.thermal == .serious || s.thermal == .critical {
                Label("Your Mac is running hot", systemImage: "thermometer.high").font(.caption).foregroundStyle(.orange)
            }
            UpdateBanner(updater: Updater.shared)
            HStack(spacing: 6) {
                PanelButton(icon: model.catsAway ? "door.left.hand.open" : "house.fill", label: model.catsAway ? "Let out" : "Call home") { model.home?() }
                    .disabled(paused || !model.access)
                PanelButton(icon: "circle.fill", label: "Ball", action: play).disabled(paused || !model.access || model.catsAway)
                PanelButton(icon: paused ? "play.fill" : "pause.fill", label: paused ? "Resume" : "Pause") { paused.toggle() }
                PanelButton(icon: "gearshape", label: "Settings", action: openSettings)
                PanelButton(icon: "power", label: "Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct UpdateBanner: View {
    @ObservedObject var updater: Updater
    var body: some View {
        if updater.available != nil {
            HStack {
                Label("New version available", systemImage: "arrow.down.circle.fill").font(.caption)
                Spacer()
                Button("Update Now") { updater.install() }.controlSize(.small).disabled(updater.checking)
            }
        }
    }
}

private struct StatSection<Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Small colored badge, in the spirit of System Settings icons.
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(tint.gradient))
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
// Same look as AI Face and AI Illuminati: toolbar tabs, titled cards of one-line rows, small text.

struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 2)
            VStack(spacing: 0) { content }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.07)))
        }
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 96, alignment: .leading)
            HStack(spacing: 6) { content }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(minHeight: 32)
    }
}

/// A short gray line under a row; the long version goes in `help`.
struct SettingsNote: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10)).foregroundStyle(.secondary)
            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.bottom, 7)
    }
}

struct SettingsAction: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).lineLimit(1).frame(maxWidth: .infinity, minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
        }.buttonStyle(.plain)
    }
}

/// An on/off switch at the right end of its row.
struct SettingsSwitch: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

struct SettingsSegments<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                Button { selection = options[index].1 } label: {
                    Text(options[index].0).lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .foregroundStyle(selection == options[index].1 ? Color.white : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 4).fill(selection == options[index].1 ? Color.accentColor : Color.clear))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(2).background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
    }
}

// A popup filling the control column; SwiftUI's Picker sizes itself to its widest item.
struct SettingsMenu<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value
    var body: some View {
        SettingsPopup(titles: options.map { $0.0 }, selection: Binding(
            get: { options.firstIndex { $0.1 == selection } ?? 0 },
            set: { if options.indices.contains($0) { selection = options[$0].1 } }))
            .frame(maxWidth: .infinity).frame(height: 24)
    }
}

struct SettingsPopup: NSViewRepresentable {
    let titles: [String]
    @Binding var selection: Int
    final class Coordinator: NSObject {
        var parent: SettingsPopup
        init(_ parent: SettingsPopup) { self.parent = parent }
        @objc func select(_ sender: NSPopUpButton) { parent.selection = sender.indexOfSelectedItem }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if button.itemTitles != titles { button.removeAllItems(); button.addItems(withTitles: titles) }
        button.selectItem(at: selection)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 184, height: 24)
    }
}

/// A status word in the control column: green when things are fine, gray otherwise.
struct SettingsStatus: View {
    let text: String
    var ok = false
    var body: some View {
        Text(text).lineLimit(1).foregroundStyle(ok ? Color.green : Color.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Window state lives in a class: the Command Line Tools toolchain lacks the macro plugin behind SwiftUI's @State.
final class SettingsState: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
}

private let hours = (0..<24).map { (String(format: "%02d:00", $0), $0) }

struct GeneralTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: SettingsState
    @AppStorage(Pref.cpuInBar) private var cpuInBar = false
    var body: some View {
        SettingsPage {
            SettingsCard(title: "App") {
                SettingsRow(title: "Open at login") {
                    SettingsSwitch(title: "Open at login", isOn: Binding(get: { state.launchAtLogin }, set: { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            state.loginError = nil
                        } catch { state.loginError = error.localizedDescription }
                        state.launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
                }
                if let error = state.loginError { SettingsNote(text: error) }
                Divider()
                SettingsRow(title: "CPU in menu bar") {
                    SettingsSwitch(title: "CPU in menu bar", isOn: $cpuInBar).help("Shows the CPU percentage next to the cat tower icon.")
                }
            }
            SettingsCard(title: "Access") {
                SettingsRow(title: "Accessibility") {
                    SettingsStatus(text: model.access ? "Allowed" : "Not allowed", ok: model.access)
                    if !model.access {
                        SettingsAction(title: "Allow…") {
                            MenuBarMonitor.requestAccess()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
                SettingsNote(text: "Only reads where menus and icons are. No screen capture, no menu text.")
                Divider()
                SettingsRow(title: "Safe space") {
                    SettingsSwitch(title: "Show safe space", isOn: $model.debug).help("Tints the empty menu bar space the cats may use.")
                }
                Divider()
                SettingsRow(title: "Log") { SettingsAction(title: "Open log") { NSWorkspace.shared.open(AppModel.logURL) } }
                SettingsNote(text: model.status)
            }
            UpdatesCard(updater: Updater.shared)
            SettingsCard(title: "About") {
                SettingsRow(title: "Version") {
                    Text(version).foregroundStyle(.secondary)
                }
                SettingsNote(text: "No analytics. The only network request is the update check against the public GitHub repository.")
            }
        }
    }
}

private var version: String {
    let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    let revision = (Bundle.main.object(forInfoDictionaryKey: "CatsSourceRevision") as? String ?? "").prefix(7)
    return revision.isEmpty ? short : "\(short) (\(revision))"
}

/// Like AI Illuminati's "Updates & storage": checks run on their own, installing waits for the button.
struct UpdatesCard: View {
    @ObservedObject var updater: Updater
    var body: some View {
        SettingsCard(title: "Updates") {
            if updater.installed {
                SettingsRow(title: "Check automatically") {
                    SettingsSwitch(title: "Check automatically", isOn: $updater.enabled).help("Checks the stable branch 60 seconds after launch and every 3 hours. Never installs on its own.")
                }
                Divider()
                SettingsRow(title: "New version") {
                    if updater.available != nil {
                        SettingsAction(title: "Update Now") { updater.install() }.disabled(updater.checking)
                    } else {
                        SettingsAction(title: "Check Now") { updater.check() }.disabled(updater.checking)
                    }
                }
            }
            if !updater.installed {
                SettingsNote(text: "This development copy does not update. The copy in /Applications checks the stable branch.")
            } else if !updater.status.isEmpty { SettingsNote(text: updater.status) }
        }
    }
}

struct CatsTab: View {
    @ObservedObject var model: AppModel
    @AppStorage(Pref.count) private var count = 3
    @AppStorage(Pref.paused) private var paused = false
    @AppStorage(Pref.allowDrag) private var allowDrag = true
    @AppStorage(Pref.activity) private var activity = 1
    @AppStorage(Pref.adaptivePower) private var adaptivePower = true
    @AppStorage(Pref.quiet) private var quiet = false
    @AppStorage(Pref.nightQuiet) private var nightQuiet = false
    @AppStorage(Pref.nightFrom) private var nightFrom = 23
    @AppStorage(Pref.nightTo) private var nightTo = 7
    var body: some View {
        SettingsPage {
            SettingsCard(title: "Cats") {
                SettingsRow(title: "Cats") { SettingsSegments(options: [("1", 1), ("2", 2), ("3", 3)], selection: $count) }
                Divider()
                SettingsRow(title: "At home") {
                    SettingsAction(title: model.catsAway ? "Let them out" : "Call them home") { model.home?() }.disabled(!model.access)
                }
                Divider()
                SettingsRow(title: "Pause") { SettingsSwitch(title: "Pause", isOn: $paused) }
                Divider()
                SettingsRow(title: "Pick up") {
                    SettingsSwitch(title: "Pick up", isOn: $allowDrag).help("Drag a cat with the mouse. It stays inside its own empty space.")
                }
            }
            SettingsCard(title: "Your cats") {
                ForEach(model.lineup.indices, id: \.self) { i in
                    if i > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(nsImage: CatDrawing.thumbnail(model.lineup[i])).frame(width: 46, height: 30)
                            Text("Cat \(i + 1)").font(.system(size: 11, weight: .medium))
                            Spacer()
                        }
                        HStack(spacing: 6) {
                            SettingsMenu(options: CatAppearance.names.enumerated().map { ($0.element, $0.offset) }, selection: Binding(
                                get: { model.lineup[i].coat },
                                set: { value in var appearance = model.lineup[i]; appearance.coat = value; model.configureCat?(i, appearance) }))
                                .accessibilityLabel("Cat \(i + 1) color")
                            SettingsMenu(options: CatSize.allCases.map { ($0.label, $0) }, selection: Binding(
                                get: { model.lineup[i].size },
                                set: { value in var appearance = model.lineup[i]; appearance.size = value; model.configureCat?(i, appearance) }))
                                .frame(width: 91).accessibilityLabel("Cat \(i + 1) size")
                        }
                    }.padding(.horizontal, 10).padding(.vertical, 5)
                }
                Divider()
                SettingsRow(title: "Keep my cats") {
                    SettingsSwitch(title: "Keep my cats at launch", isOn: Binding(get: { model.keepLineup }, set: { model.rememberCats?($0) }))
                }
                SettingsNote(text: "Off: new colors and sizes each launch. On: keep this lineup. Positions are always random.")
                SettingsRow(title: "New lineup") { SettingsAction(title: "Shuffle cats") { model.shuffleCats?() } }
            }
            SettingsCard(title: "Behavior") {
                SettingsRow(title: "Activity") { SettingsSegments(options: [("Calm", 0), ("Normal", 1), ("Playful", 2)], selection: $activity) }
                Divider()
                SettingsRow(title: "Save power") {
                    SettingsSwitch(title: "Save power", isOn: $adaptivePower)
                        .help("Plenty of CPU headroom: lively cats at full frame rate. As the Mac gets busy, hot or enters Low Power Mode, cats rest more and the app draws and checks less often.")
                }
                Divider()
                SettingsRow(title: "Now") { SettingsStatus(text: model.power.label, ok: model.power == .full) }
                SettingsNote(text: "When the Mac is busy, cats nap and the app draws less to stay out of the way.")
            }
            SettingsCard(title: "Quiet time") {
                SettingsRow(title: "Sleep now") { SettingsSwitch(title: "Sleep now", isOn: $quiet) }
                Divider()
                SettingsRow(title: "Every night") { SettingsSwitch(title: "Every night", isOn: $nightQuiet) }
                if nightQuiet {
                    Divider()
                    SettingsRow(title: "From") { SettingsMenu(options: hours, selection: $nightFrom) }
                    Divider()
                    SettingsRow(title: "Until") { SettingsMenu(options: hours, selection: $nightTo) }
                }
            }
        }
    }
}

struct MonitorTab: View {
    @AppStorage(Pref.interval) private var interval = 2.0
    @AppStorage(Pref.showCPU) private var showCPU = true
    @AppStorage(Pref.showMemory) private var showMemory = true
    @AppStorage(Pref.showDisk) private var showDisk = true
    @AppStorage(Pref.showBattery) private var showBattery = true
    @AppStorage(Pref.showNetwork) private var showNetwork = true
    var body: some View {
        SettingsPage {
            SettingsCard(title: "Update") {
                SettingsRow(title: "Every") { SettingsSegments(options: [("1 s", 1.0), ("2 s", 2.0), ("5 s", 5.0)], selection: $interval) }
            }
            SettingsCard(title: "Show in the panel") {
                SettingsRow(title: "CPU") { SettingsSwitch(title: "CPU", isOn: $showCPU) }
                Divider()
                SettingsRow(title: "Memory") { SettingsSwitch(title: "Memory", isOn: $showMemory) }
                Divider()
                SettingsRow(title: "Storage") { SettingsSwitch(title: "Storage", isOn: $showDisk) }
                Divider()
                SettingsRow(title: "Power") { SettingsSwitch(title: "Power", isOn: $showBattery) }
                Divider()
                SettingsRow(title: "Network") { SettingsSwitch(title: "Network", isOn: $showNetwork) }
            }
        }
    }
}

/// Toolbar tabs at a fixed size, like AI Face's settings window.
final class SettingsWindowController: NSObject {
    static let size = NSSize(width: 334, height: 460)
    static let tabs: [(String, String)] = [("General", "gearshape"), ("Cats", "pawprint"), ("Monitor", "gauge.with.dots.needle.33percent")]
    let model: AppModel
    let state = SettingsState()
    private(set) var window: NSWindow?
    init(model: AppModel) { self.model = model }

    func view(for index: Int) -> AnyView {
        switch index {
        case 0: AnyView(GeneralTab(model: model, state: state))
        case 1: AnyView(CatsTab(model: model))
        default: AnyView(MonitorTab())
        }
    }
    private func tab(_ index: Int) -> NSTabViewItem {
        let size = SettingsWindowController.size
        let (title, symbol) = SettingsWindowController.tabs[index]
        let host = NSHostingController(rootView: view(for: index).frame(width: size.width, height: size.height))
        // A fixed size: otherwise the hosting view sizes itself from its content's ideal width.
        host.sizingOptions = []
        host.view.frame = NSRect(origin: .zero, size: size)
        host.preferredContentSize = size
        host.title = title
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
    func show() {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            for index in SettingsWindowController.tabs.indices { tabs.addTabViewItem(tab(index)) }
            let w = NSWindow(contentViewController: tabs)
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(SettingsWindowController.size)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
