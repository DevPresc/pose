import SwiftUI
import Photos
import ImageIO

/// Une photo de la pellicule de Pose.
struct Shot: Identifiable, Codable, Equatable {
    let id: String
    let file: String
    let width: Int
    let height: Int
    let date: Date
    let bytes: Int
    var saved: Bool
}

/// Pellicule interne : Documents/shots, index en JSON.
/// Les photos y restent tant qu'elles ne sont pas exportées vers Photos puis vidées.
@MainActor
final class ShotStore: ObservableObject {

    @Published private(set) var shots: [Shot] = []
    @Published private(set) var lastThumb: UIImage?

    private let dir: URL
    private var displayCache: [String: UIImage] = [:]

    var unsaved: [Shot] { shots.filter { !$0.saved } }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
        refreshLastThumb()
    }

    private var indexURL: URL { dir.appendingPathComponent("index.json") }
    func url(for shot: Shot) -> URL { dir.appendingPathComponent(shot.file) }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Shot].self, from: data) else { return }
        shots = decoded.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(shots) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Ajout / suppression

    @discardableResult
    func add(_ output: PhotoProcessor.Output) -> Shot? {
        let id = UUID().uuidString
        let file = "\(id).\(output.ext)"
        do {
            try output.data.write(to: dir.appendingPathComponent(file), options: .atomic)
        } catch {
            return nil
        }
        let shot = Shot(id: id, file: file, width: output.width, height: output.height,
                        date: Date(), bytes: output.data.count, saved: false)
        shots.append(shot)
        persist()
        lastThumb = output.thumbnail
        return shot
    }

    func delete(_ shot: Shot) {
        try? FileManager.default.removeItem(at: url(for: shot))
        displayCache[shot.id] = nil
        shots.removeAll { $0.id == shot.id }
        persist()
        refreshLastThumb()
    }

    func clear() {
        for shot in shots { try? FileManager.default.removeItem(at: url(for: shot)) }
        shots = []
        displayCache = [:]
        lastThumb = nil
        persist()
    }

    // MARK: - Images

    private func refreshLastThumb() {
        guard let last = shots.last else { lastThumb = nil; return }
        let url = url(for: last)
        Task {
            let thumb = await Task.detached(priority: .utility) {
                ShotStore.downsample(url, maxPixel: 240)
            }.value
            if self.shots.last?.id == last.id { self.lastThumb = thumb }
        }
    }

    /// Image à la taille de l'écran : une photo 48 Mpx décodée entière pèserait ~200 Mo.
    func displayImage(for shot: Shot) async -> UIImage? {
        if let cached = displayCache[shot.id] { return cached }
        let url = url(for: shot)
        let image = await Task.detached(priority: .userInitiated) {
            ShotStore.downsample(url, maxPixel: 2400)
        }.value
        if let image { displayCache[shot.id] = image }
        return image
    }

    nonisolated static func downsample(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        return PhotoProcessor.thumbnail(from: src, maxPixel: maxPixel)
    }

    // MARK: - Photothèque

    /// Enregistre directement dans Photos (droit « ajout seulement », jamais de lecture).
    func saveToPhotos(_ list: [Shot]) async -> Bool {
        guard !list.isEmpty else { return true }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        let urls = list.map { url(for: $0) }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for url in urls {
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = url.lastPathComponent
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: options)
                }
            }
        } catch {
            return false
        }

        let ids = Set(list.map(\.id))
        for i in shots.indices where ids.contains(shots[i].id) {
            shots[i].saved = true
        }
        persist()
        return true
    }
}
