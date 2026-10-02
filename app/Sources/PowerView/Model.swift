import Foundation
import PowerProtocol

/// Live state shown in the window. All mutation happens on the main thread.
final class Model: ObservableObject {
    @Published var watts: Int?
    @Published var cadence: Double?
    @Published var avg3: Double?
    @Published var live = false  // data arrived in the last 3s
    @Published var paused = false  // disconnected on purpose; click to reconnect
    @Published var status = "Starting…"
    var lastUpdate: Date?
    var lastPedal: Date?  // last non-zero power reading

    private var samples: [(Date, Int)] = []

    func update(_ r: Reading) {
        let now = Date()
        if let cadence = r.cadence { self.cadence = cadence }
        if let watts = r.watts {
            self.watts = watts
            if watts > 0 { lastPedal = now }
            samples.append((now, watts))
            samples.removeAll { now.timeIntervalSince($0.0) > 3 }
            avg3 = Double(samples.map(\.1).reduce(0, +)) / Double(samples.count)
        }
        lastUpdate = now
        if !live { live = true }
    }

    /// Call periodically; drops `live` once data stops arriving.
    func expireStale(now: Date = Date()) {
        if live, let last = lastUpdate, now.timeIntervalSince(last) > 3 { live = false }
    }
}

/// Where readings come from: the real bike, or simulated data.
protocol PowerSource: AnyObject {
    func resume()
    func pause(_ reason: String)
}
