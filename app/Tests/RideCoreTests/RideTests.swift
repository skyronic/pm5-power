import Foundation
import Testing
@testable import RideCore

private let t0 = Date(timeIntervalSinceReferenceDate: 0)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@Test func startsOnFirstPedalStroke() {
    var ride = Ride()
    ride.add(watts: 0, at: at(0))
    #expect(!ride.started)
    ride.add(watts: 200, at: at(1))
    #expect(ride.started)
    #expect(ride.movingTime == 0)
    #expect(ride.averageWatts == nil)
}

@Test func averageIsTimeWeighted() {
    var ride = Ride()
    ride.add(watts: 100, at: at(0))
    ride.add(watts: 100, at: at(1))
    ride.add(watts: 300, at: at(4))  // 300 W for 3 s outweighs 100 W for 1 s
    #expect(ride.movingTime == 4)
    #expect(ride.averageWatts == 250)
}

@Test func briefZerosCountAsMovingAtZeroWatts() {
    var ride = Ride()
    ride.add(watts: 200, at: at(0))
    ride.add(watts: 200, at: at(1))
    ride.add(watts: 0, at: at(2))
    ride.add(watts: 200, at: at(3))
    #expect(!ride.isPaused)
    #expect(ride.movingTime == 3)
    #expect(ride.energy == 400)
}

@Test func autoPausesAndExcludesTheGap() {
    var ride = Ride()
    for s in stride(from: 0.0, through: 10, by: 1) { ride.add(watts: 200, at: at(s)) }
    for s in stride(from: 11.0, through: 60, by: 1) { ride.add(watts: 0, at: at(s)) }
    #expect(ride.isPaused)
    ride.add(watts: 100, at: at(61))
    #expect(!ride.isPaused)
    for s in stride(from: 62.0, through: 71, by: 1) { ride.add(watts: 100, at: at(s)) }
    #expect(ride.movingTime == 20)
    #expect(ride.averageWatts == 150)
}

@Test func pausesWhenReadingsStop() {
    var ride = Ride()
    ride.add(watts: 200, at: at(0))
    let early = ride.checkPause(now: at(Ride.pauseAfter))
    let late = ride.checkPause(now: at(Ride.pauseAfter + 1))
    let again = ride.checkPause(now: at(Ride.pauseAfter + 2))  // only reports the change once
    #expect(!early && late && !again)
    ride.add(watts: 200, at: at(100))  // reconnect much later: resumes without counting the gap
    #expect(!ride.isPaused)
    #expect(ride.movingTime == 0)
}

@Test func traceUsesMovingTime() {
    var ride = Ride()
    ride.add(watts: 100, at: at(0))
    ride.add(watts: 150, at: at(1))
    ride.add(watts: 0, at: at(10))
    ride.add(watts: 200, at: at(30))
    #expect(ride.trace.map(\.time) == [0, 1, 1])
    #expect(ride.trace.map(\.watts) == [100, 150, 200])
}
