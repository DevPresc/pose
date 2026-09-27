import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Format du cadre, exprimé en portrait (largeur / hauteur).
enum FrameRatio: String, CaseIterable {
    case r45 = "4:5", r34 = "3:4", r11 = "1:1", r916 = "9:16"

    var value: CGFloat {
        switch self {
        case .r45: return 4.0 / 5.0
        case .r34: return 3.0 / 4.0
        case .r11: return 1.0
        case .r916: return 9.0 / 16.0
        }
    }

    var note: String {
        switch self {
        case .r45: return "Portrait Instagram"
        case .r34: return "Capteur complet"
        case .r11: return "Carré"
        case .r916: return "Story"
        }
    }

    var next: FrameRatio {
        let all = FrameRatio.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

/// Recadre la photo au format choisi, au centre, comme l'aperçu en `resizeAspectFill`.
enum PhotoProcessor {

    struct Output {
        let data: Data
        let ext: String
        let width: Int
        let height: Int
        let thumbnail: UIImage?
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func process(_ data: Data, ratio: CGFloat) -> Output {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return Output(data: data, ext: "jpg", width: 0, height: 0, thumbnail: nil)
        }
        let pw = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let ph = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let swapped = (5...8).contains(orientation)
        let w = swapped ? ph : pw, h = swapped ? pw : ph
        let ext = isHEIF(src) ? "heic" : "jpg"

        // 3:4 = capteur entier : on garde le fichier d'origine intact (HDR, carte de gain, tout).
        if w > 0, h > 0, abs(CGFloat(w) / CGFloat(h) - ratio) < 0.01 {
            return Output(data: data, ext: ext, width: w, height: h, thumbnail: thumbnail(of: data))
        }

        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            return Output(data: data, ext: ext, width: w, height: h, thumbnail: thumbnail(of: data))
        }

        let e = image.extent
        var cw = e.width, ch = e.height
        if cw / ch > ratio { cw = (ch * ratio).rounded() } else { ch = (cw / ratio).rounded() }
        let rect = CGRect(x: e.minX + ((e.width - cw) / 2).rounded(),
                          y: e.minY + ((e.height - ch) / 2).rounded(),
                          width: cw, height: ch)
        let cropped = image.cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))

        // L'orientation est déjà appliquée aux pixels : la balise doit repasser à 1.
        var meta = image.properties
        meta[kCGImagePropertyOrientation as String] = 1
        if var tiff = meta[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            meta[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        let tagged = cropped.settingProperties(meta)

        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        let options: [CIImageRepresentationOption: Any] = [quality: 0.9]

        let encoded = context.heifRepresentation(of: tagged, format: .RGBA8, colorSpace: space, options: options)
            .map { ($0, "heic") }
            ?? context.jpegRepresentation(of: tagged, colorSpace: space, options: options).map { ($0, "jpg") }

        guard let encoded else {
            return Output(data: data, ext: ext, width: w, height: h, thumbnail: thumbnail(of: data))
        }
        let (out, outExt) = encoded
        return Output(data: out, ext: outExt, width: Int(cw), height: Int(ch), thumbnail: thumbnail(of: out))
    }

    /// Vignette via ImageIO : ne décode jamais l'image entière en mémoire.
    static func thumbnail(of data: Data, maxPixel: CGFloat = 240) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(from: src, maxPixel: maxPixel)
    }

    static func thumbnail(from src: CGImageSource, maxPixel: CGFloat) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func isHEIF(_ src: CGImageSource) -> Bool {
        guard let type = CGImageSourceGetType(src) as String? else { return false }
        return type == UTType.heic.identifier || type == UTType.heif.identifier
    }
}
