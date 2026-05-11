import Foundation
import SwiftData
import Observation
import UserNotifications

@Observable
final class MedicationViewModel {
    var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    func ensureLogsExist(for date: Date, medications: [Medication], profile: ChildProfile?, in context: ModelContext) {
        let day = Calendar.current.startOfDay(for: date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day

        let childId = profile?.id
        let descriptor = FetchDescriptor<MedicationLog>(
            predicate: #Predicate { log in
                log.scheduledTime >= day && log.scheduledTime < nextDay
            }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingKeys = Set(existing.map { "\($0.medicationId)|\(Int($0.scheduledTime.timeIntervalSince1970))" })

        for med in medications where med.isActive && med.kind == .regular {
            for slot in med.scheduledHours {
                let scheduled = slot.date(on: day)
                let key = "\(med.id)|\(Int(scheduled.timeIntervalSince1970))"
                if !existingKeys.contains(key) {
                    let log = MedicationLog(
                        medicationId: med.id,
                        medicationName: med.name,
                        scheduledTime: scheduled,
                        dose: med.doseAmount,
                        doseUnit: med.doseUnit,
                        childProfileId: childId
                    )
                    context.insert(log)
                }
            }
        }
        try? context.save()
    }

    func togglePrise(_ log: MedicationLog, in context: ModelContext) {
        log.taken.toggle()
        log.takenTime = log.taken ? Date() : nil
        try? context.save()
    }

    // MARK: - Notifications

    /// Demande la permission si elle n'a pas encore été décidée. Renvoie l'état
    /// final pour que les appelants sachent s'ils doivent prévenir l'utilisateur.
    @discardableResult
    func requestNotificationPermissionIfNeeded() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            return await center.notificationSettings().authorizationStatus
        }
        return settings.authorizationStatus
    }

    /// Recrée toutes les notifications calendaires à partir du plan médicamenteux.
    /// Si la permission est `.notDetermined`, on la demande automatiquement avant
    /// de planifier — sinon les notifications n'étaient jamais programmées
    /// quand l'utilisateur ajoutait un premier médicament sans avoir activé
    /// les notifications préalablement.
    func rescheduleAllNotifications(medications: [Medication], childFirstName: String) async {
        let center = UNUserNotificationCenter.current()
        let status = await requestNotificationPermissionIfNeeded()
        guard status == .authorized || status == .provisional else {
            return
        }

        // On supprime uniquement nos identifiants
        let pending = await center.pendingNotificationRequests()
        let ids = pending.filter { $0.identifier.hasPrefix("afsr.med.") }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        var scheduled = 0
        // Filtre supplémentaire : `notifyEnabled` permet à l'utilisateur de
        // désactiver les notifications pour un médicament spécifique (ex.
        // celui géré uniquement par l'école / le centre / l'autre parent).
        for med in medications where med.isActive && med.kind == .regular && med.notifyEnabled {
            for slot in med.scheduledHours {
                let identifier = "afsr.med.\(med.id.uuidString).\(slot.hour).\(slot.minute)"
                let content = UNMutableNotificationContent()
                content.title = "💊 \(med.name)"
                let doseLabel = med.doseLabel
                let name = childFirstName.isEmpty ? "votre enfant" : childFirstName
                content.body = "Heure de donner \(doseLabel) à \(name)."
                content.sound = .default
                content.categoryIdentifier = "afsr.medication"

                var comps = DateComponents()
                comps.hour = slot.hour
                comps.minute = slot.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                do {
                    try await center.add(request)
                    scheduled += 1
                } catch {
                    print("⚠️ Échec planning notif \(identifier) : \(error.localizedDescription)")
                }
            }
        }
        print("ℹ️ Notifications planifiées : \(scheduled)")
    }

    func cancelAllNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.filter { $0.identifier.hasPrefix("afsr.med.") }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
