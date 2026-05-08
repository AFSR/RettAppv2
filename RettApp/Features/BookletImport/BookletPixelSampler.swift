import CoreGraphics
import UIKit

/// Échantillonne l'intensité (gris) d'une image scannée à des positions
/// précises pour déterminer si chaque case est cochée.
///
/// Principe :
///   1. Le QR donne une référence connue (position en PDF + position détectée
///      dans l'image).
///   2. On en déduit la transformation PDF → image (échelle + décalage).
///   3. Pour chaque case (coordonnées PDF), on calcule sa position en pixels
///      et on lit la moyenne des pixels d'une petite fenêtre autour du
///      centre. Si l'intensité moyenne est suffisamment sombre (encre du
///      stylo de l'utilisateur), la case est considérée cochée.
///
/// L'image fournie par `VNDocumentCameraViewController` est déjà rectifiée
/// (perspective corrigée), donc une simple transformation affine suffit.
struct BookletPixelSampler {

    let image: CGImage
    let qrPDFRect: CGRect    // QR position dans le PDF (en pt)
    let qrImageRect: CGRect  // QR position détectée dans l'image (en px)

    /// Échelle PDF→image et offset (calculés une fois)
    private let scaleX: CGFloat
    private let scaleY: CGFloat
    private let offsetX: CGFloat
    private let offsetY: CGFloat

    /// Référence « papier blanc » de la page — moyenne de plusieurs zones
    /// connues pour être vides (marges blanches autour du QR). Sert à
    /// calibrer le seuil de détection : « cellule cochée » = significativement
    /// plus sombre que le papier de cette page. Plus robuste que le seuil
    /// absolu 0.85 : marche avec un mauvais éclairage / papier jaunâtre.
    let paperReference: CGFloat

    init?(image: UIImage, qrPDFRect: CGRect, qrImageRect: CGRect) {
        guard let cgImage = image.cgImage else { return nil }
        self.image = cgImage
        self.qrPDFRect = qrPDFRect
        self.qrImageRect = qrImageRect
        self.scaleX = qrImageRect.width / qrPDFRect.width
        self.scaleY = qrImageRect.height / qrPDFRect.height
        self.offsetX = qrImageRect.minX - qrPDFRect.minX * scaleX
        self.offsetY = qrImageRect.minY - qrPDFRect.minY * scaleY
        // Calibrage du blanc papier : on échantillonne 4 points dans les
        // marges (entre QR et bord, en bas à gauche, etc.) puis on prend la
        // valeur la plus claire (= la plus représentative du papier vierge).
        self.paperReference = 0  // placeholder, calculé juste après
        let samples: [CGFloat] = [
            // Coin haut-gauche (avant le bandeau date)
            BookletPixelSampler.sample(in: cgImage, scaleX: scaleX, scaleY: scaleY,
                                       offsetX: offsetX, offsetY: offsetY,
                                       at: CGPoint(x: 8, y: 8), halfPoints: 4),
            // Coin bas-gauche (sous les sections, marges de pied de page)
            BookletPixelSampler.sample(in: cgImage, scaleX: scaleX, scaleY: scaleY,
                                       offsetX: offsetX, offsetY: offsetY,
                                       at: CGPoint(x: 8, y: 830), halfPoints: 4),
            // Coin bas-droite
            BookletPixelSampler.sample(in: cgImage, scaleX: scaleX, scaleY: scaleY,
                                       offsetX: offsetX, offsetY: offsetY,
                                       at: CGPoint(x: 580, y: 830), halfPoints: 4),
            // Au-dessus du QR (entre QR et bord page)
            BookletPixelSampler.sample(in: cgImage, scaleX: scaleX, scaleY: scaleY,
                                       offsetX: offsetX, offsetY: offsetY,
                                       at: CGPoint(x: qrPDFRect.midX, y: 8), halfPoints: 4)
        ]
        // On prend la plus claire (papier blanc), ce qui rejette les
        // échantillons accidentellement tombés sur de l'encre.
        self.paperReference = samples.max() ?? 0.95
    }

    /// Convertit une position PDF (pt) en position image (px).
    func imagePoint(forPDFPoint p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scaleX + offsetX, y: p.y * scaleY + offsetY)
    }

    /// Renvoie l'intensité moyenne (0.0 noir → 1.0 blanc) d'une fenêtre
    /// carrée centrée sur `center` (en coords PDF), de demi-taille
    /// `halfSizePoints` (en pt PDF, sera converti en pixels).
    func averageIntensity(atPDFPoint center: CGPoint, halfSizePoints: CGFloat = 4) -> CGFloat {
        Self.sample(in: image, scaleX: scaleX, scaleY: scaleY,
                    offsetX: offsetX, offsetY: offsetY,
                    at: center, halfPoints: halfSizePoints)
    }

    /// Implementation partagée pour pouvoir l'appeler aussi avant que `self`
    /// soit complètement initialisé (calibration `paperReference`).
    static func sample(in image: CGImage,
                       scaleX: CGFloat, scaleY: CGFloat,
                       offsetX: CGFloat, offsetY: CGFloat,
                       at center: CGPoint, halfPoints: CGFloat) -> CGFloat {
        let imageCenter = CGPoint(x: center.x * scaleX + offsetX,
                                  y: center.y * scaleY + offsetY)
        let halfPixels = halfPoints * scaleX
        let rect = CGRect(
            x: imageCenter.x - halfPixels,
            y: imageCenter.y - halfPixels,
            width: halfPixels * 2,
            height: halfPixels * 2
        ).integral
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return 1.0 }
        guard let cropped = image.cropping(to: clipped) else { return 1.0 }

        let width = cropped.width
        let height = cropped.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixelData, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 1.0 }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalLuma: CGFloat = 0
        var count: Int = 0
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            let r = CGFloat(pixelData[i]) / 255.0
            let g = CGFloat(pixelData[i + 1]) / 255.0
            let b = CGFloat(pixelData[i + 2]) / 255.0
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            totalLuma += luma
            count += 1
        }
        return count > 0 ? totalLuma / CGFloat(count) : 1.0
    }

    /// Détermine si une case est cochée.
    ///
    /// Approche : on échantillonne **très près du centre** de la case
    /// (halfSize = 1.5 pt) pour ne pas attraper le cadre noir de la case.
    /// On compare ensuite à `paperReference` : si la zone interne est
    /// significativement plus sombre que le papier (ratio < 0.80), c'est
    /// qu'il y a de l'encre dedans → cochée.
    ///
    /// Seuil 0.80 = on considère qu'une case est cochée dès qu'elle est ~20 %
    /// plus sombre que le papier. Permet de détecter même un simple « . » ou
    /// « / » au stylo bille fin, sans déclencher sur les ombres légères.
    func isChecked(atPDFPoint center: CGPoint) -> (checked: Bool, luma: CGFloat, ratio: CGFloat) {
        let inner = averageIntensity(atPDFPoint: center, halfSizePoints: 1.5)
        let ratio = paperReference > 0 ? inner / paperReference : 1.0
        return (ratio < 0.80, inner, ratio)
    }
}
