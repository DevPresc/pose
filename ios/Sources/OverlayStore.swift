import SwiftUI
import CoreImage
import PhotosUI

/// Une référence importée et la transformation appliquée à son calque.
/// Sert aussi à mémoriser la position du calque des poses intégrées.
struct PoseItem: Identifiable, Codable, Equatable {
    var id: String
    var x: Double = 0
    var y: Double = 0
    var scale: Double = 1
    var rotation: Double = 0
    var flipped: Bool = false
}

/// Identifie la pose affichée : du pack intégré ou importée.
enum PoseKey: Hashable {
    case builtin(String)
    case user(String)

    var raw: String {
        switch self {
        case .builtin(let id): return "b:" + id
        case .user(let id): return "u:" + id
        }
    }

    init?(raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "b": self = .builtin(parts[1])
        case "u": self = .user(parts[1])
        default: return nil
        }
    }
}

/// Bibliothèque de poses : fichiers dans Documents/poses. Rien ne sort de l'appareil.
@MainActor
final class OverlayStore: ObservableObject {

    @Published private(set) var items: [PoseItem] = []
    @Published private(set) var builtinTransforms: [String: PoseItem] = [:]
    @Published var current: PoseKey? {
        didSet { UserDefaults.standard.set(current?.raw, forKey: "current") }
    }
    @Published var edgeMode = true {
        didSet { UserDefaults.standard.set(edgeMode, forKey: "edgeMode") }
    }
    @Published var opacity: Double = 0.55 {
        didSet { UserDefaults.standard.set(opacity, forKey: "opacity") }
    }
    @Published var importing = false

    private let dir: URL
    private let ciContext = CIContext()
    private var fullCache: [String: UIImage] = [:]
    private var thumbCache: [String: UIImage] = [:]

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("poses", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let defaults = UserDefaults.standard
        if defaults.object(forKey: "opacity") != nil { opacity = defaults.double(forKey: "opacity") }
        if defaults.object(forKey: "edgeMode") != nil { edgeMode = defaults.bool(forKey: "edgeMode") }

        load()

        if let raw = defaults.string(forKey: "current"), let key = PoseKey(raw: raw), exists(key) {
            current = key
        } else {
            current = .builtin(PosePack.all[0].id)
        }
    }

    // MARK: - Chemins et persistance

    private var indexURL: URL { dir.appendingPathComponent("index.json") }
    private var builtinURL: URL { dir.appendingPathComponent("builtin.json") }
    private func fullURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).img") }
    private func edgeURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).edges.png") }

    private func load() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([PoseItem].self, from: data) {
            items = decoded.filter { FileManager.default.fileExists(atPath: fullURL($0.id).path) }
        }
        if let data = try? Data(contentsOf: builtinURL),
           let decoded = try? JSONDecoder().decode([String: PoseItem].self, from: data) {
            builtinTransforms = decoded
        }
    }

    func persist() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(builtinTransforms) { try? data.write(to: builtinURL, options: .atomic) }
    }

    private func exists(_ key: PoseKey) -> Bool {
        switch key {
        case .builtin(let id): return PosePack.pose(id) != nil
        case .user(let id): return items.contains { $0.id == id }
        }
    }

    // MARK: - Pose courante

    var currentBuiltin: BuiltinPose? {
        if case .builtin(let id)? = current { return PosePack.pose(id) }
        return nil
    }

    var currentUser: PoseItem? {
        if case .user(let id)? = current { return items.first { $0.id == id } }
        return nil
    }

    var isUserPose: Bool { currentUser != nil }

    var transform: PoseItem {
        switch current {
        case .builtin(let id)?: return builtinTransforms[id] ?? PoseItem(id: id)
        case .user(let id)?: return items.first { $0.id == id } ?? PoseItem(id: id)
        case .none: return PoseItem(id: "")
        }
    }

    var currentName: String {
        if let b = currentBuiltin { return b.name }
        if let u = currentUser, let i = items.firstIndex(of: u) { return "Référence \(i + 1)" }
        return "Choisir une pose"
    }

    var currentTip: String {
        if let b = currentBuiltin { return b.tip }
        return "Glisse pour placer, pince pour ajuster, double-tap pour recentrer."
    }

    func mutate(_ change: (inout PoseItem) -> Void) {
        switch current {
        case .builtin(let id)?:
            var t = builtinTransforms[id] ?? PoseItem(id: id)
            change(&t)
            builtinTransforms[id] = t
        case .user(let id)?:
            if let i = items.firstIndex(where: { $0.id == id }) { change(&items[i]) }
        case .none:
            break
        }
    }

    func resetTransform() {
        mutate { t in
            t.x = 0; t.y = 0; t.scale = 1; t.rotation = 0
        }
        persist()
    }

    var orderedKeys: [PoseKey] {
        PosePack.all.map { PoseKey.builtin($0.id) } + items.map { PoseKey.user($0.id) }
    }

    /// Pose suivante (+1) ou précédente (-1), en boucle.
    func cycle(_ direction: Int) {
        let keys = orderedKeys
        guard !keys.isEmpty else { return }
        let i = current.flatMap { keys.firstIndex(of: $0) } ?? -1
        current = keys[(i + direction + keys.count) % keys.count]
    }

    // MARK: - Images

    func image(for item: PoseItem) -> UIImage? {
        let wantsEdges = edgeMode && FileManager.default.fileExists(atPath: edgeURL(item.id).path)
        let key = item.id + (wantsEdges ? ".e" : "")
        if let cached = fullCache[key] { return cached }
        guard let data = try? Data(contentsOf: wantsEdges ? edgeURL(item.id) : fullURL(item.id)),
              let image = UIImage(data: data) else { return nil }
        fullCache[key] = image
        return image
    }

    func thumb(for item: PoseItem) -> UIImage? {
        if let cached = thumbCache[item.id] { return cached }
        guard let data = try? Data(contentsOf: fullURL(item.id)),
              let small = PhotoProcessor.thumbnail(of: data, maxPixel: 360) else { return nil }
        thumbCache[item.id] = small
        return small
    }

    // MARK: - Import

    /// Importe des images de la photothèque et renvoie la dernière ajoutée.
    func add(_ picks: [PhotosPickerItem]) async -> PoseKey? {
        guard !picks.isEmpty else { return nil }
        importing = true
        defer { importing = false }

        var last: PoseKey?
        for pick in picks {
            guard let data = try? await pick.loadTransferable(type: Data.self),
                  UIImage(data: data) != nil else { continue }
            let id = UUID().uuidString
            do { try data.write(to: fullURL(id), options: .atomic) } catch { continue }
            if let edges = makeEdges(from: data) {
                try? edges.write(to: edgeURL(id), options: .atomic)
            }
            items.append(PoseItem(id: id))
            last = .user(id)
        }
        persist()
        return last
    }

    func remove(_ item: PoseItem) {
        try? FileManager.default.removeItem(at: fullURL(item.id))
        try? FileManager.default.removeItem(at: edgeURL(item.id))
        fullCache[item.id] = nil
        fullCache[item.id + ".e"] = nil
        thumbCache[item.id] = nil
        items.removeAll { $0.id == item.id }
        if current == .user(item.id) { current = .builtin(PosePack.all[0].id) }
        persist()
    }

    // MARK: - Contours

    /// Ne garde que les lignes de la référence, en blanc sur fond transparent.
    private func makeEdges(from data: Data) -> Data? {
        guard var image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }

        let longest = max(image.extent.width, image.extent.height)
        if longest > 1400 {
            image = image.applyingFilter("CILanczosScaleTransform",
                                         parameters: [kCIInputScaleKey: 1400 / longest,
                                                      kCIInputAspectRatioKey: 1.0])
        }
        let masked = image
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 3.0])
            .applyingFilter("CIPhotoEffectMono")
            .applyingFilter("CIMaskToAlpha")   // luminance -> alpha : traits blancs, fond transparent

        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return ciContext.pngRepresentation(of: masked, format: .RGBA8, colorSpace: space)
    }
}
