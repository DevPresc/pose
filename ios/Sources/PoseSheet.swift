import SwiftUI
import PhotosUI

/// Tiroir des poses : le pack intégré, puis les références importées.
struct PoseSheet: View {
    @ObservedObject var store: OverlayStore
    let onPick: (PoseKey) -> Void

    @State private var editing = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var toDelete: PoseItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Poses").font(.title3.bold())
                    Spacer()
                    if !store.items.isEmpty {
                        Button(editing ? "OK" : "Modifier") {
                            withAnimation(.strongOut()) { editing.toggle() }
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.top, 22)
                .padding(.horizontal, 4)

                header("Pack de départ")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(PosePack.all) { pose in
                        PoseCard(title: pose.name, selected: store.current == .builtin(pose.id)) {
                            SkeletonView(pose: pose).padding(10)
                        } action: {
                            onPick(.builtin(pose.id))
                        }
                    }
                }

                header("Mes références")
                LazyVGrid(columns: columns, spacing: 12) {
                    PhotosPicker(selection: $picks, maxSelectionCount: 12, matching: .images) {
                        AddCard(importing: store.importing)
                    }
                    .buttonStyle(PressStyle(scale: 0.96))

                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        PoseCard(title: "Réf. \(index + 1)",
                                 selected: store.current == .user(item.id),
                                 showsDelete: editing) {
                            if let thumb = store.thumb(for: item) {
                                Image(uiImage: thumb).resizable().scaledToFill()
                            }
                        } action: {
                            if editing { toDelete = item } else { onPick(.user(item.id)) }
                        }
                    }
                }

                Text("Importe une capture Instagram ou Pinterest. Le mode **contours** ne garde que les lignes de la référence, sans son fond.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 18)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .onChange(of: picks) { _, new in
            guard !new.isEmpty else { return }
            Task {
                let key = await store.add(new)
                picks = []
                if let key { onPick(key) }
            }
        }
        .onChange(of: store.items.isEmpty) { _, empty in
            if empty { editing = false }
        }
        .confirmationDialog("Supprimer cette référence ?",
                            isPresented: Binding(get: { toDelete != nil },
                                                 set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let item = toDelete {
                    withAnimation(.strongOut()) { store.remove(item) }
                }
                toDelete = nil
            }
            Button("Annuler", role: .cancel) { toDelete = nil }
        } message: {
            Text("Elle sera retirée de ta bibliothèque de poses.")
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.muted)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .padding(.horizontal, 4)
    }
}
