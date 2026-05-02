import SwiftUI
import ARKit
import os.log

/// Wrapper UIKit pour exécuter une `ARFaceTrackingConfiguration` et émettre des points
/// de regard projetés sur l'écran.
///
/// Voir le commit history pour les itérations précédentes (lookAtPoint via
/// ARSCNView.projectPoint, ray-plane intersection en world space). La version actuelle :
///
/// 1. Reste en **face-anchor LOCAL space** (pas de conversion world)
/// 2. Calcule la position moyenne et la direction de regard à partir des transforms
///    des deux yeux. Eye Z+ pointe vers l'arrière du globe oculaire (convention Apple),
///    donc la direction du regard est `-columns.2`.
/// 3. Intersecte le rayon avec un plan virtuel à 30 cm (≈ distance face-écran)
/// 4. Mappe le hit (mètres) vers les points d'écran avec des half-ranges agressives
///    (le calibrateur tap absorbe le résiduel).
/// 5. Adapte les half-ranges à l'orientation : en paysage, on permute X et Y pour que
///    le mapping suive la nouvelle géométrie écran.
/// 6. **N'applique aucun guard** sur le signe / la magnitude → on émet à chaque frame,
///    quitte à ce que le point sorte temporairement de l'écran (le calibrateur corrige).
final class ARFaceViewController: UIViewController, ARSessionDelegate {

    private static let log = Logger(subsystem: "fr.afsr.RettApp", category: "EyeGame.AR")

    let arSession = ARSession()
    var onGazeUpdate: ((CGPoint) -> Void)?

    /// Distance assumée entre la face et le plan virtuel d'intersection (m).
    private let screenDistance: Float = 0.30

    /// Demi-plage attendue sur le plan virtuel (m). Diminuer = dot plus réactif.
    /// Le calibrateur tap-based corrige le scale réel.
    private let halfRangePortraitX: Float = 0.025   // largeur en mètres
    private let halfRangePortraitY: Float = 0.05    // hauteur en mètres

    private var lastLogTime: CFTimeInterval = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        arSession.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        if #available(iOS 13.0, *) {
            config.maximumNumberOfTrackedFaces = 1
        }
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arSession.pause()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              faceAnchor.isTracked else { return }

        let leftEye = faceAnchor.leftEyeTransform
        let rightEye = faceAnchor.rightEyeTransform

        let leftPos = SIMD3<Float>(leftEye.columns.3.x, leftEye.columns.3.y, leftEye.columns.3.z)
        let rightPos = SIMD3<Float>(rightEye.columns.3.x, rightEye.columns.3.y, rightEye.columns.3.z)
        let avgEye = (leftPos + rightPos) / 2

        // Eye Z+ pointe vers l'arrière du globe → gaze = -Z
        let leftFwd = -SIMD3<Float>(leftEye.columns.2.x, leftEye.columns.2.y, leftEye.columns.2.z)
        let rightFwd = -SIMD3<Float>(rightEye.columns.2.x, rightEye.columns.2.y, rightEye.columns.2.z)
        var gaze = leftFwd + rightFwd
        let lenSq = simd_length_squared(gaze)
        guard lenSq > 1e-6 else { return }
        gaze /= lenSq.squareRoot()

        // Intersection avec le plan z = screenDistance dans face-anchor local
        let xLocal: Float
        let yLocal: Float
        if abs(gaze.z) > 1e-3 {
            let t = (screenDistance - avgEye.z) / gaze.z
            // On ne filtre PAS sur t. Si la projection est hors plage raisonnable,
            // on émet quand même — la calibration sera capable d'ajuster.
            let hit = avgEye + t * gaze
            xLocal = hit.x
            yLocal = hit.y
        } else {
            // Fallback sur lookAtPoint (à 3 m, scaler agressivement)
            let look = faceAnchor.lookAtPoint
            xLocal = look.x / 10   // ramène à l'échelle ~30cm
            yLocal = look.y / 10
        }

        // Adaptation orientation : en paysage, écran large × peu haut → permuter ranges.
        let bounds = UIScreen.main.bounds
        let isLandscape = bounds.width > bounds.height
        let halfX = isLandscape ? halfRangePortraitY : halfRangePortraitX
        let halfY = isLandscape ? halfRangePortraitX : halfRangePortraitY

        let xNorm = CGFloat(xLocal) / CGFloat(halfX)        // ≈ [-1, 1]
        let yNorm = CGFloat(yLocal) / CGFloat(halfY)        // ≈ [-1, 1]

        let xPoint = (xNorm * 0.5 + 0.5) * bounds.width
        let yPoint = (1 - (yNorm * 0.5 + 0.5)) * bounds.height

        // Diagnostic léger : log toutes les 2 secondes max pour ne pas inonder.
        let now = CACurrentMediaTime()
        if now - lastLogTime > 2.0 {
            lastLogTime = now
            Self.log.info(
                "gaze x=\(xLocal, format: .fixed(precision: 3)) y=\(yLocal, format: .fixed(precision: 3)) → screen \(Int(xPoint))/\(Int(yPoint))  (orient \(isLandscape ? "L" : "P"))"
            )
        }

        let screenPoint = CGPoint(x: xPoint, y: yPoint)
        DispatchQueue.main.async { [weak self] in
            self?.onGazeUpdate?(screenPoint)
        }
    }
}

/// Représentable SwiftUI pour le tracking facial.
struct ARFaceView: UIViewControllerRepresentable {
    let onGazeUpdate: (CGPoint) -> Void

    func makeUIViewController(context: Context) -> ARFaceViewController {
        let vc = ARFaceViewController()
        vc.onGazeUpdate = onGazeUpdate
        return vc
    }

    func updateUIViewController(_ vc: ARFaceViewController, context: Context) {
        vc.onGazeUpdate = onGazeUpdate
    }
}
