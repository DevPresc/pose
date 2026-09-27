import SwiftUI
import UIKit

/// Un seul accent (le jaune de l'app Appareil photo), réservé aux états actifs.
enum Theme {
    static let accent = Color(red: 1, green: 214 / 255, blue: 10 / 255)
    static let accentBG = Color(red: 1, green: 214 / 255, blue: 10 / 255).opacity(0.18)
    static let danger = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    static let muted = Color.white.opacity(0.62)
    static let surface = Color(white: 0.11)
    static let surface2 = Color(white: 0.17)
}

extension Animation {
    /// Ease-out marqué : entrées, retours d'appui. Démarre vite, donc paraît réactif.
    static func strongOut(_ duration: Double = 0.22) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }
    /// Ease-in-out marqué : éléments qui se déplacent ou se redimensionnent à l'écran.
    static func strongInOut(_ duration: Double = 0.36) -> Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: duration)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func shutter() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// Tout ce qui se presse rétrécit légèrement : l'interface confirme qu'elle a entendu.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.strongOut(0.14), value: configuration.isPressed)
    }
}

/// Bouton rond vitré, avec état actif jaune et pastille optionnelle.
struct IconButton: View {
    let symbol: String
    var active = false
    var size: CGFloat = 40
    var badge: String? = nil
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(active ? Theme.accent : Color.white)
                .frame(width: size, height: size)
                .background {
                    Circle().fill(.ultraThinMaterial)
                    if active { Circle().fill(Theme.accentBG) }
                }
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Theme.accent, in: Capsule())
                            .offset(x: 4, y: -4)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(.strongOut(0.18), value: badge)
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

/// Rangée d'une grille, relevée pour mesurer la hauteur d'un bloc.
struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
