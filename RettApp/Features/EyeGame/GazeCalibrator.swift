import Foundation
import CoreGraphics

/// Calibrateur du regard.
///
/// Maintient une liste de paires `(raw, actual)` où `raw` est le point fourni par
/// ARKit (projection de `lookAtPoint`) et `actual` est la position réelle à laquelle
/// l'enfant regarde (fournie par un tap du parent sur la cible).
///
/// À partir des échantillons, on fait deux régressions linéaires indépendantes :
/// `actual_x = scaleX * raw_x + offsetX` et pareil pour y. C'est une approximation
/// simple mais robuste : ça corrige offset, échelle et inversion d'axe en même temps.
final class GazeCalibrator {
    private struct Sample { let raw: CGPoint; let actual: CGPoint }

    private(set) var samples: [Sample] = []
    private let maxSamples: Int

    /// Transformation affine 1D par axe : apply(p) = (scaleX*p.x + offsetX, scaleY*p.y + offsetY).
    private(set) var scaleX: CGFloat = 1
    private(set) var offsetX: CGFloat = 0
    private(set) var scaleY: CGFloat = 1
    private(set) var offsetY: CGFloat = 0

    init(maxSamples: Int = 30) {
        self.maxSamples = maxSamples
    }

    /// Ajoute un échantillon et recalcule la transformation.
    func addSample(raw: CGPoint, actual: CGPoint) {
        samples.append(Sample(raw: raw, actual: actual))
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        recompute()
    }

    func reset() {
        samples.removeAll()
        scaleX = 1; offsetX = 0
        scaleY = 1; offsetY = 0
    }

    var samplesCount: Int { samples.count }

    /// Applique la transformation au point brut. Si moins de 2 échantillons, retourne `raw`.
    func apply(_ raw: CGPoint) -> CGPoint {
        guard samples.count >= 2 else { return raw }
        return CGPoint(
            x: raw.x * scaleX + offsetX,
            y: raw.y * scaleY + offsetY
        )
    }

    private func recompute() {
        guard samples.count >= 2 else {
            scaleX = 1; offsetX = 0
            scaleY = 1; offsetY = 0
            return
        }
        let rawsX = samples.map { Double($0.raw.x) }
        let actsX = samples.map { Double($0.actual.x) }
        let rawsY = samples.map { Double($0.raw.y) }
        let actsY = samples.map { Double($0.actual.y) }

        let (sx, ox) = linearFit(xs: rawsX, ys: actsX)
        let (sy, oy) = linearFit(xs: rawsY, ys: actsY)
        scaleX = CGFloat(sx); offsetX = CGFloat(ox)
        scaleY = CGFloat(sy); offsetY = CGFloat(oy)
    }

    /// Régression linéaire ordinaire. Retourne (slope, intercept) qui minimisent MSE.
    /// Si la variance de `xs` est trop faible, retourne (1, moy(ys) - moy(xs)).
    private func linearFit(xs: [Double], ys: [Double]) -> (slope: Double, intercept: Double) {
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let meanX = sumX / n
        let meanY = sumY / n
        var num = 0.0
        var den = 0.0
        for i in 0..<xs.count {
            let dx = xs[i] - meanX
            num += dx * (ys[i] - meanY)
            den += dx * dx
        }
        if den < 1e-6 {
            return (1.0, meanY - meanX)
        }
        let slope = num / den
        let intercept = meanY - slope * meanX
        return (slope, intercept)
    }
}
