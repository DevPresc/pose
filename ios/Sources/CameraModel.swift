import AVFoundation
import Photos
import UIKit

/// Session de capture + déclenchement. Toute la configuration AVFoundation
/// passe par `queue`; les propriétés publiées sont mises à jour sur le main.
final class CameraModel: NSObject, ObservableObject {

    @Published var isReady = false
    @Published var errorText: String?
    @Published var countdown = 0
    @Published var isBusy = false
    @Published var zoomOptions: [Double] = [1]
    @Published var currentZoom: Double = 1
    @Published var flashOn = false { didSet { wantFlash = flashOn } }

    /// Photo qui vient d'être prise, en attente de validation.
    @Published var review: UIImage?
    /// Enregistrement direct dans la photothèque, sans écran de validation.
    @Published var autoSave = false
    @Published var savedFlash = false
    /// Retardateur, en secondes. Porté par le modèle pour que le déclenchement
    /// par les boutons de volume utilise la même valeur que le bouton à l'écran.
    @Published var timerSeconds = 0

    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "pose.camera.session")
    private var device: AVCaptureDevice?
    private var zoomBase: CGFloat = 1
    private var wantFlash = false
    private var photoData: Data?
    private var timer: Timer?
    private var configured = false
    private let volumeShutter = VolumeShutter()

    // MARK: - Démarrage

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.run() }
                else { self?.report("Accès caméra refusé.") }
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
            self.setMain { self.isReady = true; self.errorText = nil }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Caméra virtuelle la plus riche disponible : elle permet de passer
        // d'un objectif à l'autre par simple facteur de zoom.
        let candidates: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera
        ]
        var picked: AVCaptureDevice?
        for type in candidates {
            if let d = AVCaptureDevice.default(type, for: .video, position: .back) { picked = d; break }
        }

        guard let dev = picked,
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else {
            session.commitConfiguration()
            report("Caméra arrière indisponible.")
            return
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            report("Sortie photo indisponible.")
            return
        }
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .quality
        session.commitConfiguration()

        device = dev
        configured = true

        // Sur une caméra à ultra grand-angle, le facteur 1.0 correspond au 0,5×.
        switch dev.deviceType {
        case .builtInTripleCamera, .builtInDualWideCamera: zoomBase = 2
        default: zoomBase = 1
        }

        var options: [Double] = []
        if zoomBase == 2 { options.append(0.5) }
        options.append(1)
        let maxUI = Double(dev.maxAvailableVideoZoomFactor) / Double(zoomBase)
        if maxUI >= 2 { options.append(2) }
        if maxUI >= 5 { options.append(5) }

        setMain { self.zoomOptions = options; self.currentZoom = 1 }
        applyZoom(1)
    }

    /// À appeler une fois la session lancée : `activeFormat` n'est fiable qu'à ce moment.
    private func applyMaxPhotoDimensions() {
        guard let dev = device else { return }
        let dims = dev.activeFormat.supportedMaxPhotoDimensions
        guard let best = dims.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) })
        else { return }
        session.beginConfiguration()
        output.maxPhotoDimensions = best
        session.commitConfiguration()
    }

    // MARK: - Zoom

    func setZoom(_ ui: Double) {
        setMain { self.currentZoom = ui }
        applyZoom(ui)
    }

    private func applyZoom(_ ui: Double) {
        queue.async { [weak self] in
            guard let self, let d = self.device else { return }
            let target = CGFloat(ui) * self.zoomBase
            let clamped = max(d.minAvailableVideoZoomFactor,
                              min(target, d.maxAvailableVideoZoomFactor))
            do {
                try d.lockForConfiguration()
                d.videoZoomFactor = clamped
                d.unlockForConfiguration()
            } catch { }
        }
    }

    // MARK: - Mise au point

    func focus(at point: CGPoint) {
        queue.async { [weak self] in
            guard let self, let d = self.device else { return }
            do {
                try d.lockForConfiguration()
                if d.isFocusPointOfInterestSupported {
                    d.focusPointOfInterest = point
                    if d.isFocusModeSupported(.autoFocus) { d.focusMode = .autoFocus }
                }
                if d.isExposurePointOfInterestSupported {
                    d.exposurePointOfInterest = point
                    if d.isExposureModeSupported(.autoExpose) { d.exposureMode = .autoExpose }
                }
                d.unlockForConfiguration()
            } catch { }
        }
    }

    // MARK: - Déclenchement

    func capture(delay: Int) {
        guard isReady, !isBusy else { return }
        guard delay > 0 else { fire(); return }

        isBusy = true
        countdown = delay
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.countdown -= 1
            if self.countdown <= 0 {
                t.invalidate()
                self.timer = nil
                self.fire()
            }
        }
    }

    func cancelCountdown() {
        timer?.invalidate()
        timer = nil
        countdown = 0
        isBusy = false
    }

    private func fire() {
        setMain { self.isBusy = true; self.countdown = 0 }
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
            // App verrouillée en portrait : l'angle est constant.
            if let c = self.output.connection(with: .video), c.isVideoRotationAngleSupported(90) {
                c.videoRotationAngle = 90
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func cycleTimer() {
        timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0)
    }

    // MARK: - Boutons de volume

    func enableVolumeShutter() {
        volumeShutter.start { [weak self] in
            guard let self else { return }
            if self.countdown > 0 { self.cancelCountdown() }
            else { self.capture(delay: self.timerSeconds) }
        }
    }

    func disableVolumeShutter() {
        volumeShutter.stop()
    }

    // MARK: - Photothèque

    func saveCurrent(completion: ((Bool) -> Void)? = nil) {
        guard let data = photoData else { completion?(false); return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.report("Autorise l'ajout aux photos dans Réglages → Pose.")
                completion?(false)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
            }, completionHandler: { ok, _ in
                DispatchQueue.main.async {
                    if ok { self.pulseSaved() }
                    completion?(ok)
                }
            })
        }
    }

    func discardReview() {
        review = nil
        photoData = nil
        isBusy = false
    }

    private func pulseSaved() {
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.savedFlash = false }
    }

    // MARK: - Utilitaires

    private func report(_ message: String) {
        setMain { self.errorText = message; self.isBusy = false }
    }

    private func setMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraModel: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            report("Échec de la capture : \(error.localizedDescription)")
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            report("Photo illisible.")
            return
        }
        photoData = data
        let image = UIImage(data: data)

        DispatchQueue.main.async {
            if self.autoSave {
                self.saveCurrent { _ in
                    self.photoData = nil
                    self.isBusy = false
                }
            } else {
                self.review = image
                self.isBusy = false
            }
        }
    }
}
