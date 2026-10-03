import Charts
import RideCore
import SwiftUI

private let pausedColor = Color(red: 1, green: 0.78, blue: 0.35)

struct PowerDisplay: View {
    @ObservedObject var model: Model
    let source: PowerSource
    @AppStorage("scale") var scale = 1.0
    @AppStorage("opacity") var opacity = 0.7
    @AppStorage("mainIsAverage") var mainIsAverage = false
    @State private var hovering = false

    static let size = CGSize(width: 220, height: 140)

    var body: some View {
        let live = model.live
        let main = mainIsAverage ? model.avg3.map { Int($0.rounded()) } : model.watts
        let other = mainIsAverage ? model.watts.map(Double.init) : model.avg3
        VStack(alignment: .leading, spacing: 2 * scale) {
            HStack(alignment: .center, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3 * scale) {
                    Text(live ? main.map(String.init) ?? "---" : "---")
                        .font(.system(size: 50 * scale, weight: .bold, design: .rounded))
                    Text("W")
                        .font(.system(size: 17 * scale, weight: .semibold, design: .rounded))
                        .opacity(0.6)
                }
                Spacer(minLength: 6 * scale)
                rideStats
            }
            HStack(spacing: 4 * scale) {
                Text(live ? detail(other) : model.status)
                    .font(.system(size: 11 * scale, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.6)
                Spacer(minLength: 0)
                newRideButton
            }
            PowerChart(ride: model.ride, scale: scale)
                .opacity(rolling ? 1 : 0.45)
        }
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 12 * scale)
        .padding(.top, 4 * scale)
        .padding(.bottom, 10 * scale)
        .frame(width: Self.size.width * scale, height: Self.size.height * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale).fill(.black.opacity(opacity)))
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .onTapGesture { source.resume() }
    }

    /// Ride clock is running: pedalling, and data is arriving.
    var rolling: Bool { model.live && model.ride.started && !model.ride.isPaused }

    var rideStats: some View {
        let ride = model.ride
        let paused = ride.started && !rolling
        return VStack(alignment: .trailing, spacing: 1 * scale) {
            HStack(spacing: 3 * scale) {
                if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11 * scale, weight: .bold))
                }
                Text(clock(ride.movingTime))
                    .font(.system(size: 20 * scale, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(paused ? pausedColor : .white)
            .opacity(ride.started ? 1 : 0.4)
            Text("avg \(ride.averageWatts.map { "\(Int($0.rounded()))" } ?? "--") W")
                .font(.system(size: 12 * scale, weight: .medium, design: .rounded))
                .opacity(0.6)
        }
    }

    var newRideButton: some View {
        Button { model.newRide() } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10 * scale, weight: .bold))
                .padding(3 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New ride")
        .opacity(model.ride.started ? (hovering ? 0.9 : 0.3) : 0)
        .disabled(!model.ride.started)
    }

    func detail(_ other: Double?) -> String {
        let label = mainIsAverage ? "now" : "3s"
        let o = other.map { "\(Int($0.rounded()))W" } ?? "--"
        let c = model.cadence.map { "\(Int($0.rounded())) rpm" } ?? "-- rpm"
        return "\(label) \(o) · \(c)"
    }

    func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    @ViewBuilder var menu: some View {
        Button("New Ride") { model.newRide() }
            .disabled(!model.ride.started)
        Divider()
        if model.paused {
            Button("Reconnect") { source.resume() }
        } else {
            Button("Disconnect") { source.pause("Off") }
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

/// The last two minutes of moving time, with the ride average as a dashed line.
struct PowerChart: View {
    let ride: Ride
    let scale: Double
    static let window: TimeInterval = 120

    var body: some View {
        let end = max(ride.movingTime, Self.window)
        let start = end - Self.window
        // Keep one point before the window so the line enters from the left edge.
        let from = ride.trace.lastIndex { $0.time < start } ?? 0
        let points = Array(ride.trace[from...])
        let avg = ride.averageWatts
        let top = max(Double(points.map(\.watts).max() ?? 0), avg ?? 0, 100) * 1.15

        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("Time", p.time), y: .value("Watts", p.watts))
                    .foregroundStyle(.linearGradient(colors: [.white.opacity(0.35), .white.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.time), y: .value("Watts", p.watts))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 1.5 * scale, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let avg {
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1 * scale, dash: [3 * scale, 3 * scale]))
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
        .background(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
        }
    }
}
