import CoreBluetooth
import PowerProtocol

private let cpsService = CBUUID(string: GATT.cyclingPowerService)
private let cpsMeasurement = CBUUID(string: GATT.cyclingPowerMeasurement)
private let ftmsService = CBUUID(string: GATT.ftmsService)
private let ftmsBikeData = CBUUID(string: GATT.ftmsIndoorBikeData)
private let c2Rowing = CBUUID(string: GATT.c2RowingService)
private let c2Status1 = CBUUID(string: GATT.c2AdditionalStatus1)
private let c2StrokeData = CBUUID(string: GATT.c2AdditionalStrokeData)

/// Finds a PM5 over Bluetooth LE, subscribes to the best power source it offers, and feeds the model.
///
/// Battery: an open connection keeps the PM5 awake indefinitely and keeps the Mac's radio busy,
/// so we disconnect after `idleTimeout` without pedalling and stop scanning after `scanTimeout`.
final class Bike: NSObject, PowerSource, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let idleTimeout: TimeInterval = 5 * 60
    static let scanTimeout: TimeInterval = 2 * 60

    let model: Model
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var chars: [CBUUID: CBCharacteristic] = [:]
    private var pendingServices = 0
    private var crank: CrankState?
    private var scanStarted: Date?
    private var connectedAt: Date?

    init(model: Model) {
        self.model = model
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
    }

    func scan() {
        guard !model.paused, central.state == .poweredOn else { return }
        model.status = "Scanning… wake the PM5"
        scanStarted = Date()
        central.scanForPeripherals(withServices: nil)
    }

    func pause(_ reason: String) {
        model.paused = true
        model.status = "\(reason) · click to connect"
        scanStarted = nil
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    func resume() {
        guard model.paused else { return }
        model.paused = false
        scan()
    }

    private func tick() {
        let now = Date()
        model.expireStale(now: now)
        if let start = scanStarted, central.isScanning, now.timeIntervalSince(start) > Self.scanTimeout {
            pause("Not found")
        }
        if let p = peripheral, p.state == .connected,
           let since = [model.lastPedal, connectedAt].compactMap({ $0 }).max(),
           now.timeIntervalSince(since) > Self.idleTimeout {
            pause("Idle")
        }
    }

    // MARK: Central

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: scan()
        case .unauthorized: model.status = "Allow Bluetooth in System Settings › Privacy"
        case .poweredOff: model.status = "Bluetooth is off"
        default: model.status = "Bluetooth unavailable"
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = ((ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "").uppercased()
        let uuids = Set(ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
        guard name.hasPrefix("PM5") || name.contains("CONCEPT2")
            || !uuids.isDisjoint(with: [cpsService, ftmsService, c2Rowing]) else { return }
        c.stopScan()
        scanStarted = nil
        peripheral = p
        model.status = "Connecting to \(p.name ?? "PM5")…"
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.delegate = self
        connectedAt = Date()
        chars = [:]
        crank = nil
        p.discoverServices([cpsService, ftmsService, c2Rowing])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { scan() }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        model.live = false
        scan()  // only rescans after an unexpected drop; no-op when paused
    }

    // MARK: Peripheral

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        let services = p.services ?? []
        pendingServices = services.count
        services.forEach { p.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        s.characteristics?.forEach { chars[$0.uuid] = $0 }
        pendingServices -= 1
        guard pendingServices == 0 else { return }

        // Priority: standard Cycling Power, then FTMS, then Concept2's proprietary service.
        let (mode, subs): (String, [CBUUID]) =
            chars[cpsMeasurement] != nil ? ("Cycling Power", [cpsMeasurement])
            : chars[ftmsBikeData] != nil ? ("FTMS", [ftmsBikeData])
            : chars[c2StrokeData] != nil ? ("PM5", [c2StrokeData, c2Status1])
            : ("", [])
        guard !subs.isEmpty else {
            model.status = "No power data on \(p.name ?? "device")"
            central.cancelPeripheralConnection(p)
            return
        }
        subs.compactMap { chars[$0] }.forEach { p.setNotifyValue(true, for: $0) }
        model.status = "\(p.name ?? "PM5") · \(mode)"
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let value = ch.value else { return }
        let d = [UInt8](value)
        let reading: Reading? = switch ch.uuid {
        case cpsMeasurement: Decode.cyclingPower(d, crank: &crank)
        case ftmsBikeData: Decode.indoorBikeData(d)
        case c2StrokeData: Decode.c2AdditionalStrokeData(d)
        case c2Status1: Decode.c2AdditionalStatus1(d)
        default: nil
        }
        if let reading { model.update(reading) }
    }
}
