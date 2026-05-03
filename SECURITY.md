# Audit sécurité, cyber & compliance — RettApp

Version : `1.0` — date : 2026-04-24 — périmètre : app iOS (SwiftUI, iOS 17+), commit courant.

## Sommaire

1. [Portée & données traitées](#1-portée--données-traitées)
2. [Authentification & identité](#2-authentification--identité)
3. [Stockage local](#3-stockage-local)
4. [Réseau & API tierces](#4-réseau--api-tierces)
5. [Protections OS mobilisées](#5-protections-os-mobilisées)
6. [Conformité RGPD / CNIL](#6-conformité-rgpd--cnil)
7. [Conformité App Store](#7-conformité-app-store)
8. [Menaces & mitigations](#8-menaces--mitigations)
9. [Findings & recommandations priorisées](#9-findings--recommandations-priorisées)
10. [Statut "dispositif médical" (MDR EU)](#10-statut-dispositif-médical-mdr-eu)

---

## 1. Portée & données traitées

RettApp est une application **mobile autonome**, sans backend propre. Les seules interactions réseau sortantes sont :

- L'authentification Sign in with Apple (Apple ID Servers)
- Le module Actualités (Statamic REST `https://afsr.fr/api`) — **actuellement désactivé** (`FeatureFlags.newsEnabled = false`)
- Les notifications locales (pas de push distant pour l'instant malgré `aps-environment`)

### Catégories de données traitées

| Donnée | Sensibilité (RGPD) | Stockage | Où |
|---|---|---|---|
| Prénom de l'enfant | Donnée identifiante directe d'un **mineur** | SwiftData | Appareil |
| Date de naissance enfant | Donnée identifiante de **mineur** | SwiftData | Appareil |
| Flag "a de l'épilepsie" | **Donnée de santé** (art. 9 RGPD) | SwiftData | Appareil |
| Liste des médicaments | **Donnée de santé** | SwiftData | Appareil |
| Heures de prise | **Donnée de santé** | SwiftData | Appareil |
| Historique des crises (date, durée, type, déclencheur, notes) | **Donnée de santé** | SwiftData | Appareil |
| Apple User ID (hash opaque) | Identifiant pseudonyme | Keychain | Appareil |

**Aucune** de ces données n'est exfiltrée vers les serveurs de l'AFSR ou un tiers dans l'état actuel du code. Le traitement de données de santé concernant un mineur déclenche toutefois un ensemble d'obligations RGPD décrites en §6.

## 2. Authentification & identité

### Sign in with Apple

- **Implémentation** : `ASAuthorizationAppleIDProvider` + `SignInWithAppleButton` SwiftUI, scope demandé `.fullName` uniquement (pas `.email`).
- **Stockage** : l'Apple User ID (identifiant opaque `001234.abc...`) est persisté en Keychain (`AuthManager`), service `fr.afsr.RettApp`, account `afsr.auth.appleUserID`.
- **Restauration de session** : au lancement, on valide que `credentialState(forUserID:)` renvoie `.authorized` avant de considérer l'utilisateur comme connecté. Si `revoked`/`notFound`, la session Keychain est purgée.
- **Déconnexion** : `AuthManager.signOut()` supprime l'item Keychain ; les données locales restent intactes par design (l'app est multi-session pour un même appareil familial).

### Points positifs

- ✅ Pas de mot de passe, pas de SMS, pas d'adresse email stockée par l'app
- ✅ Apple User ID est **opaque** et spécifique à l'app (impossible à recouper avec d'autres apps)
- ✅ Usage de Keychain (chiffré au repos par le Secure Enclave) plutôt que `UserDefaults`

### Points à renforcer

- ⚠️ L'item Keychain utilise la classe par défaut (`kSecClassGenericPassword`) sans `kSecAttrAccessible` explicite → il reste accessible même quand l'appareil est verrouillé. **Fix recommandé** : ajouter `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- ⚠️ Aucun verrouillage biométrique de l'app en soi. Si plusieurs personnes utilisent l'iPhone du parent, toutes peuvent voir les données. **Fix recommandé** : proposer un verrouillage Face ID/Touch ID optionnel à l'ouverture de l'app (`LocalAuthentication.framework`).
- ⚠️ Le flux `handle()` accepte la session sans vérifier `identityToken` ou `authorizationCode` (qui devraient être vérifiés côté serveur dans une architecture full-stack, mais sans backend on ne peut pas).

## 3. Stockage local

### SwiftData

- Fichier SQLite créé par `ModelContainer` dans le container de l'app (`~/Library/Application Support/default.store`).
- **Chiffrement au repos** : iOS applique automatiquement *Data Protection* classe `NSFileProtectionComplete` tant que l'appareil est verrouillé (si un code est configuré). Le fichier SQLite hérite de la classe par défaut du target. **À vérifier et forcer** via `ModelConfiguration` ou en ajoutant l'attribut `com.apple.developer.default-data-protection = NSFileProtectionComplete` dans les entitlements.
- **Sauvegardes iCloud/iTunes** : le fichier est par défaut inclus dans les backups. Pour un parent qui partage son iCloud avec le conjoint, cela signifie que les données de santé de l'enfant peuvent se retrouver sur un autre appareil. **Recommandation** : marquer le fichier avec `URLResourceKey.isExcludedFromBackupKey = true`, ou documenter clairement le comportement dans la politique de confidentialité.

### Keychain

- Un seul item : l'Apple User ID (voir §2).
- Service : `fr.afsr.RettApp`, account : `afsr.auth.appleUserID`.
- **Chiffrement** : via Secure Enclave, clé dérivée du code de déverrouillage de l'appareil.
- **Point d'amélioration** : voir §2 sur `kSecAttrAccessible`.

### Fichiers temporaires (exports CSV & imports)

- Exports CSV (`SeizureHistoryView.exportCSV`, `SettingsView.exportAllCSV`) et templates d'import écrivent dans `FileManager.default.temporaryDirectory`.
- iOS purge automatiquement ce répertoire, mais **pas immédiatement** — les fichiers y restent parfois plusieurs jours.
- ⚠️ Les fichiers CSV contiennent des **données de santé nominatives** (nom du médicament, date des crises). Si un utilisateur connecte son iPhone à un ordi non chiffré et partage le volume, ces fichiers sont accessibles.
- **Fix recommandé** : supprimer explicitement le fichier temporaire après le partage réussi (callback `UIActivityViewController.completionWithItemsHandler`).

### UserDefaults

- Utilisation : clé `afsr.seizure.recordingStartedAt` pour reprendre un chronomètre de crise après crash ou kill de l'app.
- **Pas sensible** : une simple timestamp, pas d'info médicale dedans. Pas de risque majeur.

## 4. Réseau & API tierces

### Posture actuelle

- **Module Actualités désactivé** (feature flag). Aucun appel réseau n'est fait en dehors des services Apple.
- **Pas d'analytics, pas de crash reporter, pas de SDK tiers.** Aucun Firebase, Sentry, Mixpanel, etc.
- **App Transport Security** : `NSAllowsArbitraryLoads = false` dans `Info.plist` — impossible de parler à un serveur HTTP non-TLS par accident.

### Quand le module News sera réactivé

- Endpoint `https://afsr.fr/api/collections/actualites/entries` — TLS forcé.
- **Token bearer** (`APIConfig.apiKey`) dans le binaire si configuré : **mauvaise pratique**. Les secrets embarqués dans une app iOS sont triviaux à extraire (class-dump, strings, jailbreak). **Recommandation** : si un token est nécessaire, ne pas le distribuer avec l'app — soit l'endpoint est public en lecture (collection publiée), soit passer par un intermédiaire (Lambda/Cloud Function) qui détient le secret. En pratique, pour des actualités publiques, aucun token ne devrait être requis.
- **URLCache** : 50 Mo disque, 10 Mo RAM. Le cache stocke du HTML potentiellement privé ? Non, actualités publiques uniquement. OK.
- **Contenu HTML affiché dans `WKWebView`** : risque d'**XSS** si le CMS est compromis et injecte du JS malveillant qui tenterait de lire d'autres contenus. Mitigation :
  - `WKWebView` est sandboxé et ne peut pas accéder au système de fichiers ni aux données SwiftData
  - Aucun handler JS→Swift n'est bridgé
  - **Recommandation** : ajouter une Content-Security-Policy dans le HTML injecté (`<meta http-equiv="Content-Security-Policy" content="default-src 'self' data: https:; script-src 'none';">`) pour interdire l'exécution JS dans le contenu des articles.

### Sign in with Apple

- Communication chiffrée, gérée par le framework système. Rien à auditer.

## 5. Protections OS mobilisées

- ✅ **Sandbox iOS** : l'app ne peut pas lire les données d'autres apps.
- ✅ **Keychain** chiffré par Secure Enclave (voir §3).
- ✅ **Data Protection** — à renforcer explicitement (§3).
- ✅ **Permissions granulaires** : Camera (jeu regard), FaceID (jeu regard), HealthKit (entitlements actifs mais non utilisés actuellement), UserNotifications (médicaments).
- ✅ **Sign in with Apple** : pas de gestion de mot de passe côté app.
- ⚠️ **App Attest / DeviceCheck** : non utilisé. Pour une app sans backend et sans donnée partagée, l'apport est nul, OK de s'en passer.
- ⚠️ **Jailbreak detection** : non implémenté. Sur un appareil jailbreaké, les protections Keychain et Data Protection peuvent être contournées. Détection simple possible (`access("/Applications/Cydia.app", F_OK)`) mais contournable ; pas prioritaire pour cette app.

## 6. Conformité RGPD / CNIL

### Nature des traitements

- **Catégorie** : données de santé d'un **mineur** → art. 9 RGPD (catégorie particulière) + art. 8 (consentement parental requis pour < 15 ans en France).
- **Finalité** : suivi personnel par le parent/aidant. Pas de partage, pas de recherche, pas de marketing.
- **Base légale** : art. 9.2.h (médecine préventive, intérêt vital) OU art. 9.2.a (consentement explicite). Le plus propre ici est **art. 9.2.a consentement explicite du titulaire de l'autorité parentale**.

### Exigences & statut

| Exigence | Statut | Action à faire |
|---|---|---|
| Politique de confidentialité accessible dans l'app | ⚠️ Lien vers `afsr.fr/confidentialite` mais page **à rédiger** | Rédiger avec DPO AFSR |
| Consentement explicite recueilli | ❌ Absent | Ajouter un écran de consentement au premier lancement, cocher explicitement "Je donne mon consentement pour le traitement des données de santé de mon enfant" |
| Droit d'accès / portabilité | ✅ Export CSV complet dans les Réglages | OK |
| Droit à l'effacement | ✅ "Effacer les données de l'application" dans les Réglages | OK |
| Droit à la rectification | ✅ Édition du profil et des enregistrements | OK |
| Minimisation | ✅ Seuls le prénom + date de naissance (optionnelle) sont demandés | OK |
| Conservation limitée | ⚠️ Aucune politique de purge automatique | Documenter dans la CGU : "vous êtes responsable de la purge ; l'app ne supprime rien automatiquement" |
| Registre des traitements (RGPD art. 30) | ❌ À créer côté AFSR | Tenu par le DPO |
| Sous-traitants / DPA | ✅ Aucun (pas de backend, pas de SDK tiers) | N/A |
| Transferts hors UE | ⚠️ Sign in with Apple : transfert vers Apple Inc. (USA) sous DPF ; iCloud backup éventuel | Mentionner dans la politique de confidentialité |
| Notification de violation | ⚠️ Sans backend, toute fuite vient du terminal utilisateur → responsabilité de l'utilisateur, mais AFSR doit être informée si elle apprend une brèche | Procédure à définir |
| DPIA (analyse d'impact) | ⚠️ Obligatoire dès lors qu'on traite des données de santé de mineurs à grande échelle | À faire si déploiement national |

### Recommandation consentement

Ajouter un **écran dédié** après le Sign in with Apple et avant le setup du profil :

```
Consentement parental
---------------------
RettApp traite des données de santé concernant votre enfant
(épilepsie, médicaments, crises). Ces données sont stockées
uniquement sur cet appareil et ne sont transmises à personne.

[ ] Je confirme être le titulaire de l'autorité parentale
[ ] Je consens au traitement de ces données par l'application

              [Lire la politique de confidentialité]

                       [Continuer]  [Refuser]
```

Un refus doit empêcher l'usage de l'app (pas juste un warning).

## 7. Conformité App Store

### Exigences Apple à satisfaire avant soumission

| Exigence | Statut | Action |
|---|---|---|
| Privacy Manifest (`PrivacyInfo.xcprivacy`) | ❌ Absent — **obligatoire depuis iOS 17** pour les apps qui utilisent des APIs à raison requise | À créer — voir ci-dessous |
| App Tracking Transparency | ✅ N/A (aucun tracking) | — |
| Kids Category / pour enfants | ⚠️ L'app n'est pas dans la catégorie Kids (elle cible les parents) mais traite des données d'enfants. Documenter l'audience cible dans App Store Connect | — |
| Usage Descriptions (`NS*UsageDescription`) | ✅ Toutes présentes (Camera, Face ID, Health Share, Health Update) | OK |
| Sign in with Apple | ✅ Entitlements et flow implémentés correctement | OK |
| Rejet "Sensitive health data" | ⚠️ Apple demande la mise à jour régulière et une politique de confidentialité explicite | OK si §6 appliqué |
| Age rating | ⚠️ 4+ a priori (aucun contenu sensible), mais avec catégorie Médical | À confirmer dans App Store Connect |

### Privacy Manifest requis

Créer `RettApp/Resources/PrivacyInfo.xcprivacy` :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key>
  <false/>
  <key>NSPrivacyTrackingDomains</key>
  <array/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array/>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array><string>CA92.1</string></array>
    </dict>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array><string>C617.1</string></array>
    </dict>
  </array>
</dict>
</plist>
```

### Déclaration Data Collection (App Store Connect → Privacy)

Les réponses à la question "Quelles données collectez-vous ?" :

- **Contact Info > Name** : oui (prénom enfant), liée à l'utilisateur, utilisée pour App Functionality uniquement, non partagée, non trackée.
- **Health & Fitness** : oui, liée à l'utilisateur, App Functionality, non partagée, non trackée.
- **Identifiers > User ID** : oui (Apple User ID), App Functionality, non partagée, non trackée.
- **Tout le reste** : non.

## 8. Menaces & mitigations

Modèle : **STRIDE simplifié appliqué à une app mobile sans backend**.

| Menace | Vecteur | Impact | Mitigation en place | Gap |
|---|---|---|---|---|
| **S**poofing | Quelqu'un se connecte avec ton Apple ID | Accès aux données | Apple ID = Face ID/Touch ID | ❌ Pas de 2e verrouillage app-level |
| **T**ampering local | Jailbreak + modification du SQLite | Falsification de l'historique | Sandbox iOS + chiffrement au repos | ⚠️ Pas de signature/checksum sur les données |
| **R**epudiation | "Ce n'est pas moi qui ai enregistré cette crise" | Faible (usage perso) | Timestamp fiable | OK |
| **I**nformation disclosure | Partage de l'iPhone, backup iCloud, export CSV | Divulgation de données de santé | Keychain, `tempDirectory` partiel | ⚠️ Exports CSV persistent, backup non-exclu |
| **D**enial of Service | — | Faible (pas de backend) | — | N/A |
| **E**levation of privilege | App bug permettant écriture hors sandbox | Aucune écriture hors app | Sandbox iOS, pas de code natif C unsafe | OK |

### Scénarios concrets

1. **iPhone perdu/volé, code déverrouillage simple** : Data Protection tient tant que l'appareil reste verrouillé. Une fois déverrouillé par brute-force (code à 4 chiffres = 10 000 combinaisons), les données sont en clair.
   → Fix : sensibiliser à utiliser un code à 6 chiffres ou biométrie + ajouter un verrouillage Face ID dans l'app.

2. **Partage du téléphone au sein de la famille** : autre membre voit tout.
   → Fix : verrouillage Face ID optionnel dans Réglages.

3. **Fuite via CSV exporté envoyé à un médecin** : le fichier quitte l'écosystème Apple. C'est voulu (portabilité) mais à documenter.

4. **Injection XSS via CMS Statamic compromis** (news réactivé) : cf. §4, sandbox `WKWebView` limite le blast radius.

5. **Reverse engineering du binaire pour extraire un token API** : aucun token sensible n'est embarqué aujourd'hui. À respecter.

## 9. Findings & recommandations priorisées

### 🔴 P0 — Bloquant avant publication App Store

1. **Créer `PrivacyInfo.xcprivacy`** — obligatoire iOS 17, l'app sera rejetée sans. (§7)
2. **Rédiger et publier la politique de confidentialité** sur `afsr.fr/confidentialite` — lien déjà présent dans l'app mais la page doit exister. (§6)
3. **Ajouter un écran de consentement parental explicite** au premier lancement — exigence RGPD art. 8 + 9. (§6)

### 🟠 P1 — Avant déploiement national

4. **Forcer `NSFileProtectionComplete` via entitlements** pour garantir le chiffrement au repos du SQLite SwiftData. Ajouter dans `RettApp.entitlements` :
   ```xml
   <key>com.apple.developer.default-data-protection</key>
   <string>NSFileProtectionComplete</string>
   ```
5. **Durcir le Keychain** : ajouter `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` dans `AuthManager`.
6. **Ajouter un verrouillage biométrique (Face ID/Touch ID) optionnel** dans les Réglages (`LocalAuthentication` framework) — *defense in depth*.
7. **Exclure le store SwiftData des backups iCloud** (`URLResourceKey.isExcludedFromBackupKey`) OU documenter que les backups sont chiffrés si l'utilisateur active l'iCloud chiffré de bout en bout.
8. **Supprimer les CSV temporaires après partage** via `UIActivityViewController.completionWithItemsHandler`.

### 🟡 P2 — Recommandé

9. **CSP dans le HTML des articles** (quand News réactivé) — `<meta http-equiv="Content-Security-Policy">` dans le wrapper HTML de `NewsDetailView`.
10. **DPIA** (analyse d'impact RGPD) à conduire par le DPO de l'AFSR si l'app dépasse quelques centaines d'utilisateurs.
11. **Journalisation des actions sensibles** (export, effacement) dans un log local consultable par l'utilisateur, non transmis. Utile en cas de litige / audit.
12. **Registre des traitements RGPD art. 30** tenu par le DPO AFSR.
13. **Ne jamais introduire de SDK tiers** (analytics, crash reporting) sans repasser cet audit. Préférer `MetricKit` (Apple, pas de sortie réseau) pour des métriques anonymisées si besoin.

### 🟢 P3 — Nice-to-have

14. **Détection jailbreak** basique — faible valeur ajoutée pour une app de suivi personnel, à ignorer sauf demande spécifique.
15. **Test de pénétration externe** si le module News devient un vrai backend (authent, écriture côté serveur).
16. **MASVS Level 1** (OWASP Mobile AppSec) : auto-évaluation, l'app coche la plupart des contrôles niveau 1 par design (pas de backend, pas de secrets, pas de SDK tiers).

---

## Appendice A — Surface d'attaque résumée

```
┌──────────────────────────────────┐
│  Appareil iOS (utilisateur)       │
│                                   │
│   ┌──────────┐    ┌──────────┐   │
│   │  Face ID │    │ Keychain │   │
│   │  + code  │    │  (Apple  │   │
│   │          │    │   User   │   │
│   └────┬─────┘    │   ID)    │   │
│        │          └──────────┘   │
│   ┌────▼─────────────────────┐   │
│   │    App RettApp           │   │
│   │  ┌────────┐  ┌────────┐ │   │
│   │  │SwiftData│ │tempDir │ │   │
│   │  │(santé) │  │(exports)│ │   │
│   │  └────────┘  └────────┘ │   │
│   └──┬──────────────┬───────┘   │
│      │              │            │
└──────┼──────────────┼────────────┘
       │              │
       ▼              ▼
  ┌────────┐    ┌──────────┐
  │ Apple  │    │ Partage  │
  │ IDaaS  │    │ utilisat.│
  └────────┘    └──────────┘
```

---

## Appendice B — Checklist de revue par release

- [ ] Aucun SDK tiers ajouté sans audit
- [ ] Aucun secret embarqué (grep sur `apiKey`, `token`, `password`, `secret` dans les sources)
- [ ] Aucun log contenant des données de santé (grep sur `print(`, `os_log`)
- [ ] Le Privacy Manifest est à jour par rapport aux APIs effectivement utilisées
- [ ] La politique de confidentialité `afsr.fr/confidentialite` reste publiée et accessible
- [ ] Les entitlements actifs correspondent aux features réellement utilisées (pas de HealthKit actif si non utilisé)
- [ ] ATS reste strict (`NSAllowsArbitraryLoads = false`)
- [ ] Les tests de schéma SwiftData ne cassent pas la migration pour les données existantes d'utilisateurs

---

*Audit à refaire à chaque ajout de dépendance tierce, activation du module News, ou ajout d'une synchronisation cloud.*

---

## 10. Statut "dispositif médical" (MDR EU)

### Position retenue : **non-dispositif médical**

RettApp **n'est pas un dispositif médical** au sens du Règlement européen 2017/745 (MDR), du UK Medical Device Regulations, ni des règles FDA. Aucune certification CE médicale, marquage UKCA, ou clearance FDA n'est requise dans le périmètre actuel.

### Justification

D'après le **MDCG 2019-11** (guide officiel européen de classification des logiciels santé) et l'art. 2 du MDR, un logiciel est qualifié de dispositif médical s'il est destiné au "diagnostic, traitement, prédiction, pronostic, atténuation" d'une maladie. Pour chaque fonctionnalité actuelle de RettApp :

| Fonctionnalité | Qualification |
|---|---|
| Journal des crises (date, durée, type, notes) | Patient diary / logbook → **non-MD** |
| Plan médicamenteux + rappels horaires | Aide à l'observance, dose saisie par l'utilisateur → **non-MD** |
| Export CSV vers le neurologue | Outil de communication patient/médecin → **non-MD** |
| Jeu eye-tracking « tarte à la crème » | Loisir / éveil, pas de revendication thérapeutique → **non-MD** |

### Lignes rouges à ne pas franchir

L'app basculerait en **dispositif médical classe IIa minimum** (et donc obligation CE) si elle implémentait :

- Recommandation automatique de dose
- Détection automatique de crise (caméra, accéléromètre, IA)
- Alertes prédictives (pré-crise)
- Analyse statistique avec interprétation clinique ("votre épilepsie s'aggrave")
- Tout texte marketing du type "diagnostique l'épilepsie", "réduit les crises", "améliore le traitement"

### Mesures concrètes en place

1. **Onboarding** : avertissement médical encadré + case "J'ai lu et compris" obligatoire avant de pouvoir continuer (`ProfileSetupView.disclaimerCard`).
2. **Réglages** : section "Avertissement médical" toujours visible, mention de l'urgence (15/112).
3. **App Store Connect** : déclaratif "Regulated medical device" → réponse `No`, justifiée par l'absence de certification CE/FDA/UKCA.
4. **Politique de confidentialité** (à publier) : doit reprendre la mention "RettApp n'est pas un dispositif médical au sens du règlement UE 2017/745. Elle ne remplace pas le suivi par un professionnel de santé."

### Recommandation

Avant déploiement national à grande échelle, faire valider cette analyse par un avocat spécialisé en santé numérique (ou consulter directement l'**ANSM**). Coût estimé : 1-2 h de conseil.

### Référence App Store Connect

Pour le déclaratif Apple : https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status — sélectionner **No** par pays/région.
