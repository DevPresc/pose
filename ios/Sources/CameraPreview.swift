import SwiftUI
import AVFoundation

/// Aperçu caméra en `resizeAspect` : le cadre 3:4 affiché est exactement
/// ce que le capteur enregistre, sans rognage surprise.
struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // La connexion n'existe qu'une fois les entrées ajoutées : on refixe
        // l'angle à chaque passe tant qu'il n'est pas bon.
        if let c = uiView.previewLayer.connection,
           c.isVideoRotationAngleSupported(90),
           c.videoRotationAngle != 90 {
            c.videoRotationAngle = 90
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
