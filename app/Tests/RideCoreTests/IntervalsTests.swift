import Testing
@testable import RideCore

// The workout: 8 × 20 s work / 20 s rest, 175 W / 75 W.

@Test func phasesFollowTheClock() throws {
    let intervals = Intervals.workout
    let start = try #require(intervals.phase(at: 0))
    #expect(start.isWork && start.round == 1 && start.target == 175 && start.remaining(at: 0) == 20)

    let rest = try #require(intervals.phase(at: 20))
    #expect(!rest.isWork && rest.round == 1 && rest.target == 75 && rest.remaining(at: 20) == 20)

    let second = try #require(intervals.phase(at: 40))
    #expect(second.isWork && second.round == 2)

    let last = try #require(intervals.phase(at: 319.9))
    #expect(!last.isWork && last.round == 8)

    #expect(intervals.phase(at: 320) == nil)
    #expect(intervals.phase(at: -1) == nil)
}

@Test func phasesInAWindow() {
    let intervals = Intervals.workout
    let slice = intervals.phases(from: 30, to: 70)
    #expect(slice.map(\.start) == [20, 40, 60])
    #expect(slice.map(\.isWork) == [false, true, false])

    #expect(intervals.phases(from: 310, to: 500).map(\.start) == [300])
    #expect(intervals.phases(from: 400, to: 500).isEmpty)
}

@Test func countdownTicksTheLastFiveSeconds() {
    let intervals = Intervals.workout
    #expect(intervals.countdown(from: 14.5, to: 15.2) == 5)
    #expect(intervals.countdown(from: 15.2, to: 15.9) == nil)  // between ticks
    #expect(intervals.countdown(from: 18.9, to: 19.1) == 1)
    #expect(intervals.countdown(from: 16.5, to: 18.5) == 2)  // skipped a packet: one click, the latest
    #expect(intervals.countdown(from: 16, to: 16) == nil)  // clock frozen while stopped
    #expect(intervals.countdown(from: 10, to: 11) == nil)  // too early
    #expect(intervals.countdown(from: 19.5, to: 20.2) == nil)  // crossed into rest
    #expect(intervals.countdown(from: 314.9, to: 315.1) == 5)  // before the end of the workout too
}

@Test func tallySummarisesEachPhase() throws {
    var tally = IntervalTally(.workout)
    let firstChange = tally.advance(to: 0.5)
    let first = try #require(firstChange)
    #expect(first.finished == nil && first.entered?.isWork == true && first.crossed)

    for w in [160, 180, 190, 150] { tally.add(watts: w, cadence: 80) }
    #expect(tally.advance(to: 10) == nil)  // same phase

    let toRestChange = tally.advance(to: 20.4)
    let toRest = try #require(toRestChange)
    #expect(toRest.crossed && toRest.entered?.isWork == false)
    let work = try #require(toRest.finished)
    #expect(work.averageWatts == 170 && work.peakWatts == 190 && work.onTarget == 0.5)
    #expect(work.averageCadence == 80 && work.seconds == 19.5)  // counted from 0.5 s, when the tally joined
}

@Test func joiningMidPhaseIsSilentAndPartial() throws {
    var tally = IntervalTally(.workout)
    let joinChange = tally.advance(to: 30)
    let join = try #require(joinChange)  // reconnected during round 1's rest
    #expect(!join.crossed)
    tally.add(watts: 80, cadence: nil)
    let nextChange = tally.advance(to: 40.5)
    let next = try #require(nextChange)
    #expect(next.crossed)
    #expect(next.finished?.seconds == 10)
    #expect(next.finished?.averageCadence == nil)
}

@Test func tallyReportsTheWholeWorkout() throws {
    var tally = IntervalTally(.workout)
    for round in 0..<8 {
        let t = Double(round) * 40
        _ = tally.advance(to: t)
        tally.add(watts: 185 - round * 5, cadence: nil)  // fading: 185 … 150
        _ = tally.advance(to: t + 20)
        tally.add(watts: 80, cadence: nil)
    }
    let doneChange = tally.advance(to: 320.5)
    let done = try #require(doneChange)
    #expect(done.entered == nil && done.crossed && done.finished?.phase.round == 8)
    #expect(tally.report.contains("work avg by round 185 180 175 170 165 160 155 150 W"))
    #expect(tally.report.contains("3/8 work intervals averaged ≥ 175 W"))
    #expect(tally.report.contains("rest avg 80 W"))
}
