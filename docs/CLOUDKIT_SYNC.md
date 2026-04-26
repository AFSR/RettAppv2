# Synchronisation entre parents — CloudKit Sharing

Objectif : permettre à deux parents (deux Apple ID distincts, même appareil ou non) de
partager les données du suivi de leur enfant via **CloudKit Sharing** (CKShare).
SwiftData reste la source de vérité locale ; CloudKit est le canal de synchronisation
chiffré entre les deux devices.

## Pourquoi CloudKit Sharing

- Chiffrement de bout en bout activable via *Advanced Data Protection* iCloud (depuis iOS 16.2)
- Aucun serveur tiers à déployer / maintenir — pas de DPA RGPD additionnel
- Authentification déléguée à Apple (les deux parents ont déjà un compte iCloud)
- Modèle d'invitation natif : un parent envoie un lien `https://www.icloud.com/share/...`,
  l'autre clique, le système gère l'acceptation
- Possibilité de retirer le partage à tout moment (révocation côté propriétaire)

## Architecture

```
┌──────────────────────┐                       ┌──────────────────────┐
│  iPhone Parent A     │                       │  iPhone Parent B     │
│  (propriétaire)      │                       │  (invité)            │
│                      │                       │                      │
│  ┌──────────────┐    │                       │    ┌──────────────┐  │
│  │  SwiftData   │    │                       │    │  SwiftData   │  │
│  │   (local)    │    │                       │    │   (local)    │  │
│  └──────┬───────┘    │                       │    └──────┬───────┘  │
│         │            │                       │           │          │
│  ┌──────▼───────┐    │                       │    ┌──────▼───────┐  │
│  │  CloudKit    │    │                       │    │  CloudKit    │  │
│  │  Sync Service│    │                       │    │  Sync Service│  │
│  └──────┬───────┘    │                       │    └──────┬───────┘  │
└─────────┼────────────┘                       └───────────┼──────────┘
          │                                                │
          │           ┌────────────────┐                   │
          │           │  iCloud        │                   │
          │           │                │                   │
          └──────────►│  privateDB(A)  │                   │
                      │   ┌─────────┐  │                   │
                      │   │ CKShare ├──┼──── invitation ──►│
                      │   └─────────┘  │                   │
                      │                │                   │
                      │  sharedDB(B)   │◄──────────────────┘
                      └────────────────┘
```

Parent A (propriétaire) crée une `CKRecordZone` dédiée au profil de l'enfant dans sa
**privateCloudDatabase**, y pousse tous les `CKRecord` (ChildProfile, Medication, MedicationLog, SeizureEvent),
puis crée un `CKShare` sur cette zone et envoie le lien à Parent B.

Parent B accepte → la zone partagée apparaît dans sa **sharedCloudDatabase**. Les deux
devices lisent/écrivent dans la même zone CloudKit ; chacun maintient sa copie locale
SwiftData en tant que cache + source de vérité offline.

## Mapping SwiftData ↔ CKRecord

| SwiftData @Model | recordType CK | Champs CK |
|---|---|---|
| ChildProfile | `Child` | firstName, birthDate?, hasEpilepsy, createdAt |
| Medication | `Medication` | name, doseAmount, doseUnit, scheduledHours (JSON), isActive, childRef |
| MedicationLog | `MedicationLog` | medicationName, scheduledTime, takenTime?, taken, dose, doseUnit, childRef |
| SeizureEvent | `Seizure` | startTime, endTime, durationSeconds, seizureType, trigger, triggerNotes, notes, childRef |

Tous les records sont rattachés via `CKRecord.Reference` à un Child parent (cascade).
L'identifiant SwiftData (`id: UUID`) est utilisé comme `recordName` pour garantir
l'unicité cross-device.

## Plan en 6 étapes

### Étape 1 — Squelette CloudKit ✅ (ce commit)
- Entitlements iCloud (Container `iCloud.fr.afsr.RettApp`)
- Capability CKSharing (`CKSharingSupported = true` dans Info.plist)
- `CloudKitSyncService` minimal : init container, `refreshAccountStatus()`
- Section Réglages "Partage entre parents" avec statut compte iCloud (read-only)
- Aucun trafic réseau encore, juste la coquille

### Étape 2 — Mapping SwiftData → CKRecord
- Pour chaque `@Model`, méthodes `func toCKRecord(zoneID:) -> CKRecord` et
  `init?(record: CKRecord, context: ModelContext)`
- Helpers d'encodage (HourMinute → JSON Data, enums → String)
- Tests unitaires de round-trip

### Étape 3 — Push (sync sortante)
- Observer SwiftData `NotificationCenter.didSave`
- File d'attente de records modifiés
- `CKModifyRecordsOperation` avec retry exponentiel (gestion `serverRecordChanged`)
- Premier `replicateAll()` au moment où on active le partage : bulk push de tout
  l'existant local vers la zone CloudKit

### Étape 4 — Pull (sync entrante)
- `CKDatabaseSubscription` sur la zone partagée
- Push silent notifications → `application(_:didReceiveRemoteNotification:)`
- `CKFetchRecordZoneChangesOperation` incrémental avec `serverChangeToken` persisté
- Application des deltas en SwiftData (insert/update/delete)
- Résolution de conflits : last-writer-wins par défaut, merge spécial sur `notes`
  (concaténation horodatée pour ne pas perdre une note d'un parent)

### Étape 5 — Création + acceptation du partage
- UI : `Settings → Partage entre parents → Inviter le second parent`
- `CKShare` sur la zone du profil
- `UICloudSharingController` (UIKit, intégré via `UIViewControllerRepresentable`)
- Lien d'invitation → AirDrop / Messages / Mail
- Côté receveur : `SceneDelegate.scene(_:userDidAcceptCloudKitShareWith:)`
  intercepte l'acceptation → `CKAcceptSharesOperation` → la zone apparaît
  dans `sharedCloudDatabase`
- Premier pull complet pour synchroniser le receveur

### Étape 6 — Polish, conflits avancés, tests
- Indicateur de sync en haut de l'app (icône iCloud + état)
- Gestion fine des erreurs (compte iCloud désactivé, quota dépassé, perte réseau)
- Bouton "Arrêter le partage" (révoque côté propriétaire)
- Tests d'intégration (CloudKit a un environnement Development distinct de Production)

## Sécurité & RGPD

| Aspect | Statut |
|---|---|
| Chiffrement en transit | TLS bout-en-bout vers iCloud |
| Chiffrement au repos | iCloud chiffre par défaut. End-to-end avec Advanced Data Protection (recommandé dans la politique de conf.) |
| Données partagées | Limitées à la zone d'un seul enfant → granularité fine |
| Révocation | Propriétaire peut retirer un participant à tout moment |
| Pas de tiers | Apple uniquement, sous DPF (transferts UE → US encadrés) |
| Consentement | À ajouter au flow d'invitation : "Vous allez partager les données de santé de [Prénom] avec [parent invité]. Confirmer ?" |
| Audit (SECURITY.md) | À mettre à jour avec la nouvelle catégorie de traitement (sous-traitance Apple iCloud) |

## Pré-requis côté Apple Developer

L'utilisateur doit :
1. Avoir un compte Apple Developer payant (CloudKit nécessite un team ID signé)
2. Activer iCloud + CloudKit dans le portail développeur :
   - https://developer.apple.com/account/resources/identifiers/list
   - Containers → Add → `iCloud.fr.afsr.RettApp`
3. Dans le **schema CloudKit Console** :
   - Créer les record types (`Child`, `Medication`, `MedicationLog`, `Seizure`)
   - OU laisser l'app créer le schema en mode Development (plus rapide), puis
     déployer en Production avant la sortie App Store
4. **Push Notifications** : déjà activées dans les entitlements (étape 1 du projet)

## Dépendances iOS

- iOS 17+ (déjà la baseline du projet)
- Compatibilité iPad (CKShare fonctionne identiquement)
- Pas de dépendance externe — tout en frameworks Apple natifs

## Estimation effort

| Étape | Effort | Risques |
|---|---|---|
| 1 — Squelette | 0,5 j | aucun |
| 2 — Mapping | 1 j | sérialisation des relations |
| 3 — Push | 1,5 j | retry, conflits initial bulk |
| 4 — Pull | 2 j | subscriptions, push silencieux, deltas |
| 5 — CKShare UI | 1,5 j | UICloudSharingController + acceptation |
| 6 — Polish | 1 j | edge cases compte/quota |
| **Total** | **~7,5 j** | itératif et testable étape par étape |
