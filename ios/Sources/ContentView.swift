import SwiftUI

struct ContentView: View {

    @StateObject private var cam = CameraModel()
    @StateObject private var store = OverlayStore()
    @StateObject private var shots = ShotStore()
    @StateObject private var level = LevelModel()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showGrid = UserDefaults.standard.bool(forKey: "grid")
    @State private var hideUI = false
    @State private var showSheet = false
    @State private var showViewer = false
    @State private var tip: String?
    @State private var tipTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var flash = false
    @State private var dockHeight: CGFloat = 250
    @State private var pillDrag: CGFloat = 0

    // Valeurs de départ des gestes, capturées au premier onChanged.
    @State private var dragging = false
    @State private var baseX = 0.0
    @State private var baseY = 0.0
    @State private var scaling = false
    @State private var baseScale = 1.0
    @State private var rotating = false
    @State private var baseRotation = 0.0

    var body: some View {
        GeometryReader { geo in
            let safe = Self.insets(geo.safeAreaInsets)
            let rect = frameRect(in: geo.size, top: safe.top)

            ZStack(alignment: .top) {
                Color.black

                viewfinder(size: rect.size)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                Color.white
                    .opacity(flash ? 0.45 : 0)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topBar.padding(.top, safe.top + 8)
                    Spacer(minLength: 0)
                    dock
                        .padding(.bottom, safe.bottom + 14)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: HeightKey.self, value: g.size.height)
                        })
                }
                .opacity(hideUI ? 0 : 1)
                .allowsHitTesting(!hideUI)

                if hideUI {
                    HStack {
                        Spacer()
                        IconButton(symbol: "eye", active: true) {
                            withAnimation(.strongOut()) { hideUI = false }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, safe.top + 8)
                    .transition(.opacity)
                }

                if let toast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.bottom, dockHeight + 10)
                            .padding(.horizontal, 24)
                    }
                    .transition(.opacity.combined(with: .offset(y: 8)))
                    .allowsHitTesting(false)
                }

                if let error = cam.errorText {
                    errorCard(error)
                }
            }
            .animation(.strongInOut(0.36), value: cam.ratio)
            .animation(.strongOut(0.2), value: hideUI)
        }
        .ignoresSafeArea()
        .onPreferenceChange(HeightKey.self) { dockHeight = $0 }
        .sheet(isPresented: $showSheet) {
            PoseSheet(store: store) { key in
                select(key)
                showSheet = false
            }
            .presentationDetents([.fraction(0.82), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
            .presentationBackground(.thinMaterial)
        }
        .fullScreenCover(isPresented: $showViewer) {
            ViewerView(shots: shots, onClose: { showViewer = false }, onMessage: { text in showToast(text) })
        }
        .onAppear(perform: activate)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { activate() } else { deactivate() }
        }
        .onChange(of: showGrid) { _, on in UserDefaults.standard.set(on, forKey: "grid") }
    }

    // MARK: - Cycle de vie

    private func activate() {
        cam.onPhoto = { output in
            let shot = withAnimation(.strongOut(0.24)) { shots.add(output) }
            if cam.autoSave, let shot {
                Task { _ = await shots.saveToPhotos([shot]) }
            }
        }
        cam.onMessage = { text in showToast(text) }
        cam.start()
        cam.enableVolumeShutter()
        // Écran allumé pendant la séance : indispensable avec le retardateur.
        UIApplication.shared.isIdleTimerDisabled = true
        if tip == nil { showTip(store.currentTip) }
    }

    private func deactivate() {
        cam.disableVolumeShutter()
        cam.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Cadre

    /// Même logique que la PWA : le cadre se loge entre la barre du haut et le dock ;
    /// s'il ne tient pas, il glisse sous le dock plutôt que de rétrécir.
    private func frameRect(in size: CGSize, top: CGFloat) -> CGRect {
        let r = cam.ratio.value
        var w = size.width, h = size.width / r
        if h > size.height { h = size.height; w = h * r }
        let topEdge = top + 56
        let dockTop = size.height - dockHeight + 24
        let avail = dockTop - topEdge
        let y: CGFloat
        if cam.ratio == .r916 {
            y = (size.height - h) / 2
        } else if h <= avail {
            y = topEdge + (avail - h) / 2
        } else {
            y = max(0, min(topEdge, (size.height - h) / 2))
        }
        return CGRect(x: (size.width - w) / 2, y: y, width: w, height: h)
    }

    // MARK: - Viseur

    private func viewfinder(size: CGSize) -> some View {
        ZStack {
            CameraPreview(session: cam.session)

            guideLayer

            if showGrid { GridOverlay().transition(.opacity) }

            if level.enabled && !level.isFlat {
                LevelView(angle: level.angle, isLevel: level.isLevel)
                    .frame(width: size.width * 0.64)
                    .transition(.opacity)
            }

            // Couche de gestes, sous les contrôles qui sont hors du cadre.
            Color.clear
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .simultaneousGesture(magnifyGesture)
                .simultaneousGesture(rotateGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.strongInOut(0.32)) { store.resetTransform() }
                }

            VStack {
                if let tip {
                    TipView(text: tip)
                        .onTapGesture { withAnimation(.strongOut()) { self.tip = nil } }
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }
                Spacer()
                if cam.burstIndex > 0 {
                    Text("\(cam.burstIndex) / \(cam.burst)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.opacity)
                }
            }
            .padding(12)

            if cam.countdown > 0 {
                Text("\(cam.countdown)")
                    .font(.system(size: min(size.width, size.height) * 0.42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .shadow(color: .black.opacity(0.5), radius: 24)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 1.2)))
            }
        }
        .clipped()
        .animation(.strongOut(), value: cam.countdown)
        .animation(.strongOut(), value: cam.burstIndex)
        .animation(.strongOut(), value: showGrid)
        .animation(.strongOut(), value: level.enabled)
    }

    @ViewBuilder
    private var guideLayer: some View {
        let t = store.transform
        ZStack {
            if let pose = store.currentBuiltin {
                SkeletonView(pose: pose)
            } else if let item = store.currentUser, let image = store.image(for: item) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .id(store.current?.raw ?? "none")
        .transition(.blurReplace)
        .opacity(store.opacity)
        .scaleEffect(x: t.flipped ? -t.scale : t.scale, y: t.scale)
        .rotationEffect(.degrees(t.rotation))
        .offset(x: t.x, y: t.y)
        .allowsHitTesting(false)
    }

    // MARK: - Gestes sur le guide

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !dragging { dragging = true; baseX = store.transform.x; baseY = store.transform.y }
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
                if !scaling { scaling = true; baseScale = store.transform.scale }
                store.mutate { $0.scale = min(6, max(0.15, baseScale * Double(value))) }
            }
            .onEnded { _ in scaling = false; store.persist() }
    }

    private var rotateGesture: some Gesture {
        RotationGesture()
            .onChanged { angle in
                if !rotating { rotating = true; baseRotation = store.transform.rotation }
                store.mutate { $0.rotation = baseRotation + angle.degrees }
            }
            .onEnded { _ in rotating = false; store.persist() }
    }

    // MARK: - Barre du haut

    private var topBar: some View {
        HStack(spacing: 8) {
            IconButton(symbol: "squareshape.split.3x3", active: showGrid) { showGrid.toggle() }
            IconButton(symbol: "level", active: level.enabled) { level.enabled.toggle() }

            Spacer()

            Button {
                Haptics.tap()
                cam.ratio = cam.ratio.next
                showToast("\(cam.ratio.rawValue) · \(cam.ratio.note)")
            } label: {
                Text(cam.ratio.rawValue)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Format \(cam.ratio.rawValue)")

            Spacer()

            IconButton(symbol: "timer", active: cam.timerSeconds > 0,
                       badge: cam.timerSeconds > 0 ? "\(cam.timerSeconds)" : nil) {
                cam.cycleTimer()
                showToast(cam.timerSeconds > 0 ? "Retardateur \(cam.timerSeconds) s" : "Retardateur désactivé")
            }
            IconButton(symbol: "square.stack.3d.up", active: cam.burst > 1,
                       badge: cam.burst > 1 ? "\(cam.burst)" : nil) {
                cam.cycleBurst()
                showToast(cam.burst > 1 ? "Rafale de \(cam.burst) photos" : "Rafale désactivée")
            }

            Menu {
                Toggle(isOn: $cam.flashOn) { Label("Flash", systemImage: "bolt.fill") }
                Toggle(isOn: $cam.autoSave) {
                    Label("Enregistrer direct dans Photos", systemImage: "square.and.arrow.down")
                }
                Divider()
                Button {
                    withAnimation(.strongOut()) { hideUI = true }
                } label: {
                    Label("Masquer l’interface", systemImage: "eye.slash")
                }
            } label: {
                Image(systemName: cam.flashOn ? "bolt.fill" : "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(cam.flashOn || cam.autoSave ? Theme.accent : Color.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Plus de réglages")
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Dock

    private var dock: some View {
        VStack(spacing: 12) {
            if cam.zoomOptions.count > 1 {
                lensBar.transition(.opacity)
            }
            posePill
            guideRow
            HStack {
                ThumbButton(image: shots.lastThumb, count: shots.shots.count) {
                    if shots.shots.isEmpty { showToast("Pas encore de photo.") } else { showViewer = true }
                }
                Spacer()
                ShutterButton(counting: cam.countdown > 0, total: cam.countdownTotal, disabled: !cam.isReady) {
                    cam.capture()
                }
                Spacer()
                IconButton(symbol: "arrow.triangle.2.circlepath.camera", size: 52) {
                    cam.switchCamera()
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
        )
        .onChange(of: shots.shots.count) { old, new in
            guard new > old else { return }
            withAnimation(.easeOut(duration: 0.05)) { flash = true }
            withAnimation(.easeOut(duration: 0.26).delay(0.05)) { flash = false }
        }
    }

    private var lensBar: some View {
        HStack(spacing: 6) {
            ForEach(cam.zoomOptions, id: \.self) { z in
                let on = cam.currentZoom == z
                Button {
                    Haptics.select()
                    cam.setZoom(z)
                } label: {
                    Text(zoomLabel(z, active: on))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(on ? Theme.accent : Color.white)
                        .frame(minWidth: 34, minHeight: 30)
                        .padding(.horizontal, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.28), in: Capsule())
        .animation(.strongOut(), value: cam.currentZoom)
    }

    private var posePill: some View {
        HStack(spacing: 10) {
            ZStack {
                if let pose = store.currentBuiltin {
                    SkeletonView(pose: pose).padding(4)
                } else if let item = store.currentUser, let thumb = store.thumb(for: item) {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    Image(systemName: "figure.stand").foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(0.08))
            .clipShape(Circle())

            Text(store.currentName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .id(store.current?.raw ?? "")
                .transition(.blurReplace)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .contentShape(Capsule())
        .offset(x: pillDrag * 0.35)
        .onTapGesture {
            Haptics.tap()
            showSheet = true
        }
        // Balayer la pastille : pose suivante / précédente.
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { pillDrag = $0.translation.width }
                .onEnded { value in
                    let dx = value.translation.width
                    if abs(dx) > 40 || abs(value.predictedEndTranslation.width) > 140 {
                        withAnimation(.strongOut()) { store.cycle(dx < 0 ? 1 : -1) }
                        Haptics.select()
                        showTip(store.currentTip)
                    }
                    withAnimation(.strongOut()) { pillDrag = 0 }
                }
        )
        .accessibilityLabel("Pose : \(store.currentName). Toucher pour changer.")
    }

    private var guideRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Slider(value: $store.opacity, in: 0.1...1)
                    .tint(.white)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())

            Text("\(Int((store.opacity * 100).rounded())) %")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.muted)
                .frame(width: 40, alignment: .trailing)

            // Le pack est déjà en traits : les contours ne concernent que les références importées.
            IconButton(symbol: "scribble.variable", active: store.isUserPose && store.edgeMode,
                       size: 36, disabled: !store.isUserPose) {
                store.edgeMode.toggle()
            }
            IconButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                       active: store.transform.flipped, size: 36, disabled: store.current == nil) {
                store.mutate { $0.flipped.toggle() }
                store.persist()
            }
        }
        .frame(maxWidth: 420)
    }

    // MARK: - Pièces

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.accent)
                .frame(width: 72, height: 72)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Pose").font(.largeTitle.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 32)
            Button {
                cam.start()
            } label: {
                Text("Réessayer")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(width: 220, height: 50)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressStyle(scale: 0.97))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func select(_ key: PoseKey) {
        withAnimation(.strongOut(0.24)) { store.current = key }
        showTip(store.currentTip)
    }

    private func showTip(_ text: String) {
        tipTask?.cancel()
        withAnimation(.strongOut()) { tip = text }
        tipTask = Task {
            try? await Task.sleep(nanoseconds: 5_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.strongOut()) { tip = nil }
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.strongOut()) { toast = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.strongOut(0.18)) { toast = nil }
        }
    }

    /// Marges de sécurité (Dynamic Island, barre d'accueil), avec la fenêtre en repli.
    private static func insets(_ proxy: EdgeInsets) -> EdgeInsets {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let w = scene?.keyWindow?.safeAreaInsets ?? .zero
        return EdgeInsets(top: max(proxy.top, w.top), leading: 0,
                          bottom: max(proxy.bottom, w.bottom), trailing: 0)
    }

    private func zoomLabel(_ z: Double, active: Bool) -> String {
        let base = z < 1 ? ".5" : "\(Int(z))"
        return active ? base + "×" : base
    }
}
