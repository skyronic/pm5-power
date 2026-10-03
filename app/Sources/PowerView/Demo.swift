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
        model.link = .connected(name: "Demo", source: "Simulated")
        timer?.invalidate()  // tapping the window calls resume() even while running
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.step() }
    }

    func pause(_ reason: String) {
        timer?.invalidate()
        model.link = .paused(reason: reason)
        model.live = false
    }

    private func step() {
        t += 0.5
        // Stop pedalling for 10 s every 90 s so auto-pause can be seen.
        if t.truncatingRemainder(dividingBy: 90) >= 80 {
            model.update(Reading(watts: 0, cadence: 0))
            return
        }
        let watts = 180 + 60 * sin(t / 20) + Double.random(in: -15...15)
        model.update(Reading(watts: Int(watts), cadence: 85 + Double.random(in: -3...3)))
    }
}
