// GATT identifiers and payload decoders for the Concept2 PM5.
// The PM5 may expose any of: Cycling Power, FTMS, or Concept2's own rowing service.
// Concept2 spec: "PM5 Bluetooth Smart Communication Interface Definition".

public enum GATT {
    public static let cyclingPowerService = "1818"
    public static let cyclingPowerMeasurement = "2A63"
    public static let ftmsService = "1826"
    public static let ftmsIndoorBikeData = "2AD2"

    public static func c2(_ short: String) -> String { "CE06\(short)-43E5-11E4-916C-0800200C9A66" }
    public static let c2RowingService = c2("0030")
    public static let c2GeneralStatus = c2("0031")  // bytes 0-2: elapsed time; byte 9: rowing state
    public static let c2AdditionalStatus1 = c2("0032")  // byte 5: stroke rate (= cadence on BikeErg)
    public static let c2AdditionalStatus2 = c2("0033")  // bytes 0-2: elapsed time; bytes 4-5: average power (W)
    public static let c2AdditionalStrokeData = c2("0036")  // bytes 3-4: stroke power (W)
}

/// One decoded notification. Either field may be absent depending on the source.
public struct Reading: Equatable, Sendable {
    public var watts: Int?
    public var cadence: Double?

    public init(watts: Int? = nil, cadence: Double? = nil) {
        self.watts = watts
        self.cadence = cadence
    }
}

/// The PM5's own workout clock and totals, which the window shows as is.
/// Each Concept2 status characteristic carries part of it; absent fields are nil.
public struct WorkoutStatus: Equatable, Sendable {
    public var elapsed: Double  // seconds; freezes while the rider is stopped
    public var averageWatts: Int?
    public var active: Bool?  // rowing state: false while stopped

    public init(elapsed: Double, averageWatts: Int? = nil, active: Bool? = nil) {
        self.elapsed = elapsed
        self.averageWatts = averageWatts
        self.active = active
    }
}

/// Previous crank sample; Cycling Power only reports cumulative revolutions, so cadence needs a delta.
public struct CrankState: Equatable, Sendable {
    public var revs: Int
    public var time: Int  // 1/1024 s, wraps at 16 bits
}

func u16(_ d: [UInt8], _ i: Int) -> Int { Int(d[i]) | Int(d[i + 1]) << 8 }
func u24(_ d: [UInt8], _ i: Int) -> Int { u16(d, i) | Int(d[i + 2]) << 16 }
func s16(_ d: [UInt8], _ i: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(d, i)))) }

public enum Decode {
    /// Cycling Power Measurement (0x2A63).
    public static func cyclingPower(_ d: [UInt8], crank: inout CrankState?) -> Reading? {
        guard d.count >= 4 else { return nil }
        let flags = u16(d, 0)
        var i = 4
        if flags & 0x01 != 0 { i += 1 }  // pedal power balance
        if flags & 0x04 != 0 { i += 2 }  // accumulated torque
        if flags & 0x10 != 0 { i += 6 }  // wheel revolutions
        var cadence: Double?
        if flags & 0x20 != 0, d.count >= i + 4 {
            let now = CrankState(revs: u16(d, i), time: u16(d, i + 2))
            if let prev = crank {
                let dr = (now.revs - prev.revs) & 0xFFFF, dt = (now.time - prev.time) & 0xFFFF
                if dt > 0 { cadence = Double(dr) * 60 * 1024 / Double(dt) }
            }
            crank = now
        }
        return Reading(watts: s16(d, 2), cadence: cadence)
    }

    /// FTMS Indoor Bike Data (0x2AD2).
    public static func indoorBikeData(_ d: [UInt8]) -> Reading? {
        guard d.count >= 2 else { return nil }
        let flags = u16(d, 0)
        var i = 2
        var r = Reading()
        if flags & 0x0001 == 0 { i += 2 }  // instantaneous speed (present when "more data" is 0)
        if flags & 0x0002 != 0 { i += 2 }  // average speed
        if flags & 0x0004 != 0, d.count >= i + 2 { r.cadence = Double(u16(d, i)) / 2; i += 2 }
        if flags & 0x0008 != 0 { i += 2 }  // average cadence
        if flags & 0x0010 != 0 { i += 3 }  // total distance
        if flags & 0x0020 != 0 { i += 2 }  // resistance level
        if flags & 0x0040 != 0, d.count >= i + 2 { r.watts = s16(d, i) }
        return r
    }

    /// Concept2 Additional Stroke Data (CE060036): power for the last stroke / pedal revolution.
    public static func c2AdditionalStrokeData(_ d: [UInt8]) -> Reading? {
        d.count >= 5 ? Reading(watts: u16(d, 3)) : nil
    }

    /// Concept2 General Status (CE060031): elapsed time (0.01 s) and rowing state (0 = stopped).
    public static func c2GeneralStatus(_ d: [UInt8]) -> WorkoutStatus? {
        d.count >= 10 ? WorkoutStatus(elapsed: Double(u24(d, 0)) / 100, active: d[9] != 0) : nil
    }

    /// Concept2 Additional Status 2 (CE060033): elapsed time (0.01 s) and workout average power.
    public static func c2AdditionalStatus2(_ d: [UInt8]) -> WorkoutStatus? {
        d.count >= 6 ? WorkoutStatus(elapsed: Double(u24(d, 0)) / 100, averageWatts: u16(d, 4)) : nil
    }

    /// Concept2 Additional Status 1 (CE060032): stroke rate, which is cadence on the BikeErg.
    public static func c2AdditionalStatus1(_ d: [UInt8]) -> Reading? {
        d.count >= 6 ? Reading(cadence: Double(d[5])) : nil
    }
}
