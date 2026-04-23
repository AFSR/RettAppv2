import Foundation
import SwiftData

enum SeizureType: String, Codable, CaseIterable, Identifiable {
    case tonicClonic, absence, focal, myoclonic, atonic, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tonicClonic: return "Tonico-clonique"
        case .absence: return "Absence"
        case .focal: return "Focale (partielle)"
        case .myoclonic: return "Myoclonique"
        case .atonic: return "Atonique"
        case .other: return "Autre"
        }
    }
    var color: String {
        switch self {
        case .tonicClonic: return "#E53935"
        case .absence: return "#FB8C00"
        case .focal: return "#FDD835"
        case .myoclonic: return "#8E24AA"
        case .atonic: return "#3949AB"
        case .other: return "#757575"
        }
    }
}

enum SeizureTrigger: String, Codable, CaseIterable, Identifiable {
    case none, fever, fatigue, emotion, heat, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Aucun identifié"
        case .fever: return "Fièvre / Maladie"
        case .fatigue: return "Fatigue / Manque de sommeil"
        case .emotion: return "Émotion forte"
        case .heat: return "Chaleur"
        case .other: return "Autre"
        }
    }
}

@Model
final class SeizureEvent {
    @Attribute(.unique) var id: UUID
    var startTime: Date
    var endTime: Date
    var durationSeconds: Int
    var seizureTypeRaw: String
    var triggerRaw: String
    var triggerNotes: String
    var notes: String
    var childProfileId: UUID?
    var exportedToHealthKit: Bool

    var seizureType: SeizureType {
        get { SeizureType(rawValue: seizureTypeRaw) ?? .other }
        set { seizureTypeRaw = newValue.rawValue }
    }

    var trigger: SeizureTrigger {
        get { SeizureTrigger(rawValue: triggerRaw) ?? .none }
        set { triggerRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date,
        seizureType: SeizureType = .other,
        trigger: SeizureTrigger = .none,
        triggerNotes: String = "",
        notes: String = "",
        childProfileId: UUID? = nil,
        exportedToHealthKit: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = max(0, Int(endTime.timeIntervalSince(startTime)))
        self.seizureTypeRaw = seizureType.rawValue
        self.triggerRaw = trigger.rawValue
        self.triggerNotes = triggerNotes
        self.notes = notes
        self.childProfileId = childProfileId
        self.exportedToHealthKit = exportedToHealthKit
    }

    var formattedDuration: String {
        SeizureEvent.formatDuration(durationSeconds)
    }

    static func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 { return String(format: "%d min %02d s", m, s) }
        return "\(s) s"
    }
}
