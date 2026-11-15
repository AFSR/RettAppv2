# Audit sécurité, cyber & compliance — RettApp

Version : `2.0` — date : 2026-11-15 — périmètre : app iOS (SwiftUI, SwiftData, CloudKit, iOS 17+).
Révision de l'audit `1.0` du 2026-04-24, dont une grande partie décrivait une app qui n'existe plus.

Pour signaler une vulnérabilité, voir [`SECURITY.md`](../SECURITY.md) : ce document-ci est
l'audit du code, pas la procédure de signalement.

**Méthode et limites.** Cette version a été établie par **lecture du code**, avec des
recherches ciblées pour chaque affirmation. L'app **n'a été ni compilée ni exécutée** :
rien ici n'est un résultat de test. Ne sont pas couverts : le site `afsr.fr` (dépôt
`AFSR/website`), Salesforce, et les déclarations faites dans App Store Connect. Quand une
chose n'a pas été vérifiée, c'est écrit.

Les décisions d'architecture et leurs raisons sont dans `docs/ARCHITECTURE.md` ; ce
document en tire les conséquences pour la sécurité.

## Sommaire

1. [Ce qui a changé depuis l'audit 1.0](#1-ce-qui-a-changé-depuis-laudit-10)
2. [Portée & données traitées](#2-portée--données-traitées)
3. [Espace adhérent : authentification](#3-espace-adhérent--authentification)
4. [Stockage local](#4-stockage-local)
5. [Réseau](#5-réseau)
6. [Protections OS mobilisées](#6-protections-os-mobilisées)
7. [Conformité RGPD / CNIL](#7-conformité-rgpd--cnil)
8. [Conformité App Store](#8-conformité-app-store)
9. [Menaces & mitigations](#9-menaces--mitigations)
10. [Findings & recommandations](#10-findings--recommandations)
11. [Statut « dispositif médical » (MDR EU)](#11-statut--dispositif-médical--mdr-eu)

---

## 1. Ce qui a changé depuis l'audit 1.0

| Affirmation de l'audit 1.0 | État vérifié dans le code |
|---|---|
| « Application autonome, sans backend » | **Faux.** L'app parle à `afsr.fr` : espace adhérent, annuaire des lieux, actualités. |
| Connexion par Sign in with Apple, Apple User ID dans le Keychain | **Disparu.** Aucun `ASAuthorization` ni `AuthManager`. L'app n'a pas de compte pour le suivi ; l'espace adhérent a sa propre connexion (§3). |
| Module Actualités désactivé | **Activé** : `FeatureFlags.newsEnabled = true`. |
| « Aucun handler JS→Swift » dans la `WKWebView` | **Faux** pour les articles : deux handlers (`contentHeight`, `imageTap`). |
| `PrivacyInfo.xcprivacy` absent | **Présent**, et copié dans la phase *Resources* du projet. |
| HealthKit « actif mais non utilisé » | **Utilisé**, en **lecture seule** (`requestAuthorization(toShare: [], read:)`). |
| Caméra et Face ID pour un « jeu de regard » | Le jeu n'existe plus. La caméra scanne le cahier de suivi papier (OCR) ; Face ID verrouille l'espace adhérent. |
| Pas de synchronisation cloud | **CloudKit** : partage entre parents dans l'iCloud personnel de la famille, invitation par AirDrop seulement. |

## 2. Portée & données traitées

Deux domaines qui ne se touchent pas (`docs/ARCHITECTURE.md`) :

- **Le suivi médical** vit dans SwiftData sur l'iPhone et, si le partage entre parents est
  activé, dans l'iCloud personnel de la famille. **Aucun serveur de l'AFSR ne le reçoit.**
- **Les données de l'association** (adhésion, dons, reçus, coordonnées) sont dans
  Salesforce, via `afsr.fr`. L'app les affiche, elle ne les conserve pas.

### Ce qui sort de l'appareil

| Destination | Quoi | Pourquoi |
|---|---|---|
| iCloud personnel (CloudKit) | Le suivi, si le partage entre parents est activé | Synchronisation entre parents ; Apple est sous-traitant de la famille, pas de l'AFSR |
| `afsr.fr` `/api/membre` | Identité d'adhérent, avis et lieux proposés, **coordonnées de l'épingle** posée sur la carte | Espace adhérent et annuaire des lieux |
| `afsr.fr` `/api` | Lecture des actualités (rien n'est envoyé hors la requête) | Onglet Actualités |
| `itunes.apple.com/lookup` | Identifiant de l'app | Savoir si une mise à jour existe |
| Apple Plans (MapKit) | Requêtes de carte | Annuaire des lieux |

Le client de don (`DonationAPIClient`, `/api/mobile/contribution`) existe dans le projet
mais **aucune vue ne l'appelle** : le don ouvre la page du site. Son `appToken` est une
chaîne vide. Le réactiver fait sortir identité et adresse postale : voir
`.claude/rules/promesses-confidentialite.md`.

### Catégories de données

| Donnée | Sensibilité (RGPD) | Où |
|---|---|---|
| Prénom de l'enfant, date de naissance (optionnelle) | Identifiante, **mineur** | SwiftData |
| Épilepsie, médicaments, prises, crises, symptômes, humeur | **Santé** (art. 9) | SwiftData, iCloud de la famille si partagé |
| Apple Santé (sommeil, hydratation, repas, activité, rythme cardiaque) | **Santé** | **Lu**, jamais écrit ; rien n'est lu par défaut |
| Jeton d'accès de l'espace adhérent | Secret | Keychain, derrière Face ID ou code |
| Coordonnées d'un lieu | Position précise | Relevée **une fois**, à la demande ; part avec l'avis |

## 3. Espace adhérent : authentification

Connexion par code à usage unique. Le jeton d'accès est dans le Keychain
(`MemberKeychain`, service `fr.afsr.RettApp.member`).

- **Jeton d'accès** : `SecAccessControl` avec `.biometryCurrentSet` **ou** `.devicePasscode`,
  classe `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`. Sans code de verrouillage sur
  l'iPhone, l'enregistrement est **refusé** (`deviceNotSecured`) : le jeton n'est jamais
  stocké sans protection. Si les visages enregistrés changent, la biométrie n'ouvre plus rien,
  le code reste.
- **Jeton de révocation** : hors verrou, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
  pour pouvoir révoquer sans demander Face ID.
- **Client HTTP** : session **éphémère**, sans cache disque ni cookies ; une réponse 401
  déclenche la déconnexion.
- **Politique d'échec** : annuler l'invite Face ID ne compte pas comme un échec ; un refus, oui.

**Limites.** Ce verrou ne protège **que l'espace adhérent**. Le suivi médical n'a aucun
verrouillage propre : quiconque déverrouille l'iPhone voit les données de l'enfant. Le jeton
qui identifie l'*application* auprès du site est extractible du binaire (c'est dit dans
`docs/ARCHITECTURE.md`) : la protection réelle est côté serveur, **non vérifiée ici**.

## 4. Stockage local

### SwiftData

- Le fichier est dans le container de l'app. **Aucune classe de protection n'est forcée** :
  ni `NSFileProtection` dans le code, ni `com.apple.developer.default-data-protection`
  dans les entitlements. C'est donc la classe par défaut d'iOS qui s'applique, soit
  *Complete Until First User Authentication* : le fichier reste lisible après le premier
  déverrouillage qui suit le démarrage, même écran verrouillé.
- Le fichier **n'est pas exclu des sauvegardes** (aucun `isExcludedFromBackupKey`).
- ⚠️ La récupération du magasin **efface le fichier** en cas d'échec d'ouverture
  (`RettAppApp.swift`) : toute évolution de schéma est un risque pour les données des
  familles. Voir `.claude/rules/sync-cloudkit.md`.

### Autres fichiers locaux

- Corbeille, écritures en attente, instantanés de sécurité : fichiers JSON dans
  *Application Support*.
- **Exports CSV** : `SeizureHistoryView.exportCSV` écrit dans `temporaryDirectory` et ne
  supprime rien après le partage ; l'export complet des Réglages (`exportAllCSV`) crée un
  dossier `rettapp-export-…` dans le même répertoire, **sans suppression visible** non plus.
  Ces fichiers contiennent des données de santé nominatives et restent jusqu'à la purge
  d'iOS.
- **Documents de l'espace adhérent** : répertoire dédié `afsr-documents` dans
  `temporaryDirectory`, avec une routine de suppression (`MemberAPIClient.swift`) ; son
  moment d'exécution n'a pas été vérifié.
- **UserDefaults** : bien plus qu'un chronomètre — jetons de synchronisation CloudKit,
  sélection de types Apple Santé, version ignorée, indicateur de session. L'inventaire
  complet n'a pas été refait ; le manifeste déclare le motif `CA92.1`.

### Keychain

Deux éléments, tous deux de l'espace adhérent (§3). L'item « Apple User ID » de l'audit 1.0
n'existe plus.

## 5. Réseau

- **ATS strict** : `NSAllowsArbitraryLoads = false`.
- **Aucun SDK tiers** : le projet ne contient aucune référence à un paquet Swift. Pas
  d'analytics, pas de rapporteur d'incidents.
- **Hôtes contactés** : `afsr.fr`, `itunes.apple.com`, Apple (CloudKit, Plans). Les images
  des actualités sont chargées depuis l'URL que le contenu donne.
- **Cache des actualités** : 50 Mo disque, 10 Mo mémoire. Contenu public uniquement. Le
  client de l'espace adhérent n'a, lui, **aucun cache**.

### `WKWebView` (actualités et espace adhérent)

Les articles sont rendus en HTML dans une `WKWebView`, base `https://afsr.fr`.

- JavaScript actif, avec **deux handlers** vers Swift (hauteur du contenu, toucher d'image)
  et un script injecté. Ils ne transmettent qu'un nombre et une URL d'image, mais l'audit 1.0
  se trompait en disant qu'il n'y en avait aucun.
- **Aucune Content-Security-Policy** dans le HTML encapsulé (recherche vide). Un CMS compromis
  pourrait injecter du script dans un article. Le bac à sable de la `WKWebView` limite les
  dégâts (pas d'accès à SwiftData ni au Keychain), mais pas ce que fait le script dans la
  page.
- Le délégué de navigation n'a pas été relu pour cet audit.

## 6. Protections OS mobilisées

- ✅ Bac à sable iOS ; Keychain avec contrôle d'accès (§3) ; Face ID n'expose qu'un booléen.
- ✅ Permissions à usage précis (`Info.plist`) : Apple Santé (lecture), Face ID, caméra
  (scan du cahier), position **à l'usage**, une seule fois.
- ⚠️ Data Protection non renforcée (§4).
- ⚠️ `aps-environment` vaut `development` dans le fichier d'entitlements versionné, avec le
  mode d'arrière-plan `remote-notification` déclaré. Xcode le remplace à l'archivage de
  distribution : **à confirmer sur une archive réelle**, c'est une cause classique de
  régression silencieuse.
- App Attest / DeviceCheck, détection de jailbreak : non utilisés. Pour une app sans compte
  côté AFSR, l'apport est faible.

## 7. Conformité RGPD / CNIL

L'AFSR **ne détient pas** les données de suivi. Cela change son rôle, et la qualification
exacte (responsable de traitement, sous-traitant, ou aucun des deux pour ces données) est
**une question juridique que ce document ne tranche pas**.

| Exigence | Statut |
|---|---|
| Politique de confidentialité | Servie par le site, en trois langues, à `afsr.fr/rettapp/confidentialite`. Chaque affirmation vérifiable est suivie dans `.claude/rules/promesses-confidentialite.md` |
| Droit d'accès / portabilité | Export CSV complet dans les Réglages |
| Droit à l'effacement | « Effacer les données de l'application » dans les Réglages ; corbeille ; pierres tombales pour le partage |
| Minimisation | Prénom et date de naissance optionnelle seulement |
| Consentement parental explicite | **Absent** : aucun écran dédié (recherche vide). Il y a un avertissement médical à cocher à la création du profil. À trancher avec le DPO |
| Registre art. 30, DPIA | Côté AFSR, non vérifiables ici |
| Transferts hors UE | iCloud et Apple Plans : Apple Inc. À mentionner dans la politique |
| Procédure de violation | À définir |
| Conservation | Aucune purge automatique |

Les données de l'espace adhérent (identité, adresse, téléphone) sont, elles, bien dans le
périmètre de l'AFSR : elles sont déclarées au manifeste (§8) et relèvent de Salesforce.

## 8. Conformité App Store

| Exigence | Statut |
|---|---|
| Privacy Manifest | ✅ Présent ; dans la phase *Resources* du projet |
| Suivi (ATT) | ✅ Aucun (`NSPrivacyTracking = false`) |
| API à motif requis | ✅ `UserDefaults` (`CA92.1`), horodatage de fichiers (`C617.1`) |
| Clés d'usage `Info.plist` | ✅ Santé ×2, Face ID, position, caméra, toutes précises |
| Types collectés déclarés | ✅ **6** au manifeste : nom, courriel, adresse postale, téléphone, identifiant utilisateur, **position précise** (ajoutée le 2026-11-15) |
| Déclaration App Store Connect, politique du site | ⚠️ Doivent dire la même chose que le manifeste ; **non vérifié ici** |

### Position précise : manifeste corrigé, le reste à aligner

`PlaceModels.swift` envoie `latitude` et `longitude` dans le `Payload` de l'avis, et
`PlacePinPickerView` les relève avec `OneShotLocator`, une seule fois, à la demande.
Le manifeste ne déclarait pas ce type alors que `.claude/rules/promesses-confidentialite.md`
disait le contraire. **Il le déclare depuis le 2026-11-15** : position précise, liée à
l'identité, sans pistage, pour le fonctionnement de l'app.

La règle demande trois corrections ensemble ; seule la première est faite ici :

- [x] `Info.plist` : la clé d'usage de la position existait déjà et est précise ;
- [x] `PrivacyInfo.xcprivacy` : type ajouté ;
- [ ] la déclaration de confidentialité d'**App Store Connect** (non vérifiable d'ici) ;
- [ ] la **politique de confidentialité** du site, dans les trois langues, et le test
  `LegalPagesTest` qui la garde (dépôt `AFSR/website`, non consulté pour cet audit).

## 9. Menaces & mitigations

Modèle STRIDE simplifié.

| Menace | Vecteur | Mitigation en place | Écart |
|---|---|---|---|
| **S**poofing | Quelqu'un utilise l'iPhone déverrouillé | Face ID ou code pour l'espace adhérent | ❌ Aucun verrou sur le suivi médical |
| **T**ampering | Jailbreak + modification du SQLite | Bac à sable iOS | ⚠️ Pas de somme de contrôle |
| **R**epudiation | — | Horodatage | Faible enjeu |
| **I**nformation disclosure | iPhone partagé, sauvegarde, CSV exporté, article piégé | Keychain verrouillé, session éphémère | ⚠️ CSV persistants, sauvegarde non exclue, pas de CSP |
| **D**enial of service | Magasin SwiftData qui ne s'ouvre plus | — | ⚠️ La récupération **efface** les données |
| **E**levation | — | Bac à sable | OK |

Scénarios : iPhone volé avec code court (la classe de protection par défaut ne tient plus
après le premier déverrouillage) ; téléphone partagé en famille ; CSV envoyé hors de
l'écosystème Apple (voulu, à documenter) ; article de CMS compromis ; extraction du jeton
d'application du binaire (protégé côté serveur, non vérifié ici).

## 10. Findings & recommandations

L'app est publiée (1.9) : les priorités ci-dessous ne sont plus « avant publication ».

### 🔴 P0 — À traiter avant le prochain envoi

1. **Aligner App Store Connect et la politique du site** sur la position précise, désormais
   déclarée au manifeste (§8). Le manifeste seul ne suffit pas : les trois doivent dire
   la même chose.
2. **Déployer le type `Tombstone` en production CloudKit** (`.claude/rules/sync-cloudkit.md`) :
   sans cela, le partage entre parents casse chez les vraies familles, et nulle part ailleurs.
   Non déployé au 11 novembre 2026 selon `CLAUDE.md` ; l'état de la console n'a pas été
   revérifié.
3. **Compiler.** Au 11 novembre 2026 (`CLAUDE.md`), tout `Features/Places`, la corbeille et
   les pierres tombales n'avaient jamais été compilés.

### 🟠 P1

4. **Verrouillage biométrique optionnel du suivi médical**, aujourd'hui limité à l'espace adhérent.
5. **Forcer la classe de protection** du magasin (`NSFileProtectionComplete`) ou documenter
   pourquoi la classe par défaut suffit. Même question pour l'exclusion des sauvegardes.
6. **Supprimer les CSV temporaires après le partage** (`completionWithItemsHandler`).
7. **Content-Security-Policy** dans le HTML des articles et de l'espace adhérent :
   `script-src 'none'` suffit aux articles, **à condition** de remplacer le script injecté
   (hauteur, image, courriels) par autre chose, puisqu'il serait lui aussi bloqué.
8. **Consentement parental** : décider avec le DPO s'il faut un écran dédié.
9. **Confirmer `aps-environment`** sur une archive de distribution (§6).

### 🟡 P2

10. DPIA et registre art. 30 côté AFSR. Procédure de violation.
11. Ne jamais introduire de SDK tiers sans repasser cet audit.
12. Retirer `DonationAPIClient`, ou le garder en sachant qu'il est mort : tant qu'il est
    dans la cible, il compte dans la surface à auditer.

## 11. Statut « dispositif médical » (MDR EU)

**Position retenue : non-dispositif médical** — une aide de suivi et de communication avec
les soignants, sans revendication de diagnostic ni de traitement. Cette position date de
l'audit 1.0 et **doit être revue**, parce que l'app a changé.

### Ce qui a changé

Depuis l'audit 1.0, l'app **calcule des corrélations** sur les données de suivi
(`MedicalReportAnalysis`, pour le rapport au médecin) et **les traduit en phrases pour le
parent** (`SeizureInsights`, dans le Bilan : « tendance … observée sur N jours, une tendance
n'est pas une cause »). Le seuil de 14 jours et les nuances obligatoires montrent une
prudence réelle.

Or l'audit 1.0 plaçait parmi les lignes rouges « analyse statistique avec interprétation
clinique ». Que ces phrases la franchissent ou non est **une question de qualification
réglementaire que je ne peux pas trancher** ; le texte, le ton et le public (parent ou
soignant) comptent autant que le calcul.

### Lignes rouges

L'app basculerait en dispositif médical si elle recommandait une dose, détectait ou prédisait
une crise, ou affirmait diagnostiquer, réduire les crises ou améliorer le traitement.

### Mesures en place

1. Avertissement médical à cocher à la création du profil (`ProfileSetupView`), avec la
   mention « n'est pas un dispositif médical » et l'urgence (15/112).
2. Même mention sur l'écran de verrou de l'espace adhérent (`MemberLockView`).
3. App Store Connect : la réponse « Regulated medical device » devrait être `No` ;
   **non vérifié ici**, à contrôler dans la console.

### Recommandation

Faire valider par un juriste en santé numérique (ou consulter l'ANSM), **en lui montrant le
Bilan tel qu'il s'affiche**, pas seulement la liste des fonctions. Référence Apple :
https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status

---

## Appendice — Checklist de revue par release

- [ ] Aucun SDK tiers ajouté sans audit
- [ ] Aucun secret embarqué (`apiKey`, `token`, `password`, `secret`)
- [ ] Aucun journal contenant des données de santé (`print(`, `os_log`)
- [ ] Le Privacy Manifest correspond aux données qui sortent **réellement** (§8)
- [ ] La politique `afsr.fr/rettapp/confidentialite` décrit ce que l'app fait vraiment
- [ ] Les entitlements actifs correspondent aux fonctions utilisées ; `aps-environment` vérifié sur l'archive
- [ ] ATS reste strict
- [ ] Tout nouveau type CloudKit est déployé en production avant l'envoi
- [ ] Les évolutions de schéma SwiftData ne déclenchent pas la récupération qui efface le magasin

*Audit à refaire à chaque ajout de dépendance, de permission, de donnée qui sort de
l'appareil, ou de calcul présenté au parent.*
