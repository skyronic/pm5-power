import Foundation
import PowerProtocol

/// Simulated PM5 for development and screenshots: `open PowerView.app --args --demo`.
/// Sends the same readings and status packets as the bike, so the display works exactly as it does live.
final class Demo: PowerSource {
    let model: Model
    private var timer: Timer?
    private var t = 0.0
    private var elapsed = 0.0  // the fake PM5's workout clock: only runs while pedalling
    private var energy = 0.0

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
        // Stop pedalling for 10 s every 90 s so the pause can be seen.
        let pedalling = t.truncatingRemainder(dividingBy: 90) < 80
        let watts = pedalling ? Int(180 + 60 * sin(t / 20) + Double.random(in: -15...15)) : 0
        if pedalling {
            elapsed += 0.5
            energy += Double(watts) * 0.5
        }
        model.update(Reading(watts: watts, cadence: pedalling ? 85 + Double.random(in: -3...3) : 0))
        model.updateStatus(WorkoutStatus(elapsed: elapsed, averageWatts: elapsed > 0 ? Int(energy / elapsed) : 0,
                                         active: pedalling, inWorkout: true))
    }
}
