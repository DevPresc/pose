import SwiftUI
import PhotosUI

struct ContentView: View {

    @StateObject private var cam = CameraModel()
    @StateObject private var store = OverlayStore()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showGrid = false
    @State private var hideUI = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var toDelete: PoseItem?

    // Valeurs de départ des gestes, capturées au premier onChanged.
    @State private var dragging = false
    @State private var baseX = 0.0
    @State private var baseY = 0.0
    @State private var scaling = false
    @State private var baseScale = 1.0
    @State private var rotating = false
    @State private var baseRotation = 0.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .opacity(hideUI ? 0 : 1)
                    .allowsHitTesting(!hideUI)

                Spacer(minLength: 0)
                viewfinder
                Spacer(minLength: 0)

                controls
                    .opacity(hideUI ? 0 : 1)
                    .allowsHitTesting(!hideUI)
            }

            if hideUI {
                VStack {
                    HStack {
                        Spacer()
                        iconButton("eye.slash", active: true) { hideUI = false }
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
            }

            if let error = cam.errorText {
                errorCard(error)
            }

            if cam.savedFlash {
                VStack {
                    Spacer()
                    Text("Enregistré dans Photos")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 180)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hideUI)
        .animation(.easeInOut(duration: 0.2), value: cam.savedFlash)
        .fullScreenCover(isPresented: reviewBinding) { reviewSheet }
        .confirmationDialog("Supprimer cette pose ?",
                            isPresented: Binding(get: { toDelete != nil },
                                                 set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let item = toDelete { store.remove(item) }
                toDelete = nil
            }
            Button("Annuler", role: .cancel) { toDelete = nil }
        }
        .onAppear {
            cam.start()
            cam.enableVolumeShutter()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                cam.start()
                cam.enableVolumeShutter()
            default:
                cam.disableVolumeShutter()
                cam.stop()
            }
        }
        .onChange(of: picks) { _, new in
            guard !new.isEmpty else { return }
            Task {
                await store.add(new)
                picks = []
            }
        }
    }

    // MARK: - Viseur

    private var viewfinder: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: cam.session)

                if let item = store.current, let image = store.image(for: item) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .opacity(store.opacity)
                        .scaleEffect(x: item.flipped ? -item.scale : item.scale,
                                     y: item.scale)
                        .rotationEffect(.degrees(item.rotation))
                        .offset(x: item.x, y: item.y)
                        .allowsHitTesting(false)
                }

                if showGrid {
                    GridOverlay().allowsHitTesting(false)
                }

                // Couche de gestes, sous les contrôles qui sont hors du cadre.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(magnifyGesture)
                    .simultaneousGesture(rotateGesture)
                    .onTapGesture(count: 2) { store.resetTransform() }

                if cam.countdown > 0 {
                    Text("\(cam.countdown)")
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.5,
                                      weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(radius: 24)
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipped()
    }

    // MARK: - Gestes

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard let item = store.current else { return }
                if !dragging { dragging = true; baseX = item.x; baseY = item.y }
                store.mutate {
                    $0.x = baseX + value.translation.width
                    $0.y = baseY + value.translation.height
                }
            }
            .onEnded { _ in dragging = false; store.persist() }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard let item = store.current else { return }
                if !scaling { scaling = true; baseScale = item.scale }
                store.mutate { $0.scale = min(6, max(0.15, baseScale * Double(value))) }
            }
            .onEnded { _ in scaling = false; store.persist() }
    }

    private var rotateGesture: some Gesture {
        RotationGesture()
            .onChanged { angle in
                guard let item = store.current else { return }
                if !rotating { rotating = true; baseRotation = item.rotation }
                store.mutate { $0.rotation = baseRotation + angle.degrees }
            }
            .onEnded { _ in rotating = false; store.persist() }
    }

    // MARK: - Barre du haut

    private var topBar: some View {
        HStack(spacing: 10) {
            iconButton("grid", active: showGrid) { showGrid.toggle() }
            iconButton("scribble", active: store.edgeMode) { store.edgeMode.toggle() }
            iconButton("arrow.left.and.right.righttriangle.left.righttriangle.right",
                       active: store.current?.flipped ?? false) {
                store.mutate { $0.flipped.toggle() }
                store.persist()
            }
            iconButton("arrow.counterclockwise", active: false) { store.resetTransform() }

            Spacer()

            iconButton("bolt.fill", active: cam.flashOn) { cam.flashOn.toggle() }
            iconButton("eye", active: false) { hideUI = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Contrôles du bas

    private var controls: some View {
        VStack(spacing: 14) {
            if cam.zoomOptions.count > 1 {
                HStack(spacing: 8) {
                    ForEach(cam.zoomOptions, id: \.self) { z in
                        Button {
                            cam.setZoom(z)
                        } label: {
                            Text(zoomLabel(z))
                                .font(.caption.weight(.semibold))
                                .frame(width: 44, height: 32)
                                .background(cam.currentZoom == z ? Color.white : Color.white.opacity(0.15),
                                            in: Capsule())
                                .foregroundStyle(cam.currentZoom == z ? .black : .white)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Text("Guide").font(.caption).foregroundStyle(.secondary)
                Slider(value: $store.opacity, in: 0...1)
                Text("\(Int(store.opacity * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 18)

            poseStrip

            HStack {
                Button { cam.cycleTimer() } label: {
                    Text(cam.timerSeconds == 0 ? "Off" : "\(cam.timerSeconds)s")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 54, height: 54)
                        .background(cam.timerSeconds == 0 ? Color.white.opacity(0.15) : Color.white,
                                    in: Circle())
                        .foregroundStyle(cam.timerSeconds == 0 ? .white : .black)
                }

                Spacer()

                Button {
                    if cam.countdown > 0 { cam.cancelCountdown() }
                    else { cam.capture(delay: cam.timerSeconds) }
                } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 74, height: 74)
                        Circle().fill(cam.countdown > 0 ? Color.red : Color.white)
                            .frame(width: 60, height: 60)
                    }
                }
                .disabled(!cam.isReady)

                Spacer()

                Button { cam.autoSave.toggle() } label: {
                    Text("Auto")
                        .font(.caption.weight(.semibold))
                        .frame(width: 54, height: 54)
                        .background(cam.autoSave ? Color.white : Color.white.opacity(0.15), in: Circle())
                        .foregroundStyle(cam.autoSave ? .black : .white)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 10)
    }

    private var poseStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    Button { store.selected = index } label: {
                        Group {
                            if let thumb = store.thumb(for: item) {
                                Image(uiImage: thumb).resizable().scaledToFill()
                            } else {
                                Color.white.opacity(0.1)
                            }
                        }
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(store.selected == index ? Color.white : .clear, lineWidth: 2)
                        )
                    }
                    .onLongPressGesture { toDelete = item }
                }

                PhotosPicker(selection: $picks, maxSelectionCount: 12, matching: .images) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        if store.importing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "plus").font(.title3)
                        }
                    }
                    .frame(width: 54, height: 54)
                }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 58)
    }

    // MARK: - Validation de la photo

    private var reviewBinding: Binding<Bool> {
        Binding(get: { cam.review != nil },
                set: { if !$0 { cam.discardReview() } })
    }

    private var reviewSheet: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if let image = cam.review {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack(spacing: 12) {
                    Button("Refaire") { cam.discardReview() }
                        .buttonStyle(BigButton(filled: false))
                    Button("Enregistrer") {
                        cam.saveCurrent { ok in if ok { cam.discardReview() } }
                    }
                    .buttonStyle(BigButton(filled: true))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
    }

    // MARK: - Pièces

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text("Pose").font(.largeTitle.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Réessayer") { cam.start() }
                .buttonStyle(BigButton(filled: true))
                .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func iconButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(active ? Color.white : Color.white.opacity(0.15), in: Circle())
                .foregroundStyle(active ? .black : .white)
        }
    }

    private func zoomLabel(_ z: Double) -> String {
        z == floor(z) ? "\(Int(z))×" : String(format: "%.1f×", z)
    }
}

// MARK: - Grille des tiers

private struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width, h = geo.size.height
                for i in 1...2 {
                    let x = w * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
                    let y = h * CGFloat(i) / 3
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
        }
    }
}

private struct BigButton: ButtonStyle {
    let filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(filled ? Color.white : Color.white.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(filled ? .black : .white)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
