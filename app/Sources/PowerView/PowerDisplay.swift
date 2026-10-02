import SwiftUI

struct PowerDisplay: View {
    @ObservedObject var model: Model
    let source: PowerSource
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
        .onTapGesture { source.resume() }
    }

    func detail(_ other: Double?) -> String {
        let label = mainIsAverage ? "now" : "3s"
        let o = other.map { "\(Int($0.rounded()))W" } ?? "--"
        let c = model.cadence.map { "\(Int($0.rounded())) rpm" } ?? "-- rpm"
        return "\(label) \(o) · \(c)"
    }

    @ViewBuilder var menu: some View {
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
