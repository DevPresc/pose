import SwiftUI
import AVFoundation

/// Aperçu caméra en `resizeAspectFill` dans le cadre du format choisi.
/// La photo est recadrée au centre avec le même rapport : ce qui est cadré est ce qui est gardé.
struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.fixRotation()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        // La connexion n'existe qu'une fois les entrées ajoutées, et change avec la caméra.
        override func layoutSubviews() {
            super.layoutSubviews()
            fixRotation()
        }

        func fixRotation() {
            if let c = previewLayer.connection, c.isVideoRotationAngleSupported(90), c.videoRotationAngle != 90 {
                c.videoRotationAngle = 90
            }
        }
    }
}
