import Foundation
import SwiftData
import os.log

/// Fusionne les doublons de données familiales créés par le scénario
/// multi-appareil : un parent installe l'app sur un 2ᵉ appareil (iPad,
/// nouvel iPhone…), l'onboarding s'affiche avant que le premier pull
/// iCloud n'ait ramené les données existantes, le parent re-saisit le
/// profil et le plan médicamenteux → nouveaux UUIDs → au pull suivant les
/// deux jeux coexistent : plan dupliqué, et les enregistrements rattachés
/// au « mauvais » profil disparaissent de l'UI (qui utilise
/// `profiles.first`).
///
/// Stratégie de fusion — **déterministe** : les règles de choix du
/// survivant ne dépendent que des données (createdAt, lastModifiedAt,
/// UUID), donc chaque appareil qui exécute la fusion choisit les MÊMES
/// survivants et pousse les MÊMES suppressions → convergence sans
/// coordination.
///
/// - **Profils** : on garde le plus ANCIEN (createdAt) — c'est l'original.
///   Tous les enregistrements des doublons (médicaments, prises, crises,
///   humeurs, observations, symptômes) sont re-rattachés au survivant.
///   `hasEpilepsy` est OR-é : une fusion ne doit jamais masquer le suivi
///   épilepsie.
/// - **Médicaments** : groupés par (nom normalisé, unité, type, planning).
///   On garde le plus ANCIEN (createdAt — immuable donc identique sur tous
///   les appareils, contrairement à lastModifiedAt qui diverge le temps que
///   les éditions se propagent). Les prises et révisions du perdant sont
///   re-pointées vers le survivant — aucun historique n'est perdu. Le dedup
///   des prises planifiées (`MedicationLog.dedupeScheduledLogs`) collapse
///   ensuite les doublons de journal résultants.
///
/// Les suppressions passent par `saveTouching()` → enqueue dans le
/// `PendingWriteStore` → propagées à CloudKit au prochain drain.
///
/// Ne crée JAMAIS de données (respecte notamment la règle « ne pas
/// réimporter les données de démo supprimées ») — fusion et suppression
/// uniquement.
enum FamilyDataDeduplicator {
    private static let log = Logger(subsystem: "fr.afsr.RettApp", category: "FamilyDedup")

    /// Exécute les deux passes de fusion. Retourne le nombre total
    /// d'entités supprimées (0 = rien à faire, aucun save émis).
    @discardableResult
    static func run(in context: ModelContext) -> Int {
        let profileMerges = mergeDuplicateProfiles(in: context)
        let medicationMerges = mergeDuplicateMedications(in: context)
        let total = profileMerges + medicationMerges
        if total > 0 {
            try? context.saveTouching()
            log.info("Fusion : \(profileMerges) profil(s) + \(medicationMerges) médicament(s) doublons supprimés")
        }
        return total
    }

    // MARK: - Profils

    static func mergeDuplicateProfiles(in context: ModelContext) -> Int {
        guard let profiles = try? context.fetch(FetchDescriptor<ChildProfile>()),
              profiles.count > 1 else { return 0 }

        // Survivant : le plus ancien createdAt, tie-break lexicographique sur
        // l'UUID pour rester déterministe si les deux ont été créés dans la
        // même seconde.
        let sorted = profiles.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let winner = sorted[0]
        let losers = Array(sorted.dropFirst())
        let loserIds = Set(losers.map(\.id))

        // Une fusion ne doit jamais désactiver le suivi épilepsie.
        if losers.contains(where: { $0.hasEpilepsy }) {
            winner.hasEpilepsy = true
        }
        // Complète les champs vides du survivant avec ceux d'un doublon
        // (cas : l'original n'avait pas de nom de famille / date de naissance).
        if winner.lastName.isEmpty, let l = losers.first(where: { !$0.lastName.isEmpty }) {
            winner.lastName = l.lastName
        }
        if winner.birthDate == nil, let l = losers.first(where: { $0.birthDate != nil }) {
            winner.birthDate = l.birthDate
        }

        // Re-rattache la relation Medication.childProfile AVANT de supprimer
        // les doublons — sinon la cascade `.cascade` emporterait les
        // médicaments avec le profil supprimé. Les orphelins (childProfile
        // nil — résultat du détachement anti-cascade de `deleteLocal` quand
        // la suppression d'un profil doublon arrive par le réseau) sont
        // adoptés par le survivant au passage.
        if let meds = try? context.fetch(FetchDescriptor<Medication>()) {
            for m in meds {
                if let pid = m.childProfile?.id, loserIds.contains(pid) {
                    m.childProfile = winner
                } else if m.childProfile == nil {
                    m.childProfile = winner
                }
            }
        }

        // Re-pointe les champs childProfileId « plats » de chaque type.
        let winnerId = winner.id
        if let logs = try? context.fetch(FetchDescriptor<MedicationLog>()) {
            for l in logs where l.childProfileId.map(loserIds.contains) == true {
                l.childProfileId = winnerId
            }
        }
        if let seizures = try? context.fetch(FetchDescriptor<SeizureEvent>()) {
            for s in seizures where s.childProfileId.map(loserIds.contains) == true {
                s.childProfileId = winnerId
            }
        }
        if let moods = try? context.fetch(FetchDescriptor<MoodEntry>()) {
            for m in moods where m.childProfileId.map(loserIds.contains) == true {
                m.childProfileId = winnerId
            }
        }
        if let obs = try? context.fetch(FetchDescriptor<DailyObservation>()) {
            for o in obs where o.childProfileId.map(loserIds.contains) == true {
                o.childProfileId = winnerId
            }
        }
        if let symptoms = try? context.fetch(FetchDescriptor<SymptomEvent>()) {
            for s in symptoms where s.childProfileId.map(loserIds.contains) == true {
                s.childProfileId = winnerId
            }
        }

        for loser in losers {
            context.delete(loser)
        }
        return losers.count
    }

    // MARK: - Médicaments

    static func mergeDuplicateMedications(in context: ModelContext) -> Int {
        guard let meds = try? context.fetch(FetchDescriptor<Medication>()),
              meds.count > 1 else { return 0 }

        // Clé de groupement STRICTE : même nom (normalisé), même unité, même
        // type (regular/adhoc) ET même planning d'horaires de prises.
        //
        // Le planning dans la clé est la protection anti-destruction : deux
        // entrées légitimes de même nom (ex. « Dépakine » du matin et
        // « Dépakine » du soir saisies comme deux médicaments distincts) ont
        // des horaires différents → jamais fusionnées. Seuls les VRAIS
        // doublons (re-saisie du même plan sur un 2ᵉ appareil → mêmes
        // horaires) sont collapsés.
        var groups: [String: [Medication]] = [:]
        for m in meds {
            let key = normalizedName(m.name) + "|" + m.doseUnitRaw + "|" + m.kindRaw + "|" + scheduleKey(m)
            groups[key, default: []].append(m)
        }

        var removed = 0
        for (_, group) in groups where group.count > 1 {
            // Survivant : le plus ANCIEN createdAt, tie-break UUID.
            //
            // ATTENTION — le critère doit être basé sur des champs IMMUABLES
            // et déjà convergés entre appareils. Une première version
            // utilisait `lastModifiedAt` (« le plus récemment modifié ») :
            // deux appareils dédupliquant en parallèle avec des éditions
            // locales pas encore propagées voyaient des timestamps
            // différents, choisissaient des survivants OPPOSÉS, et chacun
            // poussait la suppression de l'autre → les DEUX copies
            // détruites. `createdAt` est fixé à la création et identique
            // partout → même survivant sur tous les appareils, toujours.
            let sorted = group.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            let winner = sorted[0]
            let losers = Array(sorted.dropFirst())
            let winnerId = winner.id
            let winnerName = winner.name

            for loser in losers {
                let loserId = loser.id
                // Toutes les prises du doublon rejoignent le survivant —
                // l'historique factuel est intégralement conservé.
                if let logs = try? context.fetch(FetchDescriptor<MedicationLog>(
                    predicate: #Predicate { $0.medicationId == loserId }
                )) {
                    for l in logs {
                        l.medicationId = winnerId
                        l.medicationName = winnerName
                    }
                }
                // Idem pour l'historique de révisions du plan.
                if let revisions = try? context.fetch(FetchDescriptor<MedicationRevision>(
                    predicate: #Predicate { $0.medicationId == loserId }
                )) {
                    for r in revisions {
                        r.medicationId = winnerId
                    }
                }
                context.delete(loser)
                removed += 1
            }
        }
        return removed
    }

    /// Normalisation du nom pour le groupement : trim + casse + espaces
    /// multiples. « Keppra  » et « keppra » sont le même médicament.
    static func normalizedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Empreinte du planning de prises : heures/minutes triées. Deux
    /// médicaments ne sont candidats à la fusion QUE si cette empreinte est
    /// identique — signature d'une re-saisie du même plan.
    static func scheduleKey(_ m: Medication) -> String {
        m.intakes
            .map { String(format: "%02d:%02d", $0.hour, $0.minute) }
            .sorted()
            .joined(separator: ",")
    }

    /// Re-rattache au profil unique les médicaments orphelins (childProfile
    /// nil). Ces orphelins naissent du détachement anti-cascade de
    /// `CloudKitSyncService.deleteLocal` : quand la suppression d'un profil
    /// doublon arrive par le réseau, on détache ses médicaments plutôt que
    /// de laisser la cascade les détruire. À appeler après chaque pull.
    ///
    /// Ne fait rien s'il y a 0 ou 2+ profils (avec plusieurs profils, le
    /// rattachement serait non-déterministe — c'est `mergeDuplicateProfiles`
    /// qui gère ce cas en adoptant vers son survivant).
    @discardableResult
    static func adoptOrphanMedications(in context: ModelContext) -> Int {
        guard let profiles = try? context.fetch(FetchDescriptor<ChildProfile>()),
              profiles.count == 1, let only = profiles.first else { return 0 }
        guard let meds = try? context.fetch(FetchDescriptor<Medication>()) else { return 0 }
        var adopted = 0
        for m in meds where m.childProfile == nil {
            m.childProfile = only
            adopted += 1
        }
        if adopted > 0 {
            try? context.saveTouching()
            log.info("Adoption : \(adopted) médicament(s) orphelin(s) re-rattaché(s) au profil")
        }
        return adopted
    }

    /// Pré-check bon marché : y a-t-il des doublons candidats à la fusion ?
    /// Utilisé pour déclencher l'instantané de sécurité AVANT toute fusion —
    /// on ne prend jamais le risque de supprimer sans copie locale préalable.
    static func hasDuplicates(in context: ModelContext) -> Bool {
        if ((try? context.fetchCount(FetchDescriptor<ChildProfile>())) ?? 0) > 1 { return true }
        guard let meds = try? context.fetch(FetchDescriptor<Medication>()), meds.count > 1 else { return false }
        var seen = Set<String>()
        for m in meds {
            let key = normalizedName(m.name) + "|" + m.doseUnitRaw + "|" + m.kindRaw + "|" + scheduleKey(m)
            if !seen.insert(key).inserted { return true }
        }
        return false
    }
}
