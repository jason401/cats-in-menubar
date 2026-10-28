import Foundation

/// How hard the app may work. With plenty of CPU headroom the cats are lively and smooth;
/// as the Mac gets busy, hot or enters Low Power Mode, they rest and the app does less.
enum PowerLevel: Int {
    case full, eco, low

    var label: String {
        switch self {
        case .full: "Full"
        case .eco: "Eco"
        case .low: "Low power"
        }
    }
    /// Animation timer while someone is moving.
    var frameInterval: Double {
        switch self {
        case .full: 1.0 / 30
        case .eco: 1.0 / 15
        case .low: 1.0 / 8
        }
    }
    /// While everyone rests, only every n-th frame is drawn (10, 5 and 2 fps).
    var idleEvery: Int {
        switch self {
        case .full: 3
        case .eco: 3
        case .low: 4
        }
    }
    var scanInterval: Double {
        switch self {
        case .full: 1
        case .eco: 2
        case .low: 4
        }
    }
    /// System readings are taken at least this far apart.
    var sampleFloor: Double {
        switch self {
        case .full: 0
        case .eco: 2
        case .low: 5
        }
    }
    /// Shifts the cats' choices from naps (negative) toward running and hunting (positive).
    var mood: Double {
        switch self {
        case .full: 0
        case .eco: -0.15
        case .low: -0.35
        }
    }
}

struct PowerGovernor {
    private(set) var smoothed = 0.0
    private(set) var level = PowerLevel.full

    /// Averages recent CPU readings and keeps a gap between the up and down thresholds,
    /// so a short spike or a value near a boundary does not flip the mode back and forth.
    mutating func update(cpu: Double, lowPowerMode: Bool, thermal: ProcessInfo.ThermalState) -> PowerLevel {
        smoothed = smoothed * 0.6 + cpu * 0.4
        if lowPowerMode || thermal == .serious || thermal == .critical { level = .low; return level }
        switch level {
        case .full: if smoothed > 0.75 { level = .low } else if smoothed > 0.45 { level = .eco }
        case .eco: if smoothed > 0.75 { level = .low } else if smoothed < 0.3 { level = .full }
        case .low: if smoothed < 0.3 { level = .full } else if smoothed < 0.55 { level = .eco }
        }
        if thermal == .fair && level == .full { level = .eco }
        return level
    }

    /// A little extra bounce when the Mac is nearly idle.
    var liveliness: Double { level == .full && smoothed < 0.2 ? 0.08 : level.mood }
}
