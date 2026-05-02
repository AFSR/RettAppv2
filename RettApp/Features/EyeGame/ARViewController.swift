import SwiftUI
import ARKit

/// Wrapper UIKit pour exécuter une `ARFaceTrackingConfiguration` et émettre des points
/// de regard projetés sur l'écran.
///
/// Pourquoi pas `ARSCNView` ? Précédemment on utilisait `ARSCNView.projectPoint(faceAnchor.lookAtPoint)`,
/// mais `lookAtPoint` est documenté comme un point sur un plan **3 m devant le visage**
/// (Apple docs). La variation angulaire reste la même quelle que soit la distance, mais
/// la projection à travers la caméra AR (caméra co-localisée avec l'écran) écrase la
/// plage de variation autour du centre de l'écran → le point bouge à peine.
///
/// Approche correcte (utilisée ici) :
/// 1. Récupérer les transforms `leftEyeTransform` / `rightEyeTransform` (face-anchor space)
/// 2. Les passer en world space via `faceAnchor.transform`
/// 3. Calculer la direction du regard (axe -Z des yeux moyennée)
/// 4. Intersecter le rayon (origine = position moyenne des yeux, direction = regard)
///    avec le plan z = 0 du référentiel monde (= plan de l'écran, l'origine de l'AR session
///    étant la caméra frontale au démarrage, qui est sur la même surface que l'écran)
/// 5. Convertir le point d'intersection (mètres) en points d'écran via les dimensions
///    physiques approximatives du device (la calibration tap-based corrige le résiduel)
final class ARFaceViewController: UIViewController, ARSessionDelegate {

    let arSession = ARSession()
    var onGazeUpdate: ((CGPoint) -> Void)?

    /// Dimensions approximatives de l'écran en mètres, utilisées pour convertir
    /// les coordonnées du plan d'intersection en points d'écran.
    /// La calibration utilisateur (taps) corrige le résiduel ; ces valeurs servent
    /// juste à produire une plage de variation plausible.
    private var physicalScreenSize: SIMD2<Float> {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return SIMD2<Float>(0.197, 0.262)   // ≈ iPad de 11"
        }
        return SIMD2<Float>(0.071, 0.155)        // ≈ iPhone 15 / Pro
    }

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

        let faceTransform = faceAnchor.transform

        // Eye transforms en world space
        let leftEyeWorld = simd_mul(faceTransform, faceAnchor.leftEyeTransform)
        let rightEyeWorld = simd_mul(faceTransform, faceAnchor.rightEyeTransform)

        // Position moyenne des yeux (world)
        let leftPos = SIMD3<Float>(leftEyeWorld.columns.3.x, leftEyeWorld.columns.3.y, leftEyeWorld.columns.3.z)
        let rightPos = SIMD3<Float>(rightEyeWorld.columns.3.x, rightEyeWorld.columns.3.y, rightEyeWorld.columns.3.z)
        let eyePos = (leftPos + rightPos) / 2

        // Direction du regard : axe -Z de chaque transform œil (en world), moyennée et normalisée
        let leftFwd = -SIMD3<Float>(leftEyeWorld.columns.2.x, leftEyeWorld.columns.2.y, leftEyeWorld.columns.2.z)
        let rightFwd = -SIMD3<Float>(rightEyeWorld.columns.2.x, rightEyeWorld.columns.2.y, rightEyeWorld.columns.2.z)
        let gaze = simd_normalize(leftFwd + rightFwd)

        // Le user regarde l'écran → la direction du regard a un -Z significatif
        // (l'origine du monde est la caméra ; la face est à +Z, regarder l'écran = direction -Z)
        guard gaze.z < -0.01 else { return }
        // Intersection avec le plan z = 0 : t = -eyePos.z / gaze.z
        let t = -eyePos.z / gaze.z
        guard t > 0, t < 5 else { return } // sanity 0..5m

        let hit = eyePos + t * gaze
        // hit.x / hit.y sont en world space sur le plan de l'écran (en mètres)
        // - x positif : vers la droite de l'utilisateur en mode portrait
        // - y positif : vers le haut → la caméra étant en haut du téléphone, l'écran s'étend
        //   en y NÉGATIF (du haut au bas)

        let physical = physicalScreenSize
        let screenSize = UIScreen.main.bounds.size

        // Mapping x : hit.x ∈ [-w/2, +w/2] → [0, screenWidth]
        let xNorm = CGFloat(hit.x) / CGFloat(physical.x) + 0.5
        let xPoint = xNorm * screenSize.width

        // Mapping y : hit.y ∈ [-h, 0] (caméra en haut) → [screenHeight, 0]
        // Donc yPoint = -hit.y / h * screenHeight
        let yNorm = -CGFloat(hit.y) / CGFloat(physical.y)
        let yPoint = yNorm * screenSize.height

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
