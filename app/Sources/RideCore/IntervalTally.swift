import Foundation

/// Tallies power against the interval targets, one phase at a time, for the ride log.
///
/// `advance(to:)` follows the PM5's clock from phase to phase; `add` counts readings toward the
/// current phase. Readings while stopped shouldn't be added (the clock is frozen then anyway).
public struct IntervalTally: Sendable {
    public let intervals: Intervals
    public private(set) var phase: Intervals.Phase?
    public private(set) var completed: [Summary] = []
    private var watts: [Int] = []
    private var cadence: [Double] = []
    private var joined = 0.0  // clock when the current phase's tally began

    public init(_ intervals: Intervals) { self.intervals = intervals }

    public struct Summary: Equatable, Sendable, CustomStringConvertible {
        public var phase: Intervals.Phase
        public var rounds: Int
        public var averageWatts: Double
        public var peakWatts: Int
        public var onTarget: Double  // fraction of readings at or above target
        public var averageCadence: Double?
        public var seconds: Double  // of the phase actually seen; less than its length if joined late or ended early

        public var description: String {
            let rpm = averageCadence.map { String(format: ", %.0f rpm", $0) } ?? ""
            return String(format: "%@ %d/%d: avg %.0f W (target %d), peak %d W, %.0f%% of readings on target%@, %.0f s",
                          phase.isWork ? "Work" : "Rest", phase.round, rounds, averageWatts, phase.target, peakWatts,
                          onTarget * 100, rpm, seconds)
        }
    }

    public struct Change: Equatable, Sendable {
        public var finished: Summary?  // nil if no readings were counted
        public var entered: Intervals.Phase?  // nil once the workout is done
        public var crossed: Bool  // the clock just crossed a boundary, rather than joining mid-phase
    }

    /// Moves to the phase at this clock time; returns what changed, if the phase did.
    public mutating func advance(to elapsed: Double) -> Change? {
        let next = intervals.phase(at: elapsed)
        guard next != phase else { return nil }
        let boundary = next?.start ?? intervals.duration
        let finished = close(at: phase?.end ?? elapsed)
        phase = next
        joined = elapsed
        return Change(finished: finished, entered: next, crossed: elapsed >= boundary && elapsed - boundary < 3)
    }

    /// Ends the current phase early, e.g. when the PM5 leaves the workout.
    public mutating func finish(at elapsed: Double) -> Summary? {
        let s = close(at: elapsed)
        phase = nil
        return s
    }

    public mutating func add(watts w: Int, cadence c: Double?) {
        guard phase != nil else { return }
        watts.append(w)
        if let c { cadence.append(c) }
    }

    /// One line over the whole workout: work averages round by round show the fade.
    public var report: String {
        let work = completed.filter(\.phase.isWork)
        let rest = completed.filter { !$0.phase.isWork }
        let byRound = work.map { String(format: "%.0f", $0.averageWatts) }.joined(separator: " ")
        let hit = work.filter { $0.averageWatts >= Double($0.phase.target) }.count
        let restAvg = rest.isEmpty ? 0 : rest.map(\.averageWatts).reduce(0, +) / Double(rest.count)
        return String(format: "Intervals %.0fs/%.0fs × %d: work avg by round %@ W; %d/%d work intervals averaged ≥ %d W; rest avg %.0f W",
                      intervals.work, intervals.rest, intervals.rounds, byRound, hit, work.count,
                      intervals.workWatts, restAvg)
    }

    private mutating func close(at elapsed: Double) -> Summary? {
        defer { watts = []; cadence = [] }
        guard let phase, !watts.isEmpty else { return nil }
        let s = Summary(phase: phase, rounds: intervals.rounds,
                        averageWatts: Double(watts.reduce(0, +)) / Double(watts.count),
                        peakWatts: watts.max() ?? 0,
                        onTarget: Double(watts.filter { $0 >= phase.target }.count) / Double(watts.count),
                        averageCadence: cadence.isEmpty ? nil : cadence.reduce(0, +) / Double(cadence.count),
                        seconds: min(elapsed, phase.end) - max(joined, phase.start))
        completed.append(s)
        return s
    }
}
