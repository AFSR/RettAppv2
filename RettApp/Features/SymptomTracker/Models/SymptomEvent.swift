import Foundation
import SwiftData

/// Symptômes spécifiques au syndrome de Rett, à tracker au quotidien.
///
/// Liste basée sur la littérature clinique (Orphanet, IRSF, Rett Syndrome Association
/// of the UK). Les éléments déjà couverts par d'autres modèles sont volontairement
/// exclus :
/// - Crises d'épilepsie → `SeizureEvent`
/// - Humeur / agitation générale → `MoodEntry`
/// - Sommeil / repas → `DailyObservation`
enum RettSymptom: String, Codable, CaseIterable, Identifiable {
    case handStereotypy           // stéréotypies des mains (apraxie, gestes main-bouche)
    case lossHandUse              // perte de l'usage volontaire des mains
    case breathingApnea           // apnées (pauses respiratoires)
    case breathingHyperventilation // hyperventilation
    case breathHolding            // retenue du souffle
    case bruxism                  // grincements de dents
    case drooling                 // bavage / hypersialorrhée
    case swallowingDifficulty     // troubles de la déglutition
    case constipation             // constipation
    case gerd                     // reflux gastro-œsophagien
    case dystonia                 // dystonies / postures anormales
    case scoliosisPain            // douleur liée à la scoliose
    case cryingSpell              // crise de pleurs / cris inexpliqués
    case agitation                // agitation / anxiété forte
    case coldExtremities          // extrémités froides / marbrures
    case ataxia                   // ataxie / troubles de l'équilibre
    case other                    // autre

    var id: String { rawValue }

    var label: String {
        switch self {
        case .handStereotypy:           return "Stéréotypies des mains"
        case .lossHandUse:              return "Perte d'usage des mains"
        case .breathingApnea:           return "Apnée respiratoire"
        case .breathingHyperventilation: return "Hyperventilation"
        case .breathHolding:            return "Retenue du souffle"
        case .bruxism:                  return "Bruxisme (grincement)"
        case .drooling:                 return "Bavage / hypersialorrhée"
        case .swallowingDifficulty:     return "Troubles de la déglutition"
        case .constipation:             return "Constipation"
        case .gerd:                     return "Reflux gastro-œsophagien"
        case .dystonia:                 return "Dystonie / posture anormale"
        case .scoliosisPain:            return "Douleur (scoliose, etc.)"
        case .cryingSpell:              return "Crise de pleurs / cris"
        case .agitation:                return "Agitation / anxiété"
        case .coldExtremities:          return "Extrémités froides / marbrures"
        case .ataxia:                   return "Ataxie / déséquilibre"
        case .other:                    return "Autre symptôme"
        }
    }

    var icon: String {
        switch self {
        case .handStereotypy, .lossHandUse:        return "hand.raised.fill"
        case .breathingApnea, .breathingHyperventilation, .breathHolding: return "wind"
        case .bruxism:                              return "mouth.fill"
        case .drooling, .swallowingDifficulty:      return "drop.fill"
        case .constipation, .gerd:                  return "stomach"
        case .dystonia, .scoliosisPain, .ataxia:   return "figure.stand"
        case .cryingSpell, .agitation:              return "exclamationmark.bubble.fill"
        case .coldExtremities:                      return "thermometer.snowflake"
        case .other:                                return "questionmark.circle"
        }
    }

    /// Description simple affichée au parent qui découvre.
    var parentDescription: String {
        switch self {
        case .handStereotypy:
            return "Mouvements répétitifs et involontaires des mains : main à la bouche, mains qui se tordent ensemble, frottements. Caractéristique du syndrome de Rett."
        case .lossHandUse:
            return "Difficulté ou impossibilité d'utiliser les mains volontairement (saisir un objet, manger seule)."
        case .breathingApnea:
            return "Pauses dans la respiration plus longues que normalement, en éveil. Différent des apnées du sommeil."
        case .breathingHyperventilation:
            return "Respiration anormalement rapide et profonde, parfois en lien avec une émotion ou pour aucune raison apparente."
        case .breathHolding:
            return "L'enfant retient sa respiration volontairement ou involontairement pendant plusieurs secondes."
        case .bruxism:
            return "Grincement des dents, principalement en éveil. Peut user les dents et nécessiter une consultation dentaire."
        case .drooling:
            return "Salivation excessive avec écoulement par la bouche. Souvent lié à des troubles moteurs de la déglutition."
        case .swallowingDifficulty:
            return "Difficulté à avaler, fausses routes, repas plus longs que la normale."
        case .constipation:
            return "Selles rares, dures ou difficiles à évacuer. Fréquent dans le syndrome de Rett — surveiller et signaler."
        case .gerd:
            return "Remontées acides de l'estomac vers l'œsophage. Provoque inconfort, parfois douleur, parfois vomissements."
        case .dystonia:
            return "Contractions musculaires involontaires causant des postures inhabituelles ou des mouvements lents."
        case .scoliosisPain:
            return "Douleur liée à la déformation du rachis (scoliose), fréquente dans l'évolution du syndrome de Rett."
        case .cryingSpell:
            return "Épisode de pleurs ou cris inconsolables, parfois sans cause identifiée, pouvant durer de quelques minutes à plusieurs heures."
        case .agitation:
            return "État d'inquiétude ou d'agitation marqué qui sort du comportement habituel de l'enfant."
        case .coldExtremities:
            return "Mains, pieds froids, parfois bleutés ou marbrés. Lié à des troubles de la régulation circulatoire."
        case .ataxia:
            return "Difficultés de coordination, perte d'équilibre, démarche instable."
        case .other:
            return "Tout symptôme observé qui ne rentre pas dans les catégories ci-dessus. Détaillez dans les notes."
        }
    }
}

/// Saisie d'un symptôme observé.
@Model
final class SymptomEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var symptomTypeRaw: String
    /// Intensité 1-5 (0 = non renseigné).
    var intensityRaw: Int
    /// Durée en minutes (0 = ponctuel / non renseigné).
    var durationMinutes: Int
    var notes: String
    var childProfileId: UUID?

    var symptomType: RettSymptom {
        get { RettSymptom(rawValue: symptomTypeRaw) ?? .other }
        set { symptomTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        symptomType: RettSymptom,
        intensity: Int = 0,
        durationMinutes: Int = 0,
        notes: String = "",
        childProfileId: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.symptomTypeRaw = symptomType.rawValue
        self.intensityRaw = max(0, min(5, intensity))
        self.durationMinutes = max(0, durationMinutes)
        self.notes = notes
        self.childProfileId = childProfileId
    }
}
