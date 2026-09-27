import SwiftUI

/// Une pose du pack intégré : un squelette (articulations) et un conseil.
struct BuiltinPose: Identifiable, Equatable {
    let id: String
    let name: String
    let tip: String
    let joints: [String: CGPoint]
}

/// Mêmes squelettes que la PWA. Repère : viewBox (-20, -20, 240, 420).
enum PosePack {

    private static let base: [String: CGPoint] = [
        "head": CGPoint(x: 100, y: 55), "neck": CGPoint(x: 100, y: 82),
        "lsh": CGPoint(x: 76, y: 92), "rsh": CGPoint(x: 124, y: 92),
        "hip": CGPoint(x: 100, y: 200), "lhip": CGPoint(x: 89, y: 202), "rhip": CGPoint(x: 111, y: 202),
    ]

    private static func make(_ id: String, _ name: String, _ tip: String,
                             _ joints: [String: [CGFloat]]) -> BuiltinPose {
        var all = base
        for (key, xy) in joints where xy.count == 2 {
            all[key] = CGPoint(x: xy[0], y: xy[1])
        }
        return BuiltinPose(id: id, name: name, tip: tip, joints: all)
    }

    static let all: [BuiltinPose] = [
        make("casual", "Décontracté·e",
             "Poids sur une jambe, mains dans les poches, épaules basses.",
             ["lel": [70, 145], "lwr": [86, 194], "rel": [130, 145], "rwr": [114, 194],
              "lkn": [86, 290], "lan": [84, 378], "rkn": [118, 288], "ran": [128, 372]]),

        make("walk", "La marche",
             "Marche lentement vers l’objectif en regardant ailleurs. Active la rafale.",
             ["head": [102, 55], "lsh": [77, 92], "rsh": [123, 92],
              "hip": [100, 198], "lhip": [89, 200], "rhip": [111, 200],
              "lel": [70, 142], "lwr": [74, 190], "rel": [132, 140], "rwr": [140, 186],
              "lkn": [82, 285], "lan": [88, 372], "rkn": [122, 280], "ran": [112, 360]]),

        make("shoulder", "Par-dessus l’épaule",
             "Dos à l’objectif, tourne seulement la tête et une épaule.",
             ["head": [114, 57], "neck": [102, 82], "rsh": [126, 88],
              "lel": [72, 146], "lwr": [74, 198], "rel": [128, 146], "rwr": [126, 198],
              "lkn": [90, 290], "lan": [90, 378], "rkn": [114, 290], "ran": [116, 378]]),

        make("open", "Face au paysage",
             "Bras ouverts vers le ciel. Le photographe se baisse pour allonger la silhouette.",
             ["lel": [46, 48], "lwr": [24, 4], "rel": [154, 48], "rwr": [176, 4],
              "lkn": [80, 290], "lan": [70, 378], "rkn": [120, 290], "ran": [130, 378]]),

        make("lean", "Appuyé·e",
             "Un coude sur une rambarde, chevilles croisées, regard au loin.",
             ["head": [86, 58], "neck": [92, 84], "lsh": [70, 96], "rsh": [116, 90],
              "hip": [104, 200], "lhip": [93, 202], "rhip": [115, 198],
              "lel": [58, 148], "lwr": [52, 196], "rel": [150, 128], "rwr": [170, 168],
              "lkn": [100, 288], "lan": [122, 376], "rkn": [118, 286], "ran": [100, 378]]),

        make("seated", "Assis·e",
             "Sur une marche, dos droit, mains jointes entre les genoux.",
             ["head": [100, 120], "neck": [100, 146], "lsh": [78, 156], "rsh": [122, 156],
              "hip": [100, 258], "lhip": [89, 260], "rhip": [111, 260],
              "lel": [70, 208], "lwr": [96, 248], "rel": [130, 208], "rwr": [104, 248],
              "lkn": [72, 282], "lan": [78, 370], "rkn": [128, 280], "ran": [122, 368]]),

        make("hair", "Main dans les cheveux",
             "Une main dans les cheveux, l’autre relâchée, regard hors champ.",
             ["head": [96, 56], "rel": [150, 52], "rwr": [116, 30], "lel": [70, 146], "lwr": [74, 198],
              "lkn": [88, 290], "lan": [86, 378], "rkn": [114, 288], "ran": [124, 374]]),

        make("point", "Regarde là-bas",
             "Montre un détail hors champ et suis-le du regard.",
             ["head": [92, 56], "lel": [30, 76], "lwr": [-8, 58], "rel": [148, 140], "rwr": [118, 184],
              "lkn": [84, 290], "lan": [78, 378], "rkn": [116, 290], "ran": [122, 378]]),
    ]

    static func pose(_ id: String) -> BuiltinPose? {
        all.first { $0.id == id }
    }
}

/// Le squelette en tracé vectoriel, ajusté au rectangle en conservant les proportions.
struct SkeletonShape: Shape {
    let joints: [String: CGPoint]

    static let viewBox = CGRect(x: -20, y: -20, width: 240, height: 420)
    static let headRadius: CGFloat = 19

    func path(in rect: CGRect) -> Path {
        let vb = Self.viewBox
        let s = min(rect.width / vb.width, rect.height / vb.height)
        let ox = rect.midX - vb.midX * s
        let oy = rect.midY - vb.midY * s

        func p(_ key: String) -> CGPoint {
            let q = joints[key] ?? .zero
            return CGPoint(x: ox + q.x * s, y: oy + q.y * s)
        }

        var path = Path()
        func chain(_ keys: [String]) {
            guard let first = keys.first else { return }
            path.move(to: p(first))
            for key in keys.dropFirst() { path.addLine(to: p(key)) }
        }

        chain(["lwr", "lel", "lsh", "rsh", "rel", "rwr"])

        // Le cou part du bord de la tête, pas de son centre.
        let head = p("head"), neck = p("neck"), r = Self.headRadius * s
        let dx = neck.x - head.x, dy = neck.y - head.y
        let d = max(0.001, (dx * dx + dy * dy).squareRoot())
        path.move(to: CGPoint(x: head.x + dx / d * r, y: head.y + dy / d * r))
        path.addLine(to: neck)
        path.addLine(to: p("hip"))

        chain(["lan", "lkn", "lhip", "rhip", "rkn", "ran"])
        path.addEllipse(in: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2))
        return path
    }
}

/// Trait blanc épais sur liseré sombre : lisible sur un ciel clair comme sur une rue sombre.
struct SkeletonView: View {
    let pose: BuiltinPose

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / SkeletonShape.viewBox.width,
                        geo.size.height / SkeletonShape.viewBox.height)
            ZStack {
                SkeletonShape(joints: pose.joints)
                    .stroke(Color.black.opacity(0.45),
                            style: StrokeStyle(lineWidth: 13 * s, lineCap: .round, lineJoin: .round))
                SkeletonShape(joints: pose.joints)
                    .stroke(Color.white,
                            style: StrokeStyle(lineWidth: 7 * s, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(SkeletonShape.viewBox.width / SkeletonShape.viewBox.height, contentMode: .fit)
    }
}
