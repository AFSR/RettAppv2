import SwiftUI
import ARKit

/// Wrapper UIKit pour exécuter une `ARFaceTrackingConfiguration` et émettre des points
/// de regard projetés sur l'écran.
///
/// **Pourquoi pas `ARSCNView.projectPoint(lookAtPoint)` ?** Apple documente lookAtPoint
/// comme un point sur un plan **3 m devant le visage**. Projeté à travers la caméra AR
/// (co-localisée avec l'écran), la variation angulaire est correcte mais la magnitude
/// est écrasée près du centre → le point bouge à peine. La calibration ne peut pas
/// rattraper si la plage d'entrée est aussi étroite.
///
/// **Approche retenue (toute la math en face-anchor LOCAL space)** :
/// 1. Récupérer `leftEyeTransform` et `rightEyeTransform` (déjà en face-anchor local)
/// 2. Position moyenne des yeux + direction de regard (axe -Z des yeux moyennée)
/// 3. Intersecter le rayon (origine = yeux moyens, direction = regard) avec un plan
///    virtuel z = 0,30 m en face-anchor local (≈ distance moyenne face↔écran)
/// 4. Mapper hit.x / hit.y (mètres) vers les points d'écran avec une plage présumée
///    ±0,05 m × ±0,10 m. Le calibrateur tap-based + le Kalman corrigent le résiduel.
///
/// Pas de conversion world space → on évite les ambiguïtés de signe d'axe Z entre les
/// versions/orientations.
final class ARFaceViewController: UIViewController, ARSessionDelegate {

    let arSession = ARSession()
    var onGazeUpdate: ((CGPoint) -> Void)?

    /// Distance virtuelle face ↔ plan d'intersection (m). Approximation de la
    /// distance face-écran lors d'une utilisation normale.
    private let assumedScreenDistance: Float = 0.30
    /// Demi-plage attendue du regard sur le plan virtuel (m).
    /// Le calibrateur (régression linéaire sur les taps) corrige le résiduel,
    /// donc la précision absolue ne compte pas.
    private let halfRangeX: Float = 0.05
    private let halfRangeY: Float = 0.10

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

        // Position moyenne des yeux (face-anchor LOCAL space)
        let leftPos = SIMD3<Float>(leftEye.columns.3.x, leftEye.columns.3.y, leftEye.columns.3.z)
        let rightPos = SIMD3<Float>(rightEye.columns.3.x, rightEye.columns.3.y, rightEye.columns.3.z)
        let avgEye = (leftPos + rightPos) / 2

        // Direction du regard : axe -Z des yeux (face-anchor local), moyennée et normalisée
        let leftFwd = -SIMD3<Float>(leftEye.columns.2.x, leftEye.columns.2.y, leftEye.columns.2.z)
        let rightFwd = -SIMD3<Float>(rightEye.columns.2.x, rightEye.columns.2.y, rightEye.columns.2.z)
        var gaze = leftFwd + rightFwd
        let lenSq = simd_length_squared(gaze)
        guard lenSq > 1e-6 else { return }
        gaze /= lenSq.squareRoot()

        // Plan virtuel à z = assumedScreenDistance (face-anchor local).
        // Si gaze.z proche de 0, on ne peut pas projeter — on utilise un fallback grossier
        // sur lookAtPoint pour ne pas bloquer le signal.
        let xLocal: Float
        let yLocal: Float
        if abs(gaze.z) > 1e-3 {
            let t = (assumedScreenDistance - avgEye.z) / gaze.z
            let hit = avgEye + t * gaze
            xLocal = hit.x
            yLocal = hit.y
        } else {
            // Fallback : lookAtPoint × scale
            let look = faceAnchor.lookAtPoint
            xLocal = look.x
            yLocal = look.y
        }

        // Mapping → points d'écran. La calibration tap absorbera le scale exact.
        let screen = UIScreen.main.bounds.size
        let xNorm = CGFloat(xLocal) / CGFloat(halfRangeX)        // ≈ [-1, 1]
        let yNorm = CGFloat(yLocal) / CGFloat(halfRangeY)        // ≈ [-1, 1], y up

        let xPoint = (xNorm * 0.5 + 0.5) * screen.width
        let yPoint = (1 - (yNorm * 0.5 + 0.5)) * screen.height   // flip y → écran y down

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
