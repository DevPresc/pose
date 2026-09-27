import SwiftUI

// MARK: - Déclencheur

/// Pendant le décompte, le rond devient un carré rouge « arrêter » et un anneau jaune se remplit.
struct ShutterButton: View {
    let counting: Bool
    let total: Int
    let disabled: Bool
    let action: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
                    .opacity(counting ? 1 : 0)
                RoundedRectangle(cornerRadius: counting ? 8 : 32, style: .continuous)
                    .fill(counting ? Theme.danger : Color.white)
                    .frame(width: counting ? 28 : 64, height: counting ? 28 : 64)
            }
            .frame(width: 80, height: 80)
            .animation(.strongOut(0.2), value: counting)
        }
        .buttonStyle(PressStyle(scale: 0.93))
        .disabled(disabled)
        .accessibilityLabel(counting ? "Annuler le retardateur" : "Déclencher")
        .onChange(of: counting) { _, now in
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { progress = 0 }
            if now, total > 0 {
                withAnimation(.linear(duration: Double(total))) { progress = 1 }
            }
        }
    }
}

// MARK: - Vignette de la pellicule

struct ThumbButton: View {
    let image: UIImage?
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .id(count)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 52, height: 52)
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color.white, in: Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Pellicule, \(count) photo\(count > 1 ? "s" : "")")
    }
}

// MARK: - Aides de cadrage

struct GridOverlay: View {
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
            .stroke(Color.white.opacity(0.26), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Deux repères fixes et une barre centrale qui suit l'horizon. Tout passe au jaune quand c'est droit.
struct LevelView: View {
    let angle: Double
    let isLevel: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let color = isLevel ? Theme.accent : Color.white.opacity(0.8)
            ZStack {
                HStack {
                    Capsule().fill(color).frame(width: w * 0.14, height: 2)
                    Spacer()
                    Capsule().fill(color).frame(width: w * 0.14, height: 2)
                }
                Capsule().fill(color)
                    .frame(width: w * 0.56, height: 2)
                    .rotationEffect(.degrees(isLevel ? 0 : -angle))
            }
            .frame(width: w, height: geo.size.height)
            .shadow(color: .black.opacity(0.35), radius: 1)
            .animation(.strongOut(0.16), value: isLevel)
        }
        .frame(height: 24)
        .allowsHitTesting(false)
    }
}

struct TipView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Cartes du tiroir des poses

struct PoseCard<Content: View>: View {
    let title: String
    var selected = false
    var showsDelete = false
    @ViewBuilder var content: () -> Content
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            VStack(spacing: 6) {
                Theme.surface2
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay { content() }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2)
                    }
                    .overlay(alignment: .topTrailing) {
                        if showsDelete {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 24, height: 24)
                                .background(Color(white: 0.28), in: Circle())
                                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                                .offset(x: 6, y: -6)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(selected ? Color.white : Theme.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressStyle(scale: 0.96))
    }
}

struct AddCard: View {
    let importing: Bool

    var body: some View {
        VStack(spacing: 6) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    if importing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            Text("Importer")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}
