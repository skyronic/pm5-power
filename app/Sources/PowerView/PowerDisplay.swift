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
    @AppStorage("windowOpacity") var windowOpacity = 1.0  // whole window, for sitting over video
    @AppStorage(Model.refreshKey) var refresh = 0.0
    @State private var hovering = false

    static let size = CGSize(width: 220, height: 140)

    var body: some View {
        let live = model.live
        let main = mainIsAverage ? model.avg3.map { Int($0.rounded()) } : model.pm5.watts
        let other = mainIsAverage ? model.pm5.watts.map(Double.init) : model.avg3
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
                statusDot
                Text(statusLine(other))
                    .font(.system(size: 11 * scale, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.6)
            }
            PowerChart(trace: model.trace, average: average, scale: scale)
                .opacity(rolling ? 1 : 0.45)
        }
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 12 * scale)
        .padding(.top, 4 * scale)
        .padding(.bottom, 10 * scale)
        .frame(width: Self.size.width * scale, height: Self.size.height * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale).fill(.black.opacity(opacity)))
        .opacity(hovering ? 1 : windowOpacity)  // full strength under the mouse, to find and use it
        .animation(.easeOut(duration: 0.2), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { source.resume() }
    }

    // Clock, average and stopped state are the PM5's own, shown as is.

    var started: Bool { (model.pm5.elapsed ?? 0) > 0 }
    var average: Double? { started ? model.pm5.averageWatts.map(Double.init) : nil }

    /// The PM5's clock is running and data is arriving.
    var rolling: Bool { model.live && started && model.pm5.active != false }

    var rideStats: some View {
        let paused = started && !rolling
        return VStack(alignment: .trailing, spacing: 1 * scale) {
            HStack(spacing: 3 * scale) {
                if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11 * scale, weight: .bold))
                }
                Text(clock(model.pm5.elapsed ?? 0))
                    .font(.system(size: 20 * scale, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(paused ? pausedColor : .white)
            .opacity(started ? 1 : 0.4)
            Text("avg \(average.map { "\(Int($0.rounded()))" } ?? "--") W")
                .font(.system(size: 12 * scale, weight: .medium, design: .rounded))
                .opacity(0.6)
        }
    }

    /// Green: data arriving. Amber: connected but silent. Pulsing blue: looking for the bike.
    /// Grey: disconnected on purpose. Red: Bluetooth itself is off or not allowed.
    var statusDot: some View {
        let color: Color = switch model.link {
        case .connected: model.live ? .green : pausedColor
        case .scanning, .connecting: .blue
        case .paused, .starting: .white.opacity(0.4)
        case .bluetoothOff, .unauthorized, .unavailable: .red
        }
        return Image(systemName: "circle.fill")
            .font(.system(size: 6 * scale))
            .foregroundStyle(color)
            // Animates only while searching, which times out, so nothing redraws while idle.
            .symbolEffect(.pulse, isActive: model.link.isSearching)
    }

    func statusLine(_ other: Double?) -> String {
        if let left = model.idleDisconnectIn { return "Idle · disconnecting in \(clock(TimeInterval(left)))" }
        if model.live { return detail(other) }
        if case .connected(let name, _) = model.link { return "\(name) · waiting for data" }
        return model.link.message
    }

    func detail(_ other: Double?) -> String {
        let label = mainIsAverage ? "now" : "3s"
        let o = other.map { "\(Int($0.rounded()))W" } ?? "--"
        let c = model.pm5.cadence.map { "\(Int($0.rounded())) rpm" } ?? "-- rpm"
        return "\(label) \(o) · \(c)"
    }

    func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The last two minutes of the PM5's workout clock, with its average as a dashed line.
struct PowerChart: View {
    let trace: Trace
    let average: Double?
    let scale: Double
    static let window: TimeInterval = 120

    var body: some View {
        let end = max(trace.points.last?.time ?? 0, Self.window)
        let start = end - Self.window
        // Keep one point before the window so the line enters from the left edge.
        let from = trace.points.lastIndex { $0.time < start } ?? 0
        let points = Array(trace.points[from...])
        let avg = average
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
