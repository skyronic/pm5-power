// Small always-on-top wattage display for a Concept2 BikeErg (PM5) over Bluetooth LE.
// Same protocol logic as ../c2power.py: Cycling Power > FTMS > Concept2 PM5 service.

import AppKit
import CoreBluetooth
import SwiftUI

// MARK: - Model

final class Model: ObservableObject {
    @Published var watts: Int?
    @Published var cadence: Double?
    @Published var avg3: Double?
    @Published var live = false  // data arrived in the last 3s
    @Published var paused = false  // disconnected on purpose; click to reconnect
    @Published var status = "Starting…"
    var lastUpdate: Date?
    var lastPedal: Date?  // last non-zero power reading

    private var samples: [(Date, Int)] = []

    func update(watts: Int? = nil, cadence: Double? = nil) {
        let now = Date()
        if let cadence { self.cadence = cadence }
        if let watts {
            self.watts = watts
            if watts > 0 { lastPedal = now }
            samples.append((now, watts))
            samples.removeAll { now.timeIntervalSince($0.0) > 3 }
            avg3 = Double(samples.map(\.1).reduce(0, +)) / Double(samples.count)
        }
        lastUpdate = now
        if !live { live = true }
    }
}

// MARK: - Bluetooth

let cpsService = CBUUID(string: "1818")
let cpsMeasurement = CBUUID(string: "2A63")
let ftmsService = CBUUID(string: "1826")
let ftmsBikeData = CBUUID(string: "2AD2")
func c2(_ x: String) -> CBUUID { CBUUID(string: "CE06\(x)-43E5-11E4-916C-0800200C9A66") }
let c2Rowing = c2("0030")
let c2Status1 = c2("0032")  // byte 5: stroke rate (= cadence on BikeErg)
let c2Stroke2 = c2("0036")  // bytes 3-4: stroke power (W)

func u16(_ d: [UInt8], _ i: Int) -> Int { Int(d[i]) | Int(d[i + 1]) << 8 }
func s16(_ d: [UInt8], _ i: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(d, i)))) }

final class Bike: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let model: Model
    var central: CBCentralManager!
    var peripheral: CBPeripheral?
    var chars: [CBUUID: CBCharacteristic] = [:]
    var pendingServices = 0
    var crank: (revs: Int, time: Int)?
    var scanStarted: Date?
    var connectedAt: Date?

    static let idleTimeout: TimeInterval = 5 * 60  // disconnect after this long without pedalling
    static let scanTimeout: TimeInterval = 2 * 60

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

    func tick() {
        let now = Date()
        if model.live, let last = model.lastUpdate, now.timeIntervalSince(last) > 3 { model.live = false }
        if let start = scanStarted, central.isScanning, now.timeIntervalSince(start) > Self.scanTimeout {
            pause("Not found")
        }
        if let p = peripheral, p.state == .connected, let since = [model.lastPedal, connectedAt].compactMap({ $0 }).max(),
           now.timeIntervalSince(since) > Self.idleTimeout {
            pause("Idle")
        }
    }

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

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        let services = p.services ?? []
        pendingServices = services.count
        services.forEach { p.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        s.characteristics?.forEach { chars[$0.uuid] = $0 }
        pendingServices -= 1
        guard pendingServices == 0 else { return }

        let (mode, subs): (String, [CBUUID]) =
            chars[cpsMeasurement] != nil ? ("Cycling Power", [cpsMeasurement])
            : chars[ftmsBikeData] != nil ? ("FTMS", [ftmsBikeData])
            : chars[c2Stroke2] != nil ? ("PM5", [c2Stroke2, c2Status1])
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
        switch ch.uuid {
        case cpsMeasurement where d.count >= 4:
            let flags = u16(d, 0)
            var i = 4
            if flags & 0x01 != 0 { i += 1 }  // pedal power balance
            if flags & 0x04 != 0 { i += 2 }  // accumulated torque
            if flags & 0x10 != 0 { i += 6 }  // wheel revolutions
            var cadence: Double?
            if flags & 0x20 != 0, d.count >= i + 4 {
                let revs = u16(d, i), time = u16(d, i + 2)  // time in 1/1024 s
                if let prev = crank {
                    let dr = (revs - prev.revs) & 0xFFFF, dt = (time - prev.time) & 0xFFFF
                    if dt > 0 { cadence = Double(dr) * 60 * 1024 / Double(dt) }
                }
                crank = (revs, time)
            }
            model.update(watts: s16(d, 2), cadence: cadence)
        case ftmsBikeData where d.count >= 2:
            let flags = u16(d, 0)
            var i = 2
            var cadence: Double?, watts: Int?
            if flags & 0x0001 == 0 { i += 2 }  // instantaneous speed
            if flags & 0x0002 != 0 { i += 2 }  // average speed
            if flags & 0x0004 != 0, d.count >= i + 2 { cadence = Double(u16(d, i)) / 2; i += 2 }
            if flags & 0x0008 != 0 { i += 2 }  // average cadence
            if flags & 0x0010 != 0 { i += 3 }  // total distance
            if flags & 0x0020 != 0 { i += 2 }  // resistance level
            if flags & 0x0040 != 0, d.count >= i + 2 { watts = s16(d, i) }
            model.update(watts: watts, cadence: cadence)
        case c2Stroke2 where d.count >= 5:
            model.update(watts: u16(d, 3))
        case c2Status1 where d.count >= 6:
            model.update(cadence: Double(d[5]))
        default:
            break
        }
    }
}

// MARK: - View

struct PowerDisplay: View {
    @ObservedObject var model: Model
    var onResume: () -> Void
    var onPause: () -> Void
    @AppStorage("scale") var scale = 1.0
    @AppStorage("opacity") var opacity = 0.7
    @AppStorage("mainIsAverage") var mainIsAverage = false

    var body: some View {
        let live = model.live
        let main = mainIsAverage ? model.avg3.map { Int($0.rounded()) } : model.watts
        let other = mainIsAverage ? model.watts.map(Double.init) : model.avg3
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3 * scale) {
                Text(live ? main.map(String.init) ?? "---" : "---")
                    .font(.system(size: 52 * scale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("W")
                    .font(.system(size: 18 * scale, weight: .semibold, design: .rounded))
                    .opacity(0.6)
            }
            Text(live ? detail(other) : model.status)
                .font(.system(size: 11 * scale, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(0.6)
        }
        .foregroundStyle(.white)
        .frame(width: 150 * scale, height: 88 * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale).fill(.black.opacity(opacity)))
        .contextMenu { menu }
        .onTapGesture { onResume() }
    }

    func detail(_ other: Double?) -> String {
        let label = mainIsAverage ? "now" : "3s"
        let o = other.map { "\(Int($0.rounded()))W" } ?? "--"
        let c = model.cadence.map { "\(Int($0.rounded())) rpm" } ?? "-- rpm"
        return "\(label) \(o) · \(c)"
    }

    @ViewBuilder var menu: some View {
        if model.paused {
            Button("Reconnect") { onResume() }
        } else {
            Button("Disconnect") { onPause() }
        }
        Divider()
        Toggle("Show 3s Average as Main Number", isOn: $mainIsAverage)
        Picker("Size", selection: $scale) {
            Text("Small").tag(0.75)
            Text("Medium").tag(1.0)
            Text("Large").tag(1.5)
        }
        Picker("Background", selection: $opacity) {
            Text("Light").tag(0.4)
            Text("Medium").tag(0.7)
            Text("Solid").tag(0.95)
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var bike: Bike!
    var panel: NSPanel!

    func applicationDidFinishLaunching(_ n: Notification) {
        bike = Bike(model: model)
        let host = NSHostingController(rootView: PowerDisplay(
            model: model, onResume: { [unowned self] in bike.resume() },
            onPause: { [unowned self] in bike.pause("Off") }))
        host.sizingOptions = .preferredContentSize  // window follows the Size setting

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 150, height: 88),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentViewController = host
        panel.level = .statusBar
        // Accessory app + these behaviors let the window float over other apps' full-screen spaces.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        if !panel.setFrameUsingName("PowerWindow"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - 170, y: screen.maxY - 20))
        }
        panel.setFrameAutosaveName("PowerWindow")
        panel.orderFrontRegardless()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
