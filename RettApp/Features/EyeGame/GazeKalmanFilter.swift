import Foundation
import CoreGraphics
import QuartzCore

/// Filtre de Kalman 2D pour lisser la position du regard.
///
/// Modèle : position + vitesse, accélération supposée gaussienne (constant-acceleration model).
/// - État : `[x, y, vx, vy]`
/// - Mesure : `[x, y]`
/// - Transition : `x_{k+1} = x_k + vx·dt`, pareil pour y
///
/// Adaptation à la calibration :
/// - Le bruit de mesure `R` diminue quand le nombre d'échantillons de calibration augmente.
/// - Au début (aucune calibration), `R` est grand → le filtre lisse fort et suit peu la mesure.
/// - Avec > 10 échantillons, `R` est petit → le filtre réagit vite et fait confiance à la mesure.
///
/// Cela permet de compenser la mauvaise calibration initiale par un lissage agressif, puis de
/// redonner de la réactivité quand on sait mieux où l'utilisateur regarde.
final class GazeKalmanFilter {

    // MARK: - Tuning

    /// Écart-type de la mesure quand la calibration est inexistante (pixels).
    private let sigmaMeasureHigh: Double = 200.0
    /// Écart-type de la mesure quand la calibration est stable.
    private let sigmaMeasureLow: Double = 20.0
    /// Nombre d'échantillons après lequel on considère la calibration stable.
    private let samplesForFullConfidence: Double = 10.0
    /// Écart-type de l'accélération aléatoire (pixels/s²) — gouverne la "raideur".
    private let sigmaAcceleration: Double = 800.0

    // MARK: - State

    // Vecteur d'état 4×1 : [x, y, vx, vy]
    private var state: [Double] = [0, 0, 0, 0]
    // Matrice de covariance 4×4
    private var P: [[Double]] = GazeKalmanFilter.diag([1000, 1000, 1000, 1000])
    // Matrice de bruit de mesure 2×2 (adaptée dynamiquement)
    private var R: [[Double]]
    // Timestamp de la dernière mise à jour
    private var lastTimestamp: CFTimeInterval?
    private var initialized = false

    init() {
        let r = sigmaMeasureHigh * sigmaMeasureHigh
        self.R = [[r, 0], [0, r]]
    }

    // MARK: - Public API

    /// Remet le filtre à zéro (appelé sur nouvelle calibration ou fin de partie).
    func reset() {
        state = [0, 0, 0, 0]
        P = GazeKalmanFilter.diag([1000, 1000, 1000, 1000])
        lastTimestamp = nil
        initialized = false
    }

    /// Met à jour la confiance du filtre dans la mesure à partir du nombre d'échantillons
    /// de calibration disponibles. Plus il y en a, plus R est petit.
    func setCalibrationConfidence(sampleCount: Int) {
        let factor = min(Double(sampleCount) / samplesForFullConfidence, 1.0)
        let sigma = sigmaMeasureHigh - (sigmaMeasureHigh - sigmaMeasureLow) * factor
        let r = sigma * sigma
        R = [[r, 0], [0, r]]
    }

    /// Applique une étape prédiction + mise à jour au filtre et retourne la position lissée.
    func filter(measurement: CGPoint) -> CGPoint {
        let now = CACurrentMediaTime()
        let dt: Double
        if let last = lastTimestamp {
            dt = max(0.001, min(0.1, now - last))
        } else {
            dt = 1.0 / 60.0
        }
        lastTimestamp = now

        if !initialized {
            // Initialisation directe avec la première mesure
            state = [Double(measurement.x), Double(measurement.y), 0, 0]
            initialized = true
            return measurement
        }

        predict(dt: dt)
        update(measurement: measurement)
        return CGPoint(x: state[0], y: state[1])
    }

    // MARK: - Kalman steps

    /// Prédiction : state = F · state, P = F · P · Fᵀ + Q
    private func predict(dt: Double) {
        // F = [[1, 0, dt, 0],
        //      [0, 1, 0, dt],
        //      [0, 0, 1, 0],
        //      [0, 0, 0, 1]]
        state = [
            state[0] + dt * state[2],
            state[1] + dt * state[3],
            state[2],
            state[3]
        ]

        // P = F · P · Fᵀ + Q
        let F: [[Double]] = [
            [1, 0, dt, 0],
            [0, 1, 0, dt],
            [0, 0, 1, 0],
            [0, 0, 0, 1]
        ]
        let FP = Self.mul(F, P)
        let FPFt = Self.mul(FP, Self.transpose(F))
        let Q = processNoise(dt: dt)
        P = Self.add(FPFt, Q)
    }

    /// Q pour un modèle à accélération constante :
    ///
    ///   Q = σ_a² · [[dt⁴/4, 0, dt³/2, 0],
    ///              [0, dt⁴/4, 0, dt³/2],
    ///              [dt³/2, 0, dt²,  0],
    ///              [0, dt³/2, 0,    dt²]]
    private func processNoise(dt: Double) -> [[Double]] {
        let sa2 = sigmaAcceleration * sigmaAcceleration
        let dt2 = dt * dt
        let dt3 = dt2 * dt
        let dt4 = dt3 * dt
        return [
            [dt4 / 4 * sa2, 0, dt3 / 2 * sa2, 0],
            [0, dt4 / 4 * sa2, 0, dt3 / 2 * sa2],
            [dt3 / 2 * sa2, 0, dt2 * sa2, 0],
            [0, dt3 / 2 * sa2, 0, dt2 * sa2]
        ]
    }

    /// Mise à jour avec une mesure de position 2D.
    private func update(measurement: CGPoint) {
        // Innovation : y = z - H · state, avec H = [[1,0,0,0],[0,1,0,0]]
        let innovation: [Double] = [
            Double(measurement.x) - state[0],
            Double(measurement.y) - state[1]
        ]

        // S = H · P · Hᵀ + R = P[0..1, 0..1] + R (puisque H sélectionne position)
        let S: [[Double]] = [
            [P[0][0] + R[0][0], P[0][1] + R[0][1]],
            [P[1][0] + R[1][0], P[1][1] + R[1][1]]
        ]

        // S⁻¹ (2×2 inversion directe)
        let det = S[0][0] * S[1][1] - S[0][1] * S[1][0]
        guard abs(det) > 1e-9 else { return } // skip mise à jour instable
        let Sinv: [[Double]] = [
            [ S[1][1] / det, -S[0][1] / det],
            [-S[1][0] / det,  S[0][0] / det]
        ]

        // K = P · Hᵀ · S⁻¹ — où P·Hᵀ prend les 2 premières colonnes de P (4×2)
        var K = [[Double]](repeating: [0, 0], count: 4)
        for i in 0..<4 {
            for j in 0..<2 {
                K[i][j] = P[i][0] * Sinv[0][j] + P[i][1] * Sinv[1][j]
            }
        }

        // state = state + K · innovation
        for i in 0..<4 {
            state[i] += K[i][0] * innovation[0] + K[i][1] * innovation[1]
        }

        // P = (I - K·H) · P
        // K·H est 4×4 : (K·H)[i][j] = K[i][j] si j<2, sinon 0
        var newP = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 {
                var sum = P[i][j]
                // soustraire (K·H·P)[i][j] = Σ_k (K·H)[i][k] · P[k][j]
                sum -= K[i][0] * P[0][j] + K[i][1] * P[1][j]
                newP[i][j] = sum
            }
        }
        P = newP
    }

    // MARK: - Matrix helpers

    private static func diag(_ values: [Double]) -> [[Double]] {
        var m = [[Double]](repeating: [Double](repeating: 0, count: values.count), count: values.count)
        for i in 0..<values.count { m[i][i] = values[i] }
        return m
    }

    private static func transpose(_ a: [[Double]]) -> [[Double]] {
        let rows = a.count
        let cols = a[0].count
        var t = [[Double]](repeating: [Double](repeating: 0, count: rows), count: cols)
        for i in 0..<rows { for j in 0..<cols { t[j][i] = a[i][j] } }
        return t
    }

    private static func mul(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        let rows = a.count
        let inner = b.count
        let cols = b[0].count
        var out = [[Double]](repeating: [Double](repeating: 0, count: cols), count: rows)
        for i in 0..<rows {
            for j in 0..<cols {
                var sum = 0.0
                for k in 0..<inner { sum += a[i][k] * b[k][j] }
                out[i][j] = sum
            }
        }
        return out
    }

    private static func add(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        let rows = a.count
        let cols = a[0].count
        var out = [[Double]](repeating: [Double](repeating: 0, count: cols), count: rows)
        for i in 0..<rows { for j in 0..<cols { out[i][j] = a[i][j] + b[i][j] } }
        return out
    }
}
