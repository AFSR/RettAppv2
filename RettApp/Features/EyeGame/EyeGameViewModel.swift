import Foundation
import CoreGraphics
import Observation
import AVFoundation
import ARKit

@Observable
final class EyeGameViewModel {
    enum GameState: Equatable {
        case configuration
        case playing
        case finished(score: Int, total: Int)
    }

    // Configuration parent
    var targetCount: Int = 5           // 3 / 5 / 10
    var speed: GameSpeed = .normal
    var targetSize: TargetSize = .normal
    var showGazeIndicator: Bool = true
    var musicEnabled: Bool = false

    // État de jeu
    var state: GameState = .configuration
    var currentTarget: GameTarget?
    var score: Int = 0
    /// Dernier point brut reçu d'ARKit (avant calibration).
    var rawGazePoint: CGPoint = .zero
    /// Point après application de la calibration — utilisé pour l'affichage et le dwell.
    var lastGazePoint: CGPoint = .zero
    var splashAt: CGPoint? = nil

    let processor = GazeProcessor()
    let calibrator = GazeCalibrator()
    private var spawnedCount = 0
    private var audioPlayer: AVAudioPlayer?
    private var moveTask: Task<Void, Never>?

    // MARK: - Compat

    func isEyeTrackingAvailable() -> Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    // MARK: - Game lifecycle

    /// Déclenchée par le bouton "Lancer" depuis la configuration. Fait juste passer
    /// l'état à `.playing` — le vrai démarrage (spawn de la cible) est fait par
    /// `start(in:)` depuis `PlayingView.onAppear` qui a la taille du canvas.
    func launchPlaying() {
        state = .playing
    }

    func start(in canvasSize: CGSize) {
        score = 0
        spawnedCount = 0
        processor.reset()
        state = .playing
        processor.dwellDuration = speed.dwellDuration
        spawnTarget(in: canvasSize)
    }

    func reset() {
        moveTask?.cancel()
        currentTarget = nil
        splashAt = nil
        state = .configuration
    }

    /// Reçoit un point brut depuis ARKit. Stocke raw, applique la calibration,
    /// puis met à jour la logique de dwell avec le point calibré.
    func handleGaze(_ rawPoint: CGPoint, in canvasSize: CGSize) {
        rawGazePoint = rawPoint
        let calibrated = calibrator.apply(rawPoint)
        lastGazePoint = calibrated
        guard state == .playing, let target = currentTarget else { return }
        if processor.update(gazePoint: calibrated, targets: [target]) != nil {
            completeTarget(canvasSize: canvasSize)
        }
    }

    /// Appelée quand le parent tape à l'écran pour signaler "l'enfant regarde ICI".
    /// - enregistre la paire `(raw_actuel, tap)` dans le calibrateur
    /// - si le tap est proche de la cible courante, valide la cible (même effet qu'un dwell)
    func recordCalibrationTap(at location: CGPoint, canvasSize: CGSize) {
        calibrator.addSample(raw: rawGazePoint, actual: location)
        // Met à jour le point affiché immédiatement avec la nouvelle calibration.
        lastGazePoint = calibrator.apply(rawGazePoint)

        guard state == .playing, let target = currentTarget else { return }
        let dx = location.x - target.position.x
        let dy = location.y - target.position.y
        let dist = (dx * dx + dy * dy).squareRoot()
        if dist < target.diameter / 2 + 40 {
            completeTarget(canvasSize: canvasSize)
        }
    }

    func resetCalibration() {
        calibrator.reset()
        lastGazePoint = rawGazePoint
    }

    private func completeTarget(canvasSize: CGSize) {
        guard let target = currentTarget else { return }
        triggerSplash(at: target.position)
        score += 1
        spawnedCount += 1
        if spawnedCount >= targetCount {
            state = .finished(score: score, total: targetCount)
            currentTarget = nil
            moveTask?.cancel()
            return
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            await MainActor.run {
                self.splashAt = nil
                self.spawnTarget(in: canvasSize)
            }
        }
    }

    // MARK: - Spawning + movement

    private func spawnTarget(in canvasSize: CGSize) {
        let diameter = targetSize.diameter
        let margin: CGFloat = diameter / 2 + 40
        let x = CGFloat.random(in: margin...(canvasSize.width - margin))
        let y = CGFloat.random(in: margin...(canvasSize.height - margin))
        let target = GameTarget(id: UUID(), position: CGPoint(x: x, y: y), diameter: diameter)
        currentTarget = target

        moveTask?.cancel()
        if speed != .slow {
            moveTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(speed.moveInterval * 1_000_000_000))
                    await MainActor.run {
                        guard let current = self.currentTarget else { return }
                        let nx = CGFloat.random(in: margin...(canvasSize.width - margin))
                        let ny = CGFloat.random(in: margin...(canvasSize.height - margin))
                        self.currentTarget = GameTarget(id: current.id, position: CGPoint(x: nx, y: ny), diameter: current.diameter)
                    }
                }
            }
        }
    }

    private func triggerSplash(at point: CGPoint) {
        splashAt = point
        playSplashSound()
    }

    // MARK: - Audio

    private func playSplashSound() {
        AudioServicesPlaySystemSound(1104) // tap coppery, fallback universel si pas d'asset
    }

    // MARK: - Simulator mock

    #if targetEnvironment(simulator)
    private var mockTimer: Timer?
    func startMockGaze(canvasSize: CGSize) {
        mockTimer?.invalidate()
        mockTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Simule un regard qui converge lentement vers la cible courante
            if let t = self.currentTarget {
                let jitter: CGFloat = 120
                let p = CGPoint(
                    x: t.position.x + CGFloat.random(in: -jitter...jitter),
                    y: t.position.y + CGFloat.random(in: -jitter...jitter)
                )
                self.handleGaze(p, in: canvasSize)
            } else {
                self.lastGazePoint = CGPoint(
                    x: CGFloat.random(in: 0...canvasSize.width),
                    y: CGFloat.random(in: 0...canvasSize.height)
                )
            }
        }
    }

    func stopMockGaze() {
        mockTimer?.invalidate()
        mockTimer = nil
    }
    #endif
}

// MARK: - Settings enums

enum GameSpeed: String, CaseIterable, Identifiable {
    case slow, normal, fast
    var id: String { rawValue }
    var label: String {
        switch self {
        case .slow: return "Lent"
        case .normal: return "Normal"
        case .fast: return "Rapide"
        }
    }
    var dwellDuration: TimeInterval {
        switch self {
        case .slow: return 2.0
        case .normal: return 1.5
        case .fast: return 1.0
        }
    }
    var moveInterval: TimeInterval {
        switch self {
        case .slow: return .infinity
        case .normal: return 4
        case .fast: return 2
        }
    }
}

enum TargetSize: String, CaseIterable, Identifiable {
    case large, normal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .large: return "Grande"
        case .normal: return "Normale"
        }
    }
    var diameter: CGFloat {
        switch self {
        case .large: return 180
        case .normal: return 140
        }
    }
}
