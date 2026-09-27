import SwiftUI
import CoreImage
import PhotosUI

/// Une pose de référence et la transformation appliquée à son calque.
struct PoseItem: Identifiable, Codable, Equatable {
    var id: String
    var x: Double = 0
    var y: Double = 0
    var scale: Double = 1
    var rotation: Double = 0
    var flipped: Bool = false
}

/// Bibliothèque de poses : fichiers dans Documents/poses, index en JSON.
/// Rien ne sort de l'appareil.
@MainActor
final class OverlayStore: ObservableObject {

    @Published private(set) var items: [PoseItem] = []
    @Published var selected: Int = -1
    @Published var edgeMode = false { didSet { UserDefaults.standard.set(edgeMode, forKey: "edgeMode") } }
    @Published var opacity: Double = 0.45 { didSet { UserDefaults.standard.set(opacity, forKey: "opacity") } }
    @Published var importing = false

    private let dir: URL
    private let ciContext = CIContext()
    private var fullCache: [String: UIImage] = [:]
    private var thumbCache: [String: UIImage] = [:]

    var current: PoseItem? {
        guard selected >= 0, selected < items.count else { return nil }
        return items[selected]
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("poses", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if UserDefaults.standard.object(forKey: "opacity") != nil {
            opacity = UserDefaults.standard.double(forKey: "opacity")
        }
        edgeMode = UserDefaults.standard.bool(forKey: "edgeMode")

        load()
        selected = items.isEmpty ? -1 : 0
    }

    // MARK: - Chemins

    private var indexURL: URL { dir.appendingPathComponent("index.json") }
    private func fullURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).img") }
    private func edgeURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).edges.png") }

    // MARK: - Persistance

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([PoseItem].self, from: data) else { return }
        items = decoded.filter { FileManager.default.fileExists(atPath: fullURL($0.id).path) }
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Modifie la pose courante sans repasser par un index.
    func mutate(_ change: (inout PoseItem) -> Void) {
        guard selected >= 0, selected < items.count else { return }
        change(&items[selected])
    }

    func resetTransform() {
        mutate { item in
            item.x = 0; item.y = 0; item.scale = 1; item.rotation = 0
        }
        persist()
    }

    // MARK: - Images

    func image(for item: PoseItem) -> UIImage? {
        let key = edgeMode ? item.id + ".e" : item.id
        if let cached = fullCache[key] { return cached }
        let url = edgeMode ? edgeURL(item.id) : fullURL(item.id)
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else {
            // Pas de version contours pour cette image : on retombe sur l'originale.
            if edgeMode, let data = try? Data(contentsOf: fullURL(item.id)) {
                return UIImage(data: data)
            }
            return nil
        }
        fullCache[key] = img
        return img
    }

    func thumb(for item: PoseItem) -> UIImage? {
        if let cached = thumbCache[item.id] { return cached }
        guard let data = try? Data(contentsOf: fullURL(item.id)),
              let img = UIImage(data: data) else { return nil }
        let small = img.preparingThumbnail(of: CGSize(width: 160, height: 160)) ?? img
        thumbCache[item.id] = small
        return small
    }

    // MARK: - Import

    func add(_ picks: [PhotosPickerItem]) async {
        guard !picks.isEmpty else { return }
        importing = true
        defer { importing = false }

        for pick in picks {
            guard let data = try? await pick.loadTransferable(type: Data.self),
                  UIImage(data: data) != nil else { continue }
            let id = UUID().uuidString
            do {
                try data.write(to: fullURL(id), options: .atomic)
            } catch { continue }
            if let edges = makeEdges(from: data) {
                try? edges.write(to: edgeURL(id), options: .atomic)
            }
            items.append(PoseItem(id: id))
        }
        selected = items.isEmpty ? -1 : items.count - 1
        persist()
    }

    func remove(_ item: PoseItem) {
        try? FileManager.default.removeItem(at: fullURL(item.id))
        try? FileManager.default.removeItem(at: edgeURL(item.id))
        fullCache[item.id] = nil
        fullCache[item.id + ".e"] = nil
        thumbCache[item.id] = nil
        items.removeAll { $0.id == item.id }
        if selected >= items.count { selected = items.count - 1 }
        persist()
    }

    // MARK: - Contours

    /// Ne garde que les lignes de la référence, en blanc sur fond transparent.
    /// C'est le mode réellement utilisable : une photo opaque à 45 % cache la vue.
    private func makeEdges(from data: Data) -> Data? {
        guard var image = CIImage(data: data) else { return nil }

        let extent = image.extent
        let longest = max(extent.width, extent.height)
        if longest > 1400 {
            let ratio = 1400 / longest
            image = image.applyingFilter("CILanczosScaleTransform",
                                         parameters: [kCIInputScaleKey: ratio,
                                                      kCIInputAspectRatioKey: 1.0])
        }

        let edges = image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 3.0])
        let mono = edges.applyingFilter("CIPhotoEffectMono")
        // Luminance -> alpha : les traits deviennent blancs, le fond disparaît.
        let masked = mono.applyingFilter("CIMaskToAlpha")

        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return ciContext.pngRepresentation(of: masked, format: .RGBA8, colorSpace: space)
    }
}
