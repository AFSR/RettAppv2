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
        let sx = qrImageRect.width / qrPDFRect.width
        let sy = qrImageRect.height / qrPDFRect.height
        let ox = qrImageRect.minX - qrPDFRect.minX * sx
        let oy = qrImageRect.minY - qrPDFRect.minY * sy
        self.scaleX = sx
        self.scaleY = sy
        self.offsetX = ox
        self.offsetY = oy

        // Calibrage du blanc papier : on échantillonne 8 points dans les
        // marges et on prend la médiane. Plus robuste que max() :
        //   - max ignore les outliers sombres mais peut surestimer si une
        //     zone est anormalement claire (reflet)
        //   - median = papier représentatif de la photo (rejette les ombres
        //     ET les reflets ponctuels)
        let pointsForPaper: [CGPoint] = [
            CGPoint(x: 8, y: 8),                       // coin haut-gauche
            CGPoint(x: 8, y: 100),                     // marge gauche haute
            CGPoint(x: 8, y: 400),                     // marge gauche centrale
            CGPoint(x: 8, y: 800),                     // marge gauche basse
            CGPoint(x: 587, y: 100),                   // marge droite haute
            CGPoint(x: 587, y: 400),                   // marge droite centrale
            CGPoint(x: 587, y: 800),                   // marge droite basse
            CGPoint(x: qrPDFRect.midX, y: 8)           // au-dessus du QR
        ]
        let samples: [CGFloat] = pointsForPaper.map {
            BookletPixelSampler.sample(in: cgImage, scaleX: sx, scaleY: sy,
                                       offsetX: ox, offsetY: oy,
                                       at: $0, halfPoints: 4)
        }
        let sorted = samples.sorted()
        // Médiane — robuste aux ombres et reflets ponctuels.
        self.paperReference = sorted[sorted.count / 2]
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
    /// Approche : on échantillonne **5 sous-points** dans le cœur de la case
    /// (centre + 4 points autour, à 1 pt de distance) avec une fenêtre très
    /// fine (0.8 pt) pour rester strictement à l'intérieur du cadre. On
    /// retient la luma la **plus sombre** des 5 points.
    ///
    /// Avantage par rapport à une simple moyenne au centre : un trait de
    /// stylo qui ne passe pas pile au centre (typique d'un X tracé à la
    /// main) est quand même capté par l'un des 4 points périphériques.
    ///
    /// On compare ensuite à `paperReference` : si la zone interne la plus
    /// sombre est significativement plus sombre que le papier
    /// (ratio < 0.72), la case est cochée. Seuil un peu plus permissif que
    /// 0.80 (avec moyenne) car le min capte plus facilement les traits fins.
    func isChecked(atPDFPoint center: CGPoint) -> (checked: Bool, luma: CGFloat, ratio: CGFloat) {
        let offsets: [(CGFloat, CGFloat)] = [
            (0, 0), (-1, -1), (1, -1), (-1, 1), (1, 1)
        ]
        var minLuma: CGFloat = 1.0
        for (dx, dy) in offsets {
            let pt = CGPoint(x: center.x + dx, y: center.y + dy)
            let v = averageIntensity(atPDFPoint: pt, halfSizePoints: 0.8)
            if v < minLuma { minLuma = v }
        }
        let ratio = paperReference > 0 ? minLuma / paperReference : 1.0
        return (ratio < 0.72, minLuma, ratio)
    }
}
