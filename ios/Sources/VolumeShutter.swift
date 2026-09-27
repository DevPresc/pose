import AVFoundation
import MediaPlayer
import UIKit

/// Déclenchement par les boutons de volume.
///
/// iOS n'expose pas d'API officielle pour ça. La méthode employée par tous les
/// appareils photo tiers : observer `AVAudioSession.outputVolume`, puis remettre
/// le volume à sa valeur de départ pour pouvoir re-presser. Un `MPVolumeView`
/// hors écran supprime le bandeau système.
///
/// Si Apple casse cette astuce, `start()` échoue en silence et le bouton à
/// l'écran continue de fonctionner : rien d'autre ne dépend de ce fichier.
final class VolumeShutter {

    private var observation: NSKeyValueObservation?
    private let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
    private var baseline: Float = 0.5
    private var armed = false
    private var onPress: (() -> Void)?

    func start(onPress: @escaping () -> Void) {
        guard observation == nil else { return }
        self.onPress = onPress

        attachVolumeView()

        let audio = AVAudioSession.sharedInstance()
        // .ambient + mixWithOthers : on ne coupe pas la musique de l'utilisateur.
        try? audio.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? audio.setActive(true)

        baseline = audio.outputVolume
        // Il faut de la marge des deux côtés pour détecter un appui haut ET bas.
        if baseline < 0.1 || baseline > 0.9 {
            setSystemVolume(0.5)
            baseline = 0.5
        }
        armed = true

        observation = audio.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self, let value = change.newValue else { return }
            DispatchQueue.main.async { self.handle(value) }
        }
    }

    func stop() {
        observation = nil
        armed = false
        onPress = nil
        volumeView.removeFromSuperview()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func handle(_ value: Float) {
        guard armed, abs(value - baseline) > 0.001 else { return }
        onPress?()
        // Remise à niveau pour que l'appui suivant soit détectable.
        setSystemVolume(baseline)
    }

    private func attachVolumeView() {
        guard volumeView.superview == nil else { return }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let window = scene?.keyWindow ?? scene?.windows.first else { return }
        window.addSubview(volumeView)
    }

    /// Écrit dans le slider interne du `MPVolumeView` : seul moyen public de
    /// régler le volume système sans passer par les boutons.
    private func setSystemVolume(_ value: Float) {
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        armed = false
        slider.value = value
        // Le temps que la notification de retour arrive et soit ignorée.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.armed = true
        }
    }
}
