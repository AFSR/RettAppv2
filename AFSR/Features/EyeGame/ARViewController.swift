import SwiftUI
import ARKit
import SceneKit

/// Wrapper UIKit pour exécuter une ARFaceTrackingConfiguration et émettre des points de regard.
final class ARFaceViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    var arView: ARSCNView!
    var onGazeUpdate: ((CGPoint) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        arView = ARSCNView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.isHidden = true // caméra cachée : seul le regard nous intéresse
        arView.session.delegate = self
        arView.delegate = self
        view.addSubview(arView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arView?.session.pause()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

        // lookAtPoint est exprimé dans l'espace de l'ancre faciale.
        // On le transforme en espace monde puis on projette sur l'écran.
        let lookLocal = faceAnchor.lookAtPoint
        let worldTransform = faceAnchor.transform
        let lookWorld = worldTransform * simd_float4(lookLocal.x, lookLocal.y, lookLocal.z, 1)
        let worldVector = SCNVector3(lookWorld.x, lookWorld.y, lookWorld.z)

        let projected = arView.projectPoint(worldVector)
        let screenPoint = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))

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

// MARK: - simd_float4x4 * simd_float4 helper

@inline(__always)
private func *(lhs: simd_float4x4, rhs: simd_float4) -> simd_float4 {
    simd_mul(lhs, rhs)
}
