import Testing
@testable import RideCore

@Test func appendsAsTheClockAdvances() {
    var trace = Trace()
    trace.add(watts: 100, at: 10)
    trace.add(watts: 150, at: 11)
    #expect(trace.points.map(\.time) == [10, 11])
    #expect(trace.points.map(\.watts) == [100, 150])
}

@Test func frozenClockReplacesTheLastPoint() {
    var trace = Trace()
    trace.add(watts: 100, at: 10)
    trace.add(watts: 120, at: 10)  // two readings within one clock tick
    trace.add(watts: 0, at: 10)  // stopped: clock frozen
    trace.add(watts: 0, at: 10)
    trace.add(watts: 200, at: 11)  // resumed
    #expect(trace.points.map(\.time) == [10, 11])
    #expect(trace.points.map(\.watts) == [0, 200])
}
