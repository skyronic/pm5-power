import Testing
@testable import PowerProtocol

@Test func cyclingPowerWithCrankCadence() {
    var crank: CrankState?
    // flags 0x20 (crank data), 200 W, 10 revs at t=1024 (1 s)
    let first = Decode.cyclingPower([0x20, 0x00, 0xC8, 0x00, 10, 0, 0x00, 0x04], crank: &crank)
    #expect(first == Reading(watts: 200, cadence: nil))
    // 11 revs at t=1877: 1 rev in 853/1024 s ≈ 72 rpm
    let second = Decode.cyclingPower([0x20, 0x00, 0xC8, 0x00, 11, 0, 0x55, 0x07], crank: &crank)
    #expect(second?.watts == 200)
    #expect(abs((second?.cadence ?? 0) - 72.03) < 0.01)
}

@Test func cyclingPowerCrankCountersWrap() {
    var crank: CrankState? = CrankState(revs: 0xFFFF, time: 0xFF00)
    let r = Decode.cyclingPower([0x20, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x03], crank: &crank)
    // 1 rev in (0x0300 - 0xFF00) & 0xFFFF = 1024 ticks = 1 s → 60 rpm
    #expect(r == Reading(watts: 100, cadence: 60))
}

@Test func cyclingPowerSkipsOptionalFields() {
    var crank: CrankState?
    // flags: balance (0x01) + torque (0x04) + wheel (0x10); power is still at bytes 2-3
    let d: [UInt8] = [0x15, 0x00, 0x2C, 0x01, 50, 0, 0, 1, 2, 3, 4, 5, 6]
    #expect(Decode.cyclingPower(d, crank: &crank) == Reading(watts: 300, cadence: nil))
}

@Test func indoorBikeDataSpeedCadencePower() {
    // flags 0x44: cadence + power, speed present (bit 0 clear)
    let d: [UInt8] = [0x44, 0x00, 0x10, 0x0E, 0xAA, 0x00, 0xFA, 0x00]
    #expect(Decode.indoorBikeData(d) == Reading(watts: 250, cadence: 85))
}

@Test func indoorBikeDataSkipsDistanceAndResistance() {
    // flags 0x0071: no speed (bit 0 set), distance (3 bytes), resistance (2 bytes), power
    let d: [UInt8] = [0x71, 0x00, 1, 2, 3, 4, 5, 0x96, 0x00]
    #expect(Decode.indoorBikeData(d) == Reading(watts: 150, cadence: nil))
}

@Test func concept2Payloads() {
    #expect(Decode.c2AdditionalStrokeData([0, 0, 0, 0xF4, 0x01, 0, 0]) == Reading(watts: 500))
    #expect(Decode.c2AdditionalStatus1([0, 0, 0, 0, 0, 88, 255]) == Reading(cadence: 88))
}

@Test func shortPayloadsAreRejected() {
    var crank: CrankState?
    #expect(Decode.cyclingPower([0x00, 0x00, 0x01], crank: &crank) == nil)
    #expect(Decode.indoorBikeData([0x00]) == nil)
    #expect(Decode.c2AdditionalStrokeData([0, 0, 0, 1]) == nil)
    #expect(Decode.c2AdditionalStatus1([0, 0, 0, 0, 0]) == nil)
}
