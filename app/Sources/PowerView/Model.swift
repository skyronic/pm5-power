import Foundation
import os
import PowerProtocol
import RideCore

private let log = Logger(subsystem: "pm5-power", category: "ride")

/// Live state shown in the window. All mutation happens on the main thread.
///
/// Readings (power, cadence, ride, PM5 status) redraw at most once per the Refresh setting, via `changed()`.
/// Everything else — connection state, stopping and resuming, new rides — redraws immediately.
final class Model: ObservableObject {
    static let refreshKey = "refresh"  // seconds between redraws for readings; 0 = every reading

    private(set) var watts: Int?
    private(set) var cadence: Double?
    private(set) var avg3: Double?
    @Published var live = false  // data arrived in the last 3s
    @Published var link = Link.starting
    @Published var lastError: String?  // most recent Bluetooth error, shown in the menu
    @Published var idleDisconnectIn: Int?  // seconds; only set in the last minute before an idle disconnect
    private(set) var ride = Ride()
    /// The PM5's own clock, average and rowing state; shown as is when present. Nil when not arriving.
    private(set) var pm5: WorkoutStatus?
    private var pm5Update: Date?
    private var pm5Elapsed: Double?  // survives going stale, to spot a new workout after a reconnect
    var paused: Bool { if case .paused = link { true } else { false } }  // disconnected on purpose; click to reconnect
    var lastUpdate: Date?
    var lastPedal: Date?  // last non-zero power reading

    private var samples: [(Date, Int)] = []
    private var lastRedraw = Date.distantPast
    private var redrawPending = false

    func update(_ r: Reading) {
        let now = Date()
        if !live {
            let gap = lastUpdate.map { String(format: " after %.1fs gap", now.timeIntervalSince($0)) } ?? ""
            log.info("Data arriving\(gap, privacy: .public)")
        }
        let before = (ride.started, ride.isPaused)
        if let cadence = r.cadence { self.cadence = cadence }
        if let watts = r.watts {
            self.watts = watts
            if watts > 0 { lastPedal = now }
            samples.append((now, watts))
            samples.removeAll { now.timeIntervalSince($0.0) > 3 }
            avg3 = Double(samples.map(\.1).reduce(0, +)) / Double(samples.count)
            ride.add(watts: watts, at: now)
        }
        lastUpdate = now
        if !live { live = true }
        changed(immediately: logRideChange(from: before))
    }

    /// Merges one Concept2 status packet; each carries the elapsed time plus some of the other fields.
    func updateStatus(_ s: WorkoutStatus) {
        // The PM5 clock going backwards means a new workout was started on the monitor.
        if let last = pm5Elapsed, s.elapsed < last - 2 {
            log.info("PM5 workout restarted (\(last, format: .fixed(precision: 2))s → \(s.elapsed, format: .fixed(precision: 2))s)")
            newRide()
            pm5 = nil  // don't carry the old workout's average over
        }
        var next = pm5 ?? WorkoutStatus(elapsed: s.elapsed)
        next.elapsed = s.elapsed
        // Right after connecting, the PM5 sends a few packets with the average zeroed. A real
        // workout average can't fall back to 0 once it's positive, so keep the last one.
        if let a = s.averageWatts, a > 0 || (next.averageWatts ?? 0) == 0 { next.averageWatts = a }
        var toggled = false
        if let a = s.active {
            if let was = next.active, was != a {
                log.info("PM5 \(a ? "active" : "stopped", privacy: .public): \(self.summary, privacy: .public)")
                toggled = true
            }
            next.active = a
        }
        pm5Elapsed = s.elapsed
        pm5Update = Date()
        if next != pm5 {  // frozen while stopped, so no redraws then
            pm5 = next
            changed(immediately: toggled)
        }
    }

    /// Asks the view to redraw for new readings, at most once per the Refresh setting.
    /// Stopping, resuming and resets pass `immediately` so they never lag.
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

    func newRide() {
        log.info("New ride; previous: \(self.summary, privacy: .public)")
        ride = Ride()
        changed(immediately: true)
    }

    private var summary: String {
        var s = String(format: "app %.0fs moving, avg %.0f W", ride.movingTime, ride.averageWatts ?? 0)
        if let pm5 { s += String(format: "; PM5 %.2fs, avg %d W", pm5.elapsed, pm5.averageWatts ?? 0) }
        return s
    }

    /// `before` is (started, isPaused); just the flags, so the trace isn't copied on every sample.
    /// Returns true if the ride started, paused or resumed.
    @discardableResult
    private func logRideChange(from before: (Bool, Bool)) -> Bool {
        if !before.0, ride.started { log.info("Ride started") }
        if before.1 != ride.isPaused {
            log.info("Ride \(self.ride.isPaused ? "auto-paused" : "resumed", privacy: .public): \(self.summary, privacy: .public)")
        }
        return before != (ride.started, ride.isPaused)
    }

    /// Call periodically; drops `live` and pauses the ride once data stops arriving.
    /// Only publishes when something changes, so idle ticks don't redraw.
    func expireStale(now: Date = Date()) {
        if live, let last = lastUpdate, now.timeIntervalSince(last) > 3 {
            log.info("Data stopped")
            live = false
        }
        if pm5 != nil, let last = pm5Update, now.timeIntervalSince(last) > 3 {
            log.info("PM5 status stopped")
            pm5 = nil
            changed(immediately: true)
        }
        if ride.started, !ride.isPaused {
            var r = ride
            if r.checkPause(now: now) {
                let before = (ride.started, ride.isPaused)
                ride = r
                logRideChange(from: before)
                changed(immediately: true)
            }
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
