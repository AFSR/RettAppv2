---
description: Toute nouvelle permission ou sortie de donnée oblige à corriger la politique du site et la déclaration App Store. Deux fois arrivé, dont une avec une affirmation fausse en production.
globs:
  - "RettApp/Resources/Info.plist"
  - "RettApp/Resources/PrivacyInfo.xcprivacy"
  - "RettApp/Features/Donation/**"
  - "RettApp/Core/HealthKit/**"
  - "RettApp/Features/BookletImport/**"
---

# Ce que l'application promet

L'AFSR publie, sur afsr.fr, une politique de confidentialité qui **affirme des
choses vérifiables dans ce dépôt** : les données de suivi restent sur
l'appareil, l'invitation au partage passe par AirDrop seulement, rien n'est lu
par défaut dans Apple Santé, aucun outil de mesure n'est embarqué.

Cette URL est citée dans la fiche App Store. Une affirmation devenue fausse
n'est pas un détail de rédaction.

## La règle

**Toute nouvelle permission, et toute donnée qui se met à sortir de l'appareil,
oblige à trois corrections dans le même mouvement :**

1. la clé d'usage dans `RettApp/Resources/Info.plist` — précise, pas « pour
   améliorer votre expérience », qui est le motif de refus le plus courant de
   cette catégorie ;
2. `RettApp/Resources/PrivacyInfo.xcprivacy` si une API à motif requis ou un
   type collecté change ;
3. **la politique de confidentialité dans `AFSR/website`**, dans les trois
   langues (`resources/views/legal/privacy-{fr,en,pt}.blade.php`), et la
   déclaration de confidentialité d'App Store Connect.

Ne livrez pas l'une sans les autres. Le site a des tests qui gardent ces
affirmations (`tests/Feature/LegalPagesTest.php`) : ajoutez-y la vôtre.

## C'est arrivé deux fois

**L'espace adhérent devenu natif.** La politique décrivait une vue web et un
cookie de session. Elle est restée fausse le temps d'une fusion.

**L'épingle sur la carte.** La politique affirmait « l'application utilise votre
position uniquement sur l'appareil […] elle n'est jamais envoyée à l'AFSR ».
C'était vrai quand la position ne servait qu'à centrer la carte. Dès lors qu'une
épingle posée sur soi part avec l'avis comme emplacement du lieu, la phrase
était fausse **en production**.

La leçon : la question n'est pas « demande-t-on une permission ? » mais **« que
sort-il de l'appareil, et pour quoi ? »**.

## L'état des promesses au 11 novembre 2026

| Ce qu'on affirme | Vérifiable où |
|---|---|
| Le suivi ne quitte pas l'appareil / l'iCloud personnel | Aucun appel réseau dans `Features/SeizureTracker`, `MedicationTracker`, `HealthData` |
| Apple Santé est **lu**, jamais écrit, et rien par défaut | `Core/HealthKit/HealthKitManager.swift` |
| L'invitation au partage passe par **AirDrop seulement** | `Core/Sync/ProximityShareSheet.swift`, `excludedActivityTypes` |
| Aucune mesure d'audience, aucun rapporteur d'incidents | Aucune dépendance tierce dans le projet |
| La photo du cahier est traitée sur l'appareil et effacée | `Features/BookletImport/BookletScannerView.swift` |
| Pas de caméra à détection de profondeur, aucune donnée faciale | Aucun usage d'`ARFaceTracking` ; Face ID ne rend qu'un booléen |
| La position est relevée **une fois**, à la demande | `Features/Places/PlacePinPickerView.swift`, `OneShotLocator` |

## Les types déclarés dans le manifeste

Cinq types collectés — nom, courriel, adresse postale, téléphone, identifiant
utilisateur — plus la **position précise** depuis l'épingle. Tous liés à
l'identité, **aucun** pour du pistage, tous pour le fonctionnement de l'app.

Les données de santé n'y figurent **pas**, et c'est délibéré : les déclarer
dirait que l'AFSR les détient, ce qui est faux et pire que de les omettre.

Deux API à motif requis : `UserDefaults` (CA92.1) et horodatage de fichiers
(C617.1). Ni espace disque, ni clavier actif, ni heure de démarrage.

## Le don

Il est **désactivé** dans l'app au 11 novembre 2026 : `DonationView` ouvre la
page de don du site. Le réactiver fait sortir identité et adresse postale vers
afsr.fr, puis Salesforce — et demande donc le même triptyque de corrections,
plus les réponses de l'administrateur Salesforce sur les listes de choix.
