import Foundation
import PowerProtocol

/// Simulated rider for development and screenshots: `open PowerView.app --args --demo`.
final class Demo: PowerSource {
    let model: Model
    private var timer: Timer?
    private var t = 0.0

    init(model: Model) {
        self.model = model
        resume()
    }

    func resume() {
        model.paused = false
        model.status = "Demo"
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.step() }
    }

    func pause(_ reason: String) {
        timer?.invalidate()
        model.paused = true
        model.live = false
        model.status = "\(reason) · click to connect"
    }

    private func step() {
        t += 0.5
        let watts = 180 + 60 * sin(t / 20) + Double.random(in: -15...15)
        model.update(Reading(watts: Int(watts), cadence: 85 + Double.random(in: -3...3)))
    }
}
