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

    init?(image: UIImage, qrPDFRect: CGRect, qrImageRect: CGRect) {
        guard let cgImage = image.cgImage else { return nil }
        self.image = cgImage
        self.qrPDFRect = qrPDFRect
        self.qrImageRect = qrImageRect
        self.scaleX = qrImageRect.width / qrPDFRect.width
        self.scaleY = qrImageRect.height / qrPDFRect.height
        self.offsetX = qrImageRect.minX - qrPDFRect.minX * scaleX
        self.offsetY = qrImageRect.minY - qrPDFRect.minY * scaleY
    }

    /// Convertit une position PDF (pt) en position image (px).
    func imagePoint(forPDFPoint p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scaleX + offsetX, y: p.y * scaleY + offsetY)
    }

    /// Renvoie l'intensité moyenne (0.0 noir → 1.0 blanc) d'une fenêtre
    /// carrée centrée sur `center` (en coords PDF), de demi-taille
    /// `halfSizePoints` (en pt PDF, sera converti en pixels).
    func averageIntensity(atPDFPoint center: CGPoint, halfSizePoints: CGFloat = 4) -> CGFloat {
        let imageCenter = imagePoint(forPDFPoint: center)
        let halfSizePixels = halfSizePoints * scaleX
        let rect = CGRect(
            x: imageCenter.x - halfSizePixels,
            y: imageCenter.y - halfSizePixels,
            width: halfSizePixels * 2,
            height: halfSizePixels * 2
        ).integral

        // Clamp dans les bornes de l'image
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return 1.0 }

        guard let cropped = image.cropping(to: clipped) else { return 1.0 }

        // Lit les pixels et calcule la moyenne en niveaux de gris.
        let width = cropped.width
        let height = cropped.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 1.0 }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalLuma: CGFloat = 0
        var count: Int = 0
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            let r = CGFloat(pixelData[i]) / 255.0
            let g = CGFloat(pixelData[i + 1]) / 255.0
            let b = CGFloat(pixelData[i + 2]) / 255.0
            // Luma BT.601 — bonne approx pour de l'encre noire sur papier blanc
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            totalLuma += luma
            count += 1
        }
        return count > 0 ? totalLuma / CGFloat(count) : 1.0
    }

    /// Détermine si une case est cochée. Stratégie :
    ///   - On compare l'intensité de l'intérieur de la case (centre) à celle
    ///     de l'arrière-plan immédiat (cadre de papier autour). Si l'intérieur
    ///     est significativement plus sombre, c'est qu'il y a de l'encre.
    /// - Le seuil 0.85 (papier brut ~0.95, encre ~0.4) est volontairement
    ///   conservateur : on préfère un faux négatif (que l'utilisateur recoche)
    ///   à un faux positif.
    func isChecked(atPDFPoint center: CGPoint, cellSize: CGFloat = 10) -> Bool {
        let inner = averageIntensity(atPDFPoint: center, halfSizePoints: cellSize / 3)
        return inner < 0.85
    }
}
