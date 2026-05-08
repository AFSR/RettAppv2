import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// Génération + détection du QR code intégré au cahier de suivi.
///
/// **Génération** : `BookletQR.image(for: schema, size:)` produit un `UIImage`
/// contenant le QR code du payload JSON du schéma. Niveau de correction
/// d'erreur **H (30 %)** pour rester lisible même si l'impression bave ou si
/// la photo est légèrement floue.
///
/// **Détection** : `BookletQR.detect(in: image)` utilise Vision
/// (`VNDetectBarcodesRequest`) pour trouver le QR et son cadre dans l'image
/// scannée — la position du QR sert d'ancrage pour calculer toutes les
/// positions des cases à cocher.
enum BookletQR {

    // MARK: - Generation

    /// Génère un UIImage contenant le QR code du schéma, à la taille demandée
    /// (en pixels). Renvoie `nil` si l'encodage échoue.
    static func image(for schema: BookletSchema, sizeInPoints: CGFloat) -> UIImage? {
        guard let payload = schema.encodedJSON(),
              let data = payload.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "H"  // 30 % d'octets de correction d'erreur
        guard let ciImage = filter.outputImage else { return nil }
        // Le générateur Core Image produit une image très petite (1 pt par
        // module). On scale up sans interpolation pour garder les modules nets.
        let scale = sizeInPoints / ciImage.extent.width * UIScreen.main.scale
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
    }

    // MARK: - Detection

    /// Résultat de détection du QR dans une image scannée.
    struct DetectionResult {
        let schema: BookletSchema
        /// Cadre du QR dans l'image (origine bas-gauche, normalisé 0..1).
        let normalizedBounds: CGRect
        /// Cadre du QR dans l'image en pixels (origine haut-gauche).
        let pixelBounds: CGRect
    }

    /// Tente de détecter et de décoder le QR dans l'image fournie.
    static func detect(in image: UIImage) async -> DetectionResult? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        return await withCheckedContinuation { (cont: CheckedContinuation<DetectionResult?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(returning: nil)
                    return
                }
                guard let observations = request.results as? [VNBarcodeObservation] else {
                    cont.resume(returning: nil); return
                }
                let imageWidth = CGFloat(cgImage.width)
                let imageHeight = CGFloat(cgImage.height)
                for obs in observations {
                    guard obs.symbology == .qr,
                          let payload = obs.payloadStringValue,
                          let schema = BookletSchema.decode(payload) else { continue }
                    // Vision retourne des coords normalisées 0..1, origine bas-gauche.
                    // On convertit en pixels origine haut-gauche pour le sampler.
                    let nb = obs.boundingBox
                    let pixelBounds = CGRect(
                        x: nb.minX * imageWidth,
                        y: (1.0 - nb.maxY) * imageHeight,
                        width: nb.width * imageWidth,
                        height: nb.height * imageHeight
                    )
                    cont.resume(returning: DetectionResult(
                        schema: schema,
                        normalizedBounds: nb,
                        pixelBounds: pixelBounds
                    ))
                    return
                }
                cont.resume(returning: nil)
            }
        }
    }
}
