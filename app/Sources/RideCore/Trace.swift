/// The power trace behind the chart, keyed by the PM5's workout clock.
///
/// The clock freezes while the rider is stopped, so stops take no room on the chart.
public struct Trace: Sendable {
    public struct Point: Equatable, Sendable {
        public var time: Double  // PM5 elapsed seconds
        public var watts: Int
    }

    public private(set) var points: [Point] = []

    public init() {}

    /// Power readings and the clock arrive separately, about once a second each; a reading at an
    /// unchanged clock replaces the last point rather than stacking up.
    public mutating func add(watts: Int, at time: Double) {
        if let last = points.last, time <= last.time {
            points[points.count - 1].watts = watts
        } else {
            points.append(Point(time: time, watts: watts))
        }
    }
}
