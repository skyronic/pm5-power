import Foundation

/// One ride: moving time, average power and a power trace, with auto-pause.
///
/// The ride starts on the first non-zero power reading. If no non-zero power arrives for
/// `pauseAfter` seconds it auto-pauses, and that gap is left out of the time and average.
/// The next non-zero reading resumes it.
///
/// Time only advances when a reading arrives, so nothing needs to redraw on a timer.
public struct Ride: Sendable {
    public static let pauseAfter: TimeInterval = 4

    public struct Point: Equatable, Sendable {
        public var time: TimeInterval  // moving time into the ride
        public var watts: Int
    }

    public private(set) var movingTime: TimeInterval = 0
    public private(set) var energy: Double = 0  // joules
    public private(set) var isPaused = false
    public private(set) var trace: [Point] = []

    private var lastPedal: Date?  // last non-zero reading
    private var lastSample: Date?

    public init() {}

    public var started: Bool { lastPedal != nil }

    /// Time-weighted average over moving time.
    public var averageWatts: Double? { movingTime > 0 ? energy / movingTime : nil }

    public mutating func add(watts: Int, at now: Date) {
        defer { lastSample = now }
        guard let pedal = lastPedal, let sample = lastSample else {
            if watts > 0 { start(at: now, watts: watts) }
            return
        }
        guard watts > 0 else {
            checkPause(now: now)
            return
        }
        if isPaused || now.timeIntervalSince(pedal) > Self.pauseAfter {
            // Resuming: the gap since the last pedal stroke doesn't count.
            isPaused = false
        } else {
            // Zero readings since `pedal` count as moving time at 0 W; this one covers the last interval.
            movingTime += now.timeIntervalSince(pedal)
            energy += Double(watts) * now.timeIntervalSince(sample)
        }
        lastPedal = now
        trace.append(Point(time: movingTime, watts: watts))
    }

    /// Call when time passes without readings (e.g. the bike stopped sending). Returns true if this paused the ride.
    @discardableResult
    public mutating func checkPause(now: Date) -> Bool {
        guard !isPaused, let pedal = lastPedal, now.timeIntervalSince(pedal) > Self.pauseAfter else { return false }
        isPaused = true
        return true
    }

    private mutating func start(at now: Date, watts: Int) {
        lastPedal = now
        trace.append(Point(time: 0, watts: watts))
    }
}
