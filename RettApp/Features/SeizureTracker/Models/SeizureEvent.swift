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
    /// Description destinée aux parents qui découvrent la classification.
    /// Rédigée en langage simple, non médical.
    var parentDescription: String {
        switch self {
        case .tonicClonic:
            return """
            Aussi appelée « grande crise » ou « crise généralisée ».

            L'enfant perd connaissance. Le corps se raidit pendant quelques secondes (phase tonique), puis les bras et les jambes se mettent à secouer de façon rythmique (phase clonique). Des morsures de langue ou une perte d'urines sont possibles.

            Durée typique : 1 à 3 minutes. Au-delà de 5 minutes, appelez le 15.
            """
        case .absence:
            return """
            Courte interruption de la conscience, souvent brève (quelques secondes, rarement plus de 20 s).

            L'enfant fixe le vide, ne répond plus, puis reprend son activité comme si rien ne s'était passé. Pas de chute, pas de secousses. Peut se répéter plusieurs fois par jour.

            Fréquent dans certains syndromes épileptiques de l'enfant.
            """
        case .focal:
            return """
            Aussi appelée crise partielle. Ne concerne qu'une zone du cerveau.

            Symptômes variables : secousses ou raideur d'un seul membre, sensations inhabituelles (picotements, odeur étrange), déformation du visage, vision altérée, ou confusion. La conscience peut être conservée ou altérée.

            Peut parfois évoluer vers une crise généralisée (secondairement généralisée).
            """
        case .myoclonic:
            return """
            Secousses musculaires brèves, brutales et involontaires. L'enfant reste conscient.

            Peut toucher les bras, les épaules, les jambes ou tout le corps. Souvent en salves (plusieurs secousses rapprochées). Peut provoquer une chute d'objet ou une petite perte d'équilibre.

            Durée très courte : une fraction de seconde par secousse.
            """
        case .atonic:
            return """
            Aussi appelée « drop attack ». L'enfant perd brutalement le tonus musculaire et s'effondre.

            Très courte : quelques secondes. L'enfant peut tomber et se blesser. La conscience revient vite.

            Un casque de protection est parfois recommandé pour les enfants qui font ces crises fréquemment.
            """
        case .other:
            return """
            Toute crise qui ne correspond pas clairement aux catégories ci-dessus, ou dont le type n'est pas identifié.

            N'hésitez pas à décrire précisément la crise dans les notes. Votre neurologue pourra vous aider à classer a posteriori.
            """
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
