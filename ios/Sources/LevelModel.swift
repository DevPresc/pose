import CoreMotion
import SwiftUI

/// Niveau d'horizon à partir de la gravité mesurée par CoreMotion.
final class LevelModel: ObservableObject {

    @Published private(set) var angle: Double = 0
    @Published private(set) var isLevel = false
    @Published private(set) var isFlat = false
    @Published var enabled = false {
        didSet { enabled ? start() : stop() }
    }

    private let motion = CMMotionManager()
    private var smoothed = 0.0

    private func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let g = data?.gravity else { return }

            // Téléphone à plat : l'horizon n'a pas de sens.
            let flat = abs(g.y) < 0.35
            if flat != self.isFlat { self.isFlat = flat }
            guard !flat else { return }

            let target = atan(g.x / -g.y) * 180 / .pi
            self.smoothed += (target - self.smoothed) * 0.25
            let level = abs(self.smoothed) < 1
            if level && !self.isLevel { Haptics.tap() }   // petit « clic » quand c'est droit
            if level != self.isLevel { self.isLevel = level }
            self.angle = self.smoothed
        }
    }

    private func stop() {
        motion.stopDeviceMotionUpdates()
        isLevel = false
    }
}
