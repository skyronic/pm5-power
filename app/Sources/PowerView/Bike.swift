import CoreBluetooth
import os
import PowerProtocol

private let cpsService = CBUUID(string: GATT.cyclingPowerService)
private let cpsMeasurement = CBUUID(string: GATT.cyclingPowerMeasurement)
private let ftmsService = CBUUID(string: GATT.ftmsService)
private let ftmsBikeData = CBUUID(string: GATT.ftmsIndoorBikeData)
private let c2Rowing = CBUUID(string: GATT.c2RowingService)
private let c2General = CBUUID(string: GATT.c2GeneralStatus)
private let c2Status1 = CBUUID(string: GATT.c2AdditionalStatus1)
private let c2Status2 = CBUUID(string: GATT.c2AdditionalStatus2)
private let c2StrokeData = CBUUID(string: GATT.c2AdditionalStrokeData)

/// Watch with: log stream --predicate 'subsystem == "pm5-power"' --level debug
private let log = Logger(subsystem: "pm5-power", category: "bike")

/// Finds a PM5 over Bluetooth LE, subscribes to the best power source it offers, and feeds the model.
///
/// Battery: an open connection keeps the PM5 awake indefinitely and keeps the Mac's radio busy,
/// so we disconnect after `idleTimeout` without pedalling (`endedTimeout` once the workout is over), stop scanning after `scanTimeout`,
/// and give up on a connection attempt after `connectTimeout` (CoreBluetooth never times out on its own).
final class Bike: NSObject, PowerSource, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let idleTimeout: TimeInterval = 5 * 60
    static let endedTimeout: TimeInterval = 2 * 60  // once the PM5 is out of a workout, so it can go to sleep
    static let scanTimeout: TimeInterval = 2 * 60
    static let connectTimeout: TimeInterval = 15
    static let idleWarning: TimeInterval = 60
    static let rawSamplesLogged = 5
    /// Dogfooding: discover every service, read everything readable, subscribe to everything that
    /// notifies, and log every payload. Costs extra radio time while connected; turn off before publishing.
    static let diagnostics = false

    let model: Model
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var chars: [CBUUID: CBCharacteristic] = [:]
    private var active: Set<CBUUID> = []  // the characteristics feeding the model
    private var pendingServices = 0
    private var crank: CrankState?
    private var scanStarted: Date?
    private var connectStarted: Date?
    private var connectedAt: Date?
    private var pauseReason: String?  // kept apart from model.link so it survives Bluetooth turning off and on
    private var rawLogged: [CBUUID: Int] = [:]

    init(model: Model) {
        self.model = model
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
    }

    func scan(lostConnection: Bool = false) {
        guard pauseReason == nil, central.state == .poweredOn else { return }
        log.info("Scanning (lost connection: \(lostConnection))")
        model.link = .scanning(lostConnection: lostConnection)
        scanStarted = Date()
        central.scanForPeripherals(withServices: nil)
    }

    func pause(_ reason: String) {
        log.info("Paused: \(reason, privacy: .public)")
        pauseReason = reason
        model.link = .paused(reason: reason)
        scanStarted = nil
        connectStarted = nil
        setIdleWarning(nil)
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    func resume() {
        guard pauseReason != nil else { return }
        pauseReason = nil
        model.lastError = nil
        scan()
    }

    /// Records an error for the menu and pauses with a short reason for the status line.
    private func fail(_ reason: String, _ error: Error?) {
        if let error {
            log.error("\(reason, privacy: .public): \(error.localizedDescription, privacy: .public)")
            model.lastError = error.localizedDescription
        }
        pause(reason)
    }

    private func tick() {
        let now = Date()
        model.expireStale(now: now)
        if let start = scanStarted, central.isScanning, now.timeIntervalSince(start) > Self.scanTimeout {
            pause("Not found")
        }
        if let start = connectStarted, now.timeIntervalSince(start) > Self.connectTimeout {
            pause("Couldn't connect")
        }
        if let p = peripheral, p.state == .connected,
           let since = [model.lastPedal, connectedAt, model.workoutEnded].compactMap({ $0 }).max() {
            let timeout = model.pm5.inWorkout == false ? Self.endedTimeout : Self.idleTimeout
            let left = timeout - now.timeIntervalSince(since)
            if left <= 0 {
                pause("Idle")
            } else {
                setIdleWarning(left <= Self.idleWarning ? Int(left.rounded(.up)) : nil)
            }
        }
    }

    /// Publishes only on change, so the view doesn't redraw every tick while idle.
    private func setIdleWarning(_ seconds: Int?) {
        if model.idleDisconnectIn == nil, seconds != nil { log.info("Idle; disconnecting in \(Int(Self.idleWarning))s") }
        if model.idleDisconnectIn != seconds { model.idleDisconnectIn = seconds }
    }

    // MARK: Central

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        log.info("Bluetooth state: \(c.state.rawValue)")
        switch c.state {
        case .poweredOn:
            if let reason = pauseReason { model.link = .paused(reason: reason) } else { scan() }
            return
        case .unauthorized: model.link = .unauthorized
        case .poweredOff: model.link = .bluetoothOff
        default: model.link = .unavailable
        }
        // Connections and scans are gone once the radio is off.
        peripheral = nil
        scanStarted = nil
        connectStarted = nil
        model.live = false
        setIdleWarning(nil)
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = ((ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "").uppercased()
        let uuids = Set(ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
        guard name.hasPrefix("PM5") || name.contains("CONCEPT2")
            || !uuids.isDisjoint(with: [cpsService, ftmsService, c2Rowing]) else { return }
        log.info("Found \(name, privacy: .public) rssi \(rssi.intValue) dBm, advertising \(uuids.map(\.uuidString).sorted(), privacy: .public)")
        c.stopScan()
        scanStarted = nil
        connectStarted = Date()
        peripheral = p
        model.link = .connecting(name: p.name ?? "PM5")
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        log.info("Connected to \(p.name ?? "?", privacy: .public)")
        p.delegate = self
        connectStarted = nil
        connectedAt = Date()
        chars = [:]
        active = []
        crank = nil
        rawLogged = [:]
        p.discoverServices(Self.diagnostics ? nil : [cpsService, ftmsService, c2Rowing])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        fail("Couldn't connect", error)
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log.info("Disconnected\(error.map { ": \($0.localizedDescription)" } ?? "", privacy: .public)")
        if let error { model.lastError = error.localizedDescription }
        model.live = false
        setIdleWarning(nil)
        scan(lostConnection: true)  // only rescans after an unexpected drop; no-op when paused
    }

    // MARK: Peripheral

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        let services = p.services ?? []
        log.info("Services: \(services.map(\.uuid.uuidString), privacy: .public)")
        guard error == nil, !services.isEmpty else {
            return fail("No power data on \(p.name ?? "device")", error)
        }
        pendingServices = services.count
        services.forEach { p.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        if let error { log.error("Characteristics of \(s.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)") }
        for ch in s.characteristics ?? [] {
            log.info("\(s.uuid.uuidString, privacy: .public) › \(ch.uuid.uuidString, privacy: .public) [\(describe(ch.properties), privacy: .public)]")
            chars[ch.uuid] = ch
        }
        pendingServices -= 1
        guard pendingServices == 0 else { return }

        // Priority: standard Cycling Power, then FTMS, then Concept2's proprietary service.
        let (mode, subs): (String, [CBUUID]) =
            chars[cpsMeasurement] != nil ? ("Cycling Power", [cpsMeasurement])
            : chars[ftmsBikeData] != nil ? ("FTMS", [ftmsBikeData])
            : chars[c2StrokeData] != nil ? ("PM5", [c2StrokeData, c2Status1])
            : ("", [])
        guard !subs.isEmpty else {
            return fail("No power data on \(p.name ?? "device")", nil)
        }
        log.info("Using \(mode, privacy: .public)")
        active = Set(subs)
        subs.compactMap { chars[$0] }.forEach { p.setNotifyValue(true, for: $0) }
        // The PM5's own clock, average and rowing state, whichever source supplies power.
        let status = [c2General, c2Status2].compactMap { chars[$0] }
        status.forEach { p.setNotifyValue(true, for: $0) }
        model.link = .connected(name: p.name ?? "PM5", source: mode)

        if Self.diagnostics {
            for ch in chars.values {
                if ch.properties.contains(.read) { p.readValue(for: ch) }
                if !active.contains(ch.uuid), !status.contains(ch),
                   !ch.properties.isDisjoint(with: [.notify, .indicate]) {
                    p.setNotifyValue(true, for: ch)
                }
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let error, active.contains(ch.uuid) {
            fail("Couldn't subscribe", error)
        } else if let error {
            log.error("Subscribe \(ch.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            log.info("Subscribed to \(ch.uuid.uuidString, privacy: .public)")
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if let error {
            log.error("Read \(ch.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        guard let value = ch.value else { return }
        let d = [UInt8](value)
        // Only the chosen source feeds the model; in diagnostics mode the rest are just logged.
        let reading: Reading? = switch active.contains(ch.uuid) ? ch.uuid : nil {
        case cpsMeasurement: Decode.cyclingPower(d, crank: &crank)
        case ftmsBikeData: Decode.indoorBikeData(d)
        case c2StrokeData: Decode.c2AdditionalStrokeData(d)
        case c2Status1: Decode.c2AdditionalStatus1(d)
        default: nil
        }
        let status: WorkoutStatus? = switch ch.uuid {
        case c2General: Decode.c2GeneralStatus(d)
        case c2Status2: Decode.c2AdditionalStatus2(d)
        default: nil
        }
        // Raw payloads, to check the decoders against a real PM5: all of them in diagnostics mode, else a few.
        let n = rawLogged[ch.uuid, default: 0]
        if Self.diagnostics || n < Self.rawSamplesLogged {
            rawLogged[ch.uuid] = n + 1
            let hex = d.map { String(format: "%02x", $0) }.joined(separator: " ")
            // One-off reads (Device Information etc.) are often text.
            let text = ch.isNotifying ? "" : String(bytes: d, encoding: .utf8).map { " \"\($0)\"" } ?? ""
            let decoded = (reading.map { " → \($0)" } ?? "") + (status.map { " → \($0)" } ?? "")
            log.debug("\(ch.uuid.uuidString, privacy: .public) [\(hex, privacy: .public)]\(text, privacy: .public)\(decoded, privacy: .public)")
        }
        if let reading { model.update(reading) }
        if let status { model.updateStatus(status) }
    }
}

private func describe(_ props: CBCharacteristicProperties) -> String {
    let names: [(CBCharacteristicProperties, String)] = [
        (.read, "read"), (.write, "write"), (.writeWithoutResponse, "writeNoResponse"),
        (.notify, "notify"), (.indicate, "indicate"),
    ]
    return names.filter { props.contains($0.0) }.map(\.1).joined(separator: ",")
}
