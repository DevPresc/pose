import SwiftUI

/// Pellicule plein écran : balayage entre les photos, partage, export groupé vers Photos.
struct ViewerView: View {
    @ObservedObject var shots: ShotStore
    let onClose: () -> Void
    let onMessage: (String) -> Void

    @State private var index = 0
    @State private var confirmDelete = false
    @State private var confirmClear = false
    @State private var saving = false

    private var current: Shot? {
        shots.shots.indices.contains(index) ? shots.shots[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(shots.shots.enumerated()), id: \.element.id) { i, shot in
                    ShotImage(shots: shots, shot: shot).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .onAppear { index = max(0, shots.shots.count - 1) }
        .onChange(of: shots.shots.count) { _, n in
            if n == 0 { onClose() } else if index >= n { index = n - 1 }
        }
        .confirmationDialog("Supprimer cette photo ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let current { withAnimation(.strongOut()) { shots.delete(current) } }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(current?.saved == true
                 ? "Elle reste dans ta photothèque."
                 : "Elle n’est pas encore dans ta photothèque.")
        }
        .alert("Vider la pellicule ?", isPresented: $confirmClear) {
            Button("Vider", role: .destructive) { shots.clear(); onClose() }
            Button("Garder", role: .cancel) {}
        } message: {
            Text("Toutes les photos sont dans ta photothèque. Tu peux les retirer de Pose pour libérer de la place.")
        }
    }

    // MARK: - Barres

    private var topBar: some View {
        HStack {
            IconButton(symbol: "xmark") { onClose() }
            Spacer()
            VStack(spacing: 2) {
                Text("\(index + 1) / \(shots.shots.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if let current {
                    HStack(spacing: 4) {
                        if current.saved {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                        }
                        Text("\(current.width) × \(current.height) · \(Self.size(current.bytes))")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "trash", size: 52) { confirmDelete = true }

            if let current {
                ShareLink(item: shots.url(for: current)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(PressStyle())
            }

            Button {
                saveAll()
            } label: {
                ZStack {
                    if saving {
                        ProgressView().tint(.black)
                    } else {
                        Text(saveLabel)
                            .font(.headline)
                            .contentTransition(.numericText())
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressStyle(scale: 0.97))
            .disabled(saving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
    }

    private var saveLabel: String {
        let n = shots.unsaved.count
        if n == 0 { return "Tout est dans Photos" }
        return n == 1 ? "Enregistrer dans Photos" : "Tout enregistrer (\(n))"
    }

    private func saveAll() {
        let pending = shots.unsaved
        guard !pending.isEmpty else { confirmClear = true; return }
        saving = true
        Task {
            let ok = await shots.saveToPhotos(pending)
            saving = false
            if ok {
                Haptics.success()
                confirmClear = true
            } else {
                onMessage("Autorise l’ajout aux photos dans Réglages → Pose.")
            }
        }
    }

    private static func size(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return "\(Int(kb.rounded())) Ko" }
        return String(format: "%.1f Mo", kb / 1024).replacingOccurrences(of: ".", with: ",")
    }
}

/// Une photo décodée à la taille de l'écran, en arrière-plan.
private struct ShotImage: View {
    let shots: ShotStore
    let shot: Shot

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: shot.id) { image = await shots.displayImage(for: shot) }
    }
}
