import Foundation
import CloudKit
import SwiftData

/// Mapping bidirectionnel SwiftData ↔ CloudKit pour la synchronisation entre parents.
///
/// Convention :
/// - Le `recordName` CKRecord = `id.uuidString` du model SwiftData → unicité cross-device garantie
/// - Tous les records vivent dans la même `recordZone` privée du parent propriétaire (ou
///   partagée chez le second parent), pour pouvoir les partager via un seul `CKShare` de zone
/// - Les enums sont stockées en `String` (rawValue) pour rester portables
/// - Les relations (Medication.childProfile) sont représentées par leur UUID en string —
///   la résolution se fait côté SwiftData après upsert (relations recréées par fetch)
enum CKRecordType {
    static let childProfile     = "ChildProfile"
    static let medication       = "Medication"
    static let medicationLog    = "MedicationLog"
    static let seizure          = "SeizureEvent"
    static let mood             = "MoodEntry"
    static let dailyObservation = "DailyObservation"

    /// Tous les record types utilisés. Sert au pull pour balayer la zone.
    static let all = [childProfile, medication, medicationLog, seizure, mood, dailyObservation]
}

// MARK: - ChildProfile

extension ChildProfile {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r = CKRecord(recordType: CKRecordType.childProfile, recordID: recordID)
        r["firstName"] = firstName as CKRecordValue
        r["lastName"] = lastName as CKRecordValue
        if let birthDate { r["birthDate"] = birthDate as CKRecordValue }
        r["hasEpilepsy"] = (hasEpilepsy ? 1 : 0) as CKRecordValue
        r["sexRaw"] = sexRaw as CKRecordValue
        r["createdAt"] = createdAt as CKRecordValue
        return r
    }

    static func upsert(from record: CKRecord, in context: ModelContext) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let existing = (try? context.fetch(FetchDescriptor<ChildProfile>(
            predicate: #Predicate { $0.id == id }
        )).first)

        let firstName = record["firstName"] as? String ?? ""
        let lastName = record["lastName"] as? String ?? ""
        let birthDate = record["birthDate"] as? Date
        let hasEpilepsy = (record["hasEpilepsy"] as? Int ?? 0) == 1
        let sexRaw = record["sexRaw"] as? String ?? ChildSex.unspecified.rawValue
        let createdAt = record["createdAt"] as? Date ?? Date()

        if let existing {
            existing.firstName = firstName
            existing.lastName = lastName
            existing.birthDate = birthDate
            existing.hasEpilepsy = hasEpilepsy
            existing.sexRaw = sexRaw
        } else {
            let new = ChildProfile(
                id: id, firstName: firstName, lastName: lastName,
                birthDate: birthDate, hasEpilepsy: hasEpilepsy,
                sex: ChildSex(rawValue: sexRaw) ?? .unspecified,
                createdAt: createdAt
            )
            context.insert(new)
        }
    }
}

// MARK: - Medication

extension Medication {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r = CKRecord(recordType: CKRecordType.medication, recordID: recordID)
        r["name"] = name as CKRecordValue
        r["doseAmount"] = doseAmount as CKRecordValue
        r["doseUnitRaw"] = doseUnitRaw as CKRecordValue
        r["kindRaw"] = kindRaw as CKRecordValue
        r["isActive"] = (isActive ? 1 : 0) as CKRecordValue
        r["notifyEnabled"] = (notifyEnabled ? 1 : 0) as CKRecordValue
        r["createdAt"] = createdAt as CKRecordValue
        // Heures planifiées encodées en JSON
        if let data = try? JSONEncoder().encode(scheduledHours),
           let str = String(data: data, encoding: .utf8) {
            r["scheduledHours"] = str as CKRecordValue
        }
        if let childID = childProfile?.id {
            r["childProfileId"] = childID.uuidString as CKRecordValue
        }
        return r
    }

    static func upsert(from record: CKRecord, in context: ModelContext) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let existing = (try? context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.id == id }
        )).first)

        let name = record["name"] as? String ?? ""
        let doseAmount = record["doseAmount"] as? Double ?? 0
        let doseUnitRaw = record["doseUnitRaw"] as? String ?? DoseUnit.mg.rawValue
        let kindRaw = record["kindRaw"] as? String ?? MedicationKind.regular.rawValue
        let isActive = (record["isActive"] as? Int ?? 1) == 1
        let notifyEnabled = (record["notifyEnabled"] as? Int ?? 1) == 1
        let createdAt = record["createdAt"] as? Date ?? Date()

        var hours: [HourMinute] = []
        if let str = record["scheduledHours"] as? String,
           let data = str.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([HourMinute].self, from: data) {
            hours = decoded
        }

        let unit = DoseUnit(rawValue: doseUnitRaw) ?? .mg
        let kind = MedicationKind(rawValue: kindRaw) ?? .regular

        let childIDStr = record["childProfileId"] as? String
        let child: ChildProfile? = childIDStr.flatMap { UUID(uuidString: $0) }.flatMap { childUUID in
            (try? context.fetch(FetchDescriptor<ChildProfile>(
                predicate: #Predicate { $0.id == childUUID }
            )).first)
        }

        if let existing {
            existing.name = name
            existing.doseAmount = doseAmount
            existing.doseUnit = unit
            existing.kind = kind
            existing.isActive = isActive
            existing.notifyEnabled = notifyEnabled
            existing.scheduledHours = hours
            existing.childProfile = child
        } else {
            let new = Medication(
                id: id, name: name,
                doseAmount: doseAmount, doseUnit: unit,
                scheduledHours: hours, kind: kind,
                isActive: isActive, notifyEnabled: notifyEnabled, createdAt: createdAt
            )
            new.childProfile = child
            context.insert(new)
        }
    }
}

// MARK: - MedicationLog

extension MedicationLog {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r = CKRecord(recordType: CKRecordType.medicationLog, recordID: recordID)
        r["medicationId"] = medicationId.uuidString as CKRecordValue
        r["medicationName"] = medicationName as CKRecordValue
        r["scheduledTime"] = scheduledTime as CKRecordValue
        if let takenTime { r["takenTime"] = takenTime as CKRecordValue }
        r["taken"] = (taken ? 1 : 0) as CKRecordValue
        r["dose"] = dose as CKRecordValue
        r["doseUnitRaw"] = doseUnitRaw as CKRecordValue
        r["isAdHoc"] = (isAdHoc ? 1 : 0) as CKRecordValue
        r["adhocReason"] = adhocReason as CKRecordValue
        if let childProfileId {
            r["childProfileId"] = childProfileId.uuidString as CKRecordValue
        }
        return r
    }

    static func upsert(from record: CKRecord, in context: ModelContext) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let existing = (try? context.fetch(FetchDescriptor<MedicationLog>(
            predicate: #Predicate { $0.id == id }
        )).first)

        guard let medIDStr = record["medicationId"] as? String,
              let medicationId = UUID(uuidString: medIDStr) else { return }
        let medicationName = record["medicationName"] as? String ?? ""
        let scheduledTime = record["scheduledTime"] as? Date ?? Date()
        let takenTime = record["takenTime"] as? Date
        let taken = (record["taken"] as? Int ?? 0) == 1
        let dose = record["dose"] as? Double ?? 0
        let doseUnitRaw = record["doseUnitRaw"] as? String ?? DoseUnit.mg.rawValue
        let isAdHoc = (record["isAdHoc"] as? Int ?? 0) == 1
        let adhocReason = record["adhocReason"] as? String ?? ""
        let childProfileId = (record["childProfileId"] as? String).flatMap { UUID(uuidString: $0) }
        let unit = DoseUnit(rawValue: doseUnitRaw) ?? .mg

        if let existing {
            existing.medicationId = medicationId
            existing.medicationName = medicationName
            existing.scheduledTime = scheduledTime
            existing.takenTime = takenTime
            existing.taken = taken
            existing.dose = dose
            existing.doseUnit = unit
            existing.isAdHoc = isAdHoc
            existing.adhocReason = adhocReason
            existing.childProfileId = childProfileId
        } else {
            let new = MedicationLog(
                id: id, medicationId: medicationId, medicationName: medicationName,
                scheduledTime: scheduledTime, takenTime: takenTime, taken: taken,
                dose: dose, doseUnit: unit,
                childProfileId: childProfileId,
                isAdHoc: isAdHoc, adhocReason: adhocReason
            )
            context.insert(new)
        }
    }
}

// MARK: - SeizureEvent

extension SeizureEvent {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r = CKRecord(recordType: CKRecordType.seizure, recordID: recordID)
        r["startTime"] = startTime as CKRecordValue
        r["endTime"] = endTime as CKRecordValue
        r["durationSeconds"] = durationSeconds as CKRecordValue
        r["seizureTypeRaw"] = seizureTypeRaw as CKRecordValue
        r["triggerRaw"] = triggerRaw as CKRecordValue
        r["triggerNotes"] = triggerNotes as CKRecordValue
        r["notes"] = notes as CKRecordValue
        if let childProfileId {
            r["childProfileId"] = childProfileId.uuidString as CKRecordValue
        }
        return r
    }

    static func upsert(from record: CKRecord, in context: ModelContext) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let existing = (try? context.fetch(FetchDescriptor<SeizureEvent>(
            predicate: #Predicate { $0.id == id }
        )).first)

        let startTime = record["startTime"] as? Date ?? Date()
        let endTime = record["endTime"] as? Date ?? startTime
        let typeRaw = record["seizureTypeRaw"] as? String ?? SeizureType.other.rawValue
        let triggerRaw = record["triggerRaw"] as? String ?? SeizureTrigger.none.rawValue
        let triggerNotes = record["triggerNotes"] as? String ?? ""
        let notes = record["notes"] as? String ?? ""
        let childProfileId = (record["childProfileId"] as? String).flatMap { UUID(uuidString: $0) }
        let type = SeizureType(rawValue: typeRaw) ?? .other
        let trigger = SeizureTrigger(rawValue: triggerRaw) ?? .none

        if let existing {
            existing.startTime = startTime
            existing.endTime = endTime
            existing.durationSeconds = max(0, Int(endTime.timeIntervalSince(startTime)))
            existing.seizureType = type
            existing.trigger = trigger
            existing.triggerNotes = triggerNotes
            existing.notes = notes
            existing.childProfileId = childProfileId
        } else {
            let new = SeizureEvent(
                id: id, startTime: startTime, endTime: endTime,
                seizureType: type, trigger: trigger,
                triggerNotes: triggerNotes, notes: notes,
                childProfileId: childProfileId
            )
            context.insert(new)
        }
    }
}

// MARK: - MoodEntry

extension MoodEntry {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r = CKRecord(recordType: CKRecordType.mood, recordID: recordID)
        r["timestamp"] = timestamp as CKRecordValue
        r["levelRaw"] = levelRaw as CKRecordValue
        r["notes"] = notes as CKRecordValue
        if let childProfileId {
            r["childProfileId"] = childProfileId.uuidString as CKRecordValue
        }
        return r
    }

    static func upsert(from record: CKRecord, in context: ModelContext) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let existing = (try? context.fetch(FetchDescriptor<MoodEntry>(
            predicate: #Predicate { $0.id == id }
        )).first)

        let timestamp = record["timestamp"] as? Date ?? Date()
        let levelRaw = record["levelRaw"] as? Int ?? MoodLevel.neutral.rawValue
        let notes = record["notes"] as? String ?? ""
        let childProfileId = (record["childProfileId"] as? String).flatMap { UUID(uuidString: $0) }
        let level = MoodLevel(rawValue: levelRaw) ?? .neutral

        if let existing {
            existing.timestamp = timestamp
            existing.level = level
            existing.notes = notes
            existing.childProfileId = childProfileId
        } else {
            let new = MoodEntry(
                id: id, timestamp: timestamp, level: level,
                notes: notes, childProfileId: childProfileId
            )
            context.insert(new)
        }
    }
}

// MARK: - DailyObservation

extension DailyObservation {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let r = CKRecord(recordType: CKRecordType.dailyObservation, recordID: recordID)
        r["dayStart"] = dayStart as CKRecordValue
        r["mealRatingRaw"] = mealRatingRaw as CKRecordValue
        r["mealNotes"] = mealNotes as CKRecordValue
        r["breakfastRatingRaw"] = breakfastRatingRaw as CKRecordValue
        r["breakfastNotes"] = breakfastNotes as CKRecordValue
        r["lunchRatingRaw"] = lunchRatingRaw as CKRecordValue
        r["lunchNotes"] = lunchNotes as CKRecordValue
        r["snackRatingRaw"] = snackRatingRaw as CKRecordValue
        r["snackNotes"] = snackNotes as CKRecordValue
        r["dinnerRatingRaw"] = dinnerRatingRaw as CKRecordValue
        r["dinnerNotes"] = dinnerNotes as CKRecordValue
        r["hydrationRatingRaw"] = hydrationRatingRaw as CKRecordValue
        r["hydrationNotes"] = hydrationNotes as CKRecordValue
        r["nightSleepRatingRaw"] = nightSleepRatingRaw as CKRecordValue
        r["nightSleepDurationMinutes"] = nightSleepDurationMinutes as CKRecordValue
        r["nightSleepNotes"] = nightSleepNotes as CKRecordValue
        r["napDurationMinutes"] = napDurationMinutes as CKRecordValue
        r["napNotes"] = napNotes as CKRecordValue
        r["generalNotes"] = generalNotes as CKRecordValue
        if let childProfileId {
            r["childProfileId"] = childProfileId.uuidString as CKRecordValue
        }
        return r
    }

    static func upsert(from record: CKRecord, in context: ModelContext) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let existing = (try? context.fetch(FetchDescriptor<DailyObservation>(
            predicate: #Predicate { $0.id == id }
        )).first)

        let dayStart = record["dayStart"] as? Date ?? Date()

        let target: DailyObservation
        if let existing {
            target = existing
            target.dayStart = dayStart
        } else {
            target = DailyObservation(id: id, dayStart: dayStart)
            context.insert(target)
        }

        target.mealRatingRaw = record["mealRatingRaw"] as? Int ?? 0
        target.mealNotes = record["mealNotes"] as? String ?? ""
        target.breakfastRatingRaw = record["breakfastRatingRaw"] as? Int ?? 0
        target.breakfastNotes = record["breakfastNotes"] as? String ?? ""
        target.lunchRatingRaw = record["lunchRatingRaw"] as? Int ?? 0
        target.lunchNotes = record["lunchNotes"] as? String ?? ""
        target.snackRatingRaw = record["snackRatingRaw"] as? Int ?? 0
        target.snackNotes = record["snackNotes"] as? String ?? ""
        target.dinnerRatingRaw = record["dinnerRatingRaw"] as? Int ?? 0
        target.dinnerNotes = record["dinnerNotes"] as? String ?? ""
        target.hydrationRatingRaw = record["hydrationRatingRaw"] as? Int ?? 0
        target.hydrationNotes = record["hydrationNotes"] as? String ?? ""
        target.nightSleepRatingRaw = record["nightSleepRatingRaw"] as? Int ?? 0
        target.nightSleepDurationMinutes = record["nightSleepDurationMinutes"] as? Int ?? 0
        target.nightSleepNotes = record["nightSleepNotes"] as? String ?? ""
        target.napDurationMinutes = record["napDurationMinutes"] as? Int ?? 0
        target.napNotes = record["napNotes"] as? String ?? ""
        target.generalNotes = record["generalNotes"] as? String ?? ""
        target.childProfileId = (record["childProfileId"] as? String).flatMap { UUID(uuidString: $0) }
    }
}
