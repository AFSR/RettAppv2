import Foundation
import Observation
import SwiftData

@Observable
final class SeizureTrackerViewModel {
    enum Phase: Equatable {
        case idle
        case recording(startedAt: Date)
        case qualifying(start: Date, end: Date)
    }

    var phase: Phase = .idle
    var tickerTime: Date = Date()
    private var timer: Timer?

    private let persistenceKey = "afsr.seizure.recordingStartedAt"

    init() {
        // Restauration d'un enregistrement en cours (fermeture accidentelle)
        if let ts = UserDefaults.standard.object(forKey: persistenceKey) as? Double {
            let restored = Date(timeIntervalSince1970: ts)
            phase = .recording(startedAt: restored)
            startTicker()
        }
    }

    // MARK: - Start / stop

    func start() {
        let now = Date()
        phase = .recording(startedAt: now)
        tickerTime = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: persistenceKey)
        startTicker()
    }

    private func startTicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tickerTime = Date()
        }
    }

    func stop() {
        guard case .recording(let startedAt) = phase else { return }
        timer?.invalidate()
        timer = nil
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        phase = .qualifying(start: startedAt, end: Date())
    }

    func cancelQualification() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        phase = .idle
    }

    var currentDuration: TimeInterval {
        guard case .recording(let start) = phase else { return 0 }
        return tickerTime.timeIntervalSince(start)
    }

    func formattedCurrentDuration() -> String {
        let total = Int(currentDuration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Persistence

    func save(
        context: ModelContext,
        type: SeizureType,
        trigger: SeizureTrigger,
        triggerNotes: String,
        notes: String,
        childProfile: ChildProfile?,
        healthKit: HealthKitManager
    ) async {
        guard case .qualifying(let start, let end) = phase else { return }
        let event = SeizureEvent(
            startTime: start,
            endTime: end,
            seizureType: type,
            trigger: trigger,
            triggerNotes: triggerNotes,
            notes: notes,
            childProfileId: childProfile?.id
        )
        context.insert(event)
        do {
            try context.saveTouching()
        } catch {
            print("Erreur sauvegarde crise : \(error)")
        }
        // Tentative d'écriture HealthKit (best-effort)
        do {
            try await healthKit.writeSeizure(event: event, childFirstName: childProfile?.firstName ?? "")
            event.exportedToHealthKit = true
            try? context.save()
        } catch {
            // Permission refusée ou indisponible : on conserve l'événement local
            print("HealthKit non enregistré : \(error.localizedDescription)")
        }
        await MainActor.run { self.phase = .idle }
    }
}
