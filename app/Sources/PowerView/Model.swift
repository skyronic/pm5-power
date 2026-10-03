import Foundation
import os
import PowerProtocol
import RideCore

private let log = Logger(subsystem: "pm5-power", category: "ride")

/// Live state shown in the window. All mutation happens on the main thread.
///
/// The window mirrors the PM5: clock, average and stopped state are whatever it last sent.
/// Readings redraw at most once per the Refresh setting, via `changed()`; connection changes,
/// stopping, resuming and new workouts redraw immediately.
final class Model: ObservableObject {
    static let refreshKey = "refresh"  // seconds between redraws for readings; 0 = every reading

    /// Kept after data stops, so the last workout stays on screen and a reconnect can spot a new one.
    private(set) var pm5 = PM5State()
    private(set) var avg3: Double?
    private(set) var trace = Trace()
    @Published var live = false  // power arrived in the last 3s
    @Published var link = Link.starting
    @Published var lastError: String?  // most recent Bluetooth error, shown in the menu
    @Published var idleDisconnectIn: Int?  // seconds; only set in the last minute before an idle disconnect
    var paused: Bool { if case .paused = link { true } else { false } }  // disconnected on purpose; click to reconnect
    var lastUpdate: Date?
    var lastPedal: Date?  // last time the PM5 said the rider was moving
    var workoutEnded: Date?  // when the PM5 last left a workout (ended, or back on the menu)

    private var samples: [(Date, Int)] = []
    private var lastRedraw = Date.distantPast
    private var redrawPending = false

    func update(_ r: Reading) {
        let now = Date()
        if !live {
            let gap = lastUpdate.map { String(format: " after %.1fs gap", now.timeIntervalSince($0)) } ?? ""
            log.info("Data arriving\(gap, privacy: .public)")
            live = true
        }
        pm5.apply(r)
        if let watts = r.watts {
            // The PM5's rowing state decides; raw watts only before it has said anything. (Cycling Power
            // can send a stray non-zero reading as a workout is ended, which would delay the idle disconnect.)
            if watts > 0, pm5.active == nil { lastPedal = now }
            samples.append((now, watts))
            samples.removeAll { now.timeIntervalSince($0.0) > 3 }
            avg3 = Double(samples.map(\.1).reduce(0, +)) / Double(samples.count)
            if let t = pm5.elapsed { trace.add(watts: watts, at: t) }
        }
        lastUpdate = now
        changed()
    }

    func updateStatus(_ s: WorkoutStatus) {
        let before = pm5
        let restarted = pm5.apply(s)
        if restarted {
            log.info("PM5 workout restarted (\(before.elapsed ?? 0, format: .fixed(precision: 2))s → \(s.elapsed, format: .fixed(precision: 2))s)")
            trace = Trace()
        }
        if pm5.active == true { lastPedal = Date() }
        if before.inWorkout != false, pm5.inWorkout == false {
            log.info("PM5 workout ended: \(self.summary, privacy: .public)")
            workoutEnded = Date()
        }
        let toggled = before.active.map { $0 != pm5.active } ?? false
        if toggled { log.info("PM5 \(self.pm5.active == true ? "active" : "stopped", privacy: .public): \(self.summary, privacy: .public)") }
        if pm5 != before { changed(immediately: restarted || toggled) }  // frozen while stopped, so no redraws then
    }

    /// Asks the view to redraw for new readings, at most once per the Refresh setting.
    private func changed(immediately: Bool = false) {
        let wait = UserDefaults.standard.double(forKey: Self.refreshKey) - Date().timeIntervalSince(lastRedraw)
        if immediately || wait <= 0 { return redraw() }
        guard !redrawPending else { return }
        redrawPending = true
        // Only scheduled when a reading arrived, so nothing fires while idle.
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.redraw() }
    }

    private func redraw() {
        redrawPending = false
        lastRedraw = Date()
        objectWillChange.send()
    }

    private var summary: String {
        String(format: "%.2fs, avg %d W", pm5.elapsed ?? 0, pm5.averageWatts ?? 0)
    }

    /// Call periodically; drops `live` once data stops arriving. Only publishes on change.
    func expireStale(now: Date = Date()) {
        if live, let last = lastUpdate, now.timeIntervalSince(last) > 3 {
            log.info("Data stopped")
            live = false
        }
    }
}


/// Connection state, from Bluetooth availability through to a subscribed power source.
enum Link: Equatable {
    case starting
    case bluetoothOff, unauthorized, unavailable
    case scanning(lostConnection: Bool)
    case connecting(name: String)
    case connected(name: String, source: String)  // source: "Cycling Power", "FTMS", "PM5" or "Simulated"
    case paused(reason: String)  // short: "Idle", "Off", "Not found", "Couldn't connect"…

    var message: String {
        switch self {
        case .starting: "Starting…"
        case .bluetoothOff: "Bluetooth is off"
        case .unauthorized: "Allow Bluetooth in System Settings › Privacy"
        case .unavailable: "Bluetooth unavailable"
        case .scanning(let lost): lost ? "Connection lost · reconnecting…" : "Scanning… wake the PM5"
        case .connecting(let name): "Connecting to \(name)…"
        case .connected(let name, let source): "\(name) · \(source)"
        case .paused(let reason): "\(reason) · click to connect"
        }
    }

    var isSearching: Bool {
        switch self {
        case .scanning, .connecting: true
        default: false
        }
    }
}

/// Where readings come from: the real bike, or simulated data.
protocol PowerSource: AnyObject {
    func resume()
    func pause(_ reason: String)
}
