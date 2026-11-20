/// A fixed work/rest interval workout, timed by the PM5's workout clock.
///
/// The clock freezes while the rider is stopped, so the intervals pause with it.
public struct Intervals: Sendable {
    public var work: Double = 20  // seconds
    public var rest: Double = 20
    public var rounds = 8
    public var workWatts = 175
    public var restWatts = 75

    /// The one workout for now: 8 × 20 s work / 20 s rest (Tabata-style, with a longer rest).
    public static let workout = Intervals()

    public init() {}

    public struct Phase: Equatable, Sendable {
        public var isWork: Bool
        public var round: Int  // 1-based
        public var start: Double  // PM5 elapsed seconds
        public var end: Double
        public var target: Int
        public func remaining(at elapsed: Double) -> Double { end - elapsed }
    }

    public var duration: Double { Double(rounds) * (work + rest) }

    /// The phase the clock is in; nil before it starts and once all rounds are done.
    public func phase(at elapsed: Double) -> Phase? {
        guard elapsed >= 0, elapsed < duration else { return nil }
        let length = work + rest
        let index = Int(elapsed / length)
        let roundStart = Double(index) * length
        return elapsed - roundStart < work
            ? workPhase(index, roundStart)
            : restPhase(index, roundStart)
    }

    /// The countdown second (5…1 before the current phase ends) that the clock passed going from
    /// `previous` to `elapsed`, if any. A frozen clock passes nothing, so the countdown pauses too.
    public func countdown(from previous: Double, to elapsed: Double) -> Int? {
        guard let phase = phase(at: elapsed) else { return nil }
        return (1...5).first { k in
            let tick = phase.end - Double(k)
            return tick > phase.start && previous < tick && tick <= elapsed
        }
    }

    /// Every phase overlapping `from...to`, in order.
    public func phases(from: Double, to: Double) -> [Phase] {
        let length = work + rest
        let first = max(0, Int(from / length))
        let last = min(rounds - 1, Int(to / length))
        guard first <= last else { return [] }
        return (first...last)
            .flatMap { i in [workPhase(i, Double(i) * length), restPhase(i, Double(i) * length)] }
            .filter { $0.end > from && $0.start < to }
    }

    private func workPhase(_ index: Int, _ start: Double) -> Phase {
        Phase(isWork: true, round: index + 1, start: start, end: start + work, target: workWatts)
    }

    private func restPhase(_ index: Int, _ start: Double) -> Phase {
        Phase(isWork: false, round: index + 1, start: start + work, end: start + work + rest, target: restWatts)
    }
}
