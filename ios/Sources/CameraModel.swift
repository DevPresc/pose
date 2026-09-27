import AVFoundation
import AudioToolbox
import UIKit

/// Session de capture, retardateur, rafale. Toute la configuration AVFoundation
/// passe par `queue` ; les propriétés publiées sont mises à jour sur le main.
final class CameraModel: NSObject, ObservableObject {

    @Published var isReady = false
    @Published var errorText: String?
    @Published var countdown = 0
    @Published var countdownTotal = 0
    @Published var isBusy = false
    /// Position dans la rafale en cours (1…burst), 0 hors rafale.
    @Published var burstIndex = 0
    @Published var zoomOptions: [Double] = [1]
    @Published var currentZoom: Double = 1
    @Published var position: AVCaptureDevice.Position = .back

    @Published var flashOn = false {
        didSet { wantFlash = flashOn }
    }
    @Published var autoSave = UserDefaults.standard.bool(forKey: "autoSave") {
        didSet { UserDefaults.standard.set(autoSave, forKey: "autoSave") }
    }
    @Published var timerSeconds = UserDefaults.standard.integer(forKey: "timer") {
        didSet { UserDefaults.standard.set(timerSeconds, forKey: "timer") }
    }
    @Published var burst = max(1, UserDefaults.standard.integer(forKey: "burst")) {
        didSet { UserDefaults.standard.set(burst, forKey: "burst") }
    }
    @Published var ratio = FrameRatio(rawValue: UserDefaults.standard.string(forKey: "ratio") ?? "") ?? .r45 {
        didSet {
            UserDefaults.standard.set(ratio.rawValue, forKey: "ratio")
            wantRatio = ratio.value
        }
    }

    /// Appelé sur le main à chaque photo traitée (recadrée, encodée).
    var onPhoto: ((PhotoProcessor.Output) -> Void)?
    var onMessage: ((String) -> Void)?

    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "pose.camera.session")
    private let processing = DispatchQueue(label: "pose.camera.processing", qos: .userInitiated)
    private var input: AVCaptureDeviceInput?
    private var device: AVCaptureDevice?
    private var zoomBase: CGFloat = 1
    private var wantFlash = false
    private var wantRatio: CGFloat = FrameRatio.r45.value
    private var wantPosition: AVCaptureDevice.Position = .back
    private var timer: Timer?
    private var remaining = 0
    private var cancelled = false
    private var configured = false
    private let volumeShutter = VolumeShutter()

    override init() {
        super.init()
        wantRatio = ratio.value
    }

    // MARK: - Démarrage

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.run() } else { self?.report("Accès caméra refusé.") }
            }
        default:
            report("Accès caméra refusé. Réglages → Pose → Appareil photo.")
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func run() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured { self.configure() }
            guard self.configured else { return }
            if !self.session.isRunning { self.session.startRunning() }
            self.applyMaxPhotoDimensions()
            self.onMain { self.isReady = true; self.errorText = nil }
        }
    }

    private static func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        // Caméra virtuelle la plus riche : on change d'objectif par simple facteur de zoom.
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        ]
        for type in types {
            if let d = AVCaptureDevice.default(type, for: .video, position: .back) { return d }
        }
        return nil
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let dev = Self.bestDevice(for: wantPosition),
              let inp = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(inp) else {
            session.commitConfiguration()
            report("Caméra indisponible.")
            return
        }
        session.addInput(inp)
        input = inp
        device = dev

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            report("Sortie photo indisponible.")
            return
        }
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .quality
        session.commitConfiguration()

        configured = true
        updateZoomOptions(for: dev)
    }

    /// `activeFormat` n'est fiable qu'une fois la session lancée : c'est ce qui débloque le 48 Mpx.
    private func applyMaxPhotoDimensions() {
        guard let dev = device else { return }
        let dims = dev.activeFormat.supportedMaxPhotoDimensions
        guard let best = dims.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) })
        else { return }
        session.beginConfiguration()
        output.maxPhotoDimensions = best
        session.commitConfiguration()
    }

    func switchCamera() {
        guard !isBusy else { return }
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        position = next
        wantPosition = next
        queue.async { [weak self] in
            guard let self, self.configured, let old = self.input,
                  let dev = Self.bestDevice(for: next),
                  let inp = try? AVCaptureDeviceInput(device: dev) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(old)
            if self.session.canAddInput(inp) {
                self.session.addInput(inp)
                self.input = inp
                self.device = dev
            } else {
                self.session.addInput(old)
            }
            self.session.commitConfiguration()
            self.applyMaxPhotoDimensions()
            if let current = self.device { self.updateZoomOptions(for: current) }
        }
    }

    // MARK: - Zoom

    private func updateZoomOptions(for dev: AVCaptureDevice) {
        // Sur une caméra à ultra grand-angle, le facteur 1.0 correspond au 0,5×.
        switch dev.deviceType {
        case .builtInTripleCamera, .builtInDualWideCamera: zoomBase = 2
        default: zoomBase = 1
        }
        var options: [Double] = []
        if zoomBase == 2 { options.append(0.5) }
        options.append(1)
        let maxUI = Double(dev.maxAvailableVideoZoomFactor) / Double(zoomBase)
        if dev.position == .back {
            if maxUI >= 2 { options.append(2) }
            if maxUI >= 5 { options.append(5) }
        }
        onMain { self.zoomOptions = options; self.currentZoom = 1 }
        applyZoom(1)
    }

    func setZoom(_ ui: Double) {
        currentZoom = ui
        applyZoom(ui)
    }

    private func applyZoom(_ ui: Double) {
        queue.async { [weak self] in
            guard let self, let d = self.device else { return }
            let target = CGFloat(ui) * self.zoomBase
            do {
                try d.lockForConfiguration()
                d.videoZoomFactor = max(d.minAvailableVideoZoomFactor, min(target, d.maxAvailableVideoZoomFactor))
                d.unlockForConfiguration()
            } catch { }
        }
    }

    // MARK: - Réglages

    func cycleTimer() { timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0) }
    func cycleBurst() { burst = burst == 1 ? 3 : (burst == 3 ? 5 : 1) }

    // MARK: - Déclenchement

    /// Appui sur le déclencheur. Un second appui pendant le décompte ou la rafale annule.
    func capture() {
        guard isReady else { return }
        if isBusy {
            cancelled = true
            if timer != nil { finish() }
            return
        }
        cancelled = false
        isBusy = true
        if timerSeconds > 0 { startCountdown(timerSeconds) } else { startBurst() }
    }

    private func startCountdown(_ seconds: Int) {
        countdownTotal = seconds
        countdown = seconds
        tick()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.countdown -= 1
            if self.countdown <= 0 {
                t.invalidate()
                self.timer = nil
                self.countdownTotal = 0
                self.startBurst()
            } else {
                self.tick()
            }
        }
    }

    private func tick() {
        AudioServicesPlaySystemSound(1103)
        Haptics.tap()
    }

    private func startBurst() {
        remaining = burst
        fireNext()
    }

    private func fireNext() {
        guard !cancelled, remaining > 0 else { finish(); return }
        remaining -= 1
        burstIndex = burst > 1 ? burst - remaining : 0
        Haptics.shutter()
        fire()
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        remaining = 0
        cancelled = false
        countdown = 0
        countdownTotal = 0
        burstIndex = 0
        isBusy = false
    }

    private func fire() {
        queue.async { [weak self] in
            guard let self else { return }
            let settings: AVCapturePhotoSettings
            if self.output.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.maxPhotoDimensions = self.output.maxPhotoDimensions
            settings.photoQualityPrioritization = .quality
            if self.wantFlash, self.output.supportedFlashModes.contains(.on) {
                settings.flashMode = .on
            } else if self.output.supportedFlashModes.contains(.off) {
                settings.flashMode = .off
            }
            if let c = self.output.connection(with: .video) {
                // App verrouillée en portrait : l'angle est constant.
                if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
                // Caméra avant : la photo est enregistrée comme l'aperçu, en miroir.
                if c.isVideoMirroringSupported {
                    c.automaticallyAdjustsVideoMirroring = false
                    c.isVideoMirrored = self.wantPosition == .front
                }
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Utilitaires

    private func report(_ message: String) {
        onMain { self.errorText = message; self.finish() }
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    // MARK: - Boutons de volume

    func enableVolumeShutter() {
        volumeShutter.start { [weak self] in self?.capture() }
    }

    func disableVolumeShutter() {
        volumeShutter.stop()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraModel: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        // Photo suivante de la rafale, pendant que celle-ci est recadrée en arrière-plan.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.fireNext() }

        if let error {
            onMain { self.onMessage?("Échec de la capture : \(error.localizedDescription)") }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            onMain { self.onMessage?("Photo illisible.") }
            return
        }
        let ratio = wantRatio
        processing.async {
            let result = PhotoProcessor.process(data, ratio: ratio)
            DispatchQueue.main.async { self.onPhoto?(result) }
        }
    }
}
