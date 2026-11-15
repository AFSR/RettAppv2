# RettApp — l'application iOS de l'AFSR

*English: RettApp is the native iOS companion app of the Association Française du
Syndrome de Rett (AFSR), the French Rett syndrome association. It helps families
and carers track seizures, medication, mood and symptoms. Health tracking data stays
on the device (or in the family's own iCloud); nothing is sent to an AFSR server.
The code and documentation are in French. Apache License 2.0.*

Application iOS native (SwiftUI), éditée par l'**Association Française du Syndrome
de Rett** et publiée sur l'App Store. Elle accompagne les parents et aidants dans
le suivi quotidien d'enfants atteints du syndrome de Rett.

## Ce que l'application promet

Trois engagements, posés par l'association, qui s'appliquent à toute modification
(détail et raisons : [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)) :

1. **Les données de suivi médical ne quittent jamais l'appareil** ni l'iCloud
   personnel de la famille. Aucun serveur de l'AFSR ne les reçoit.
2. **Salesforce est la base de référence** pour ce qui touche à l'association
   (dons, adhésions, reçus fiscaux). L'app ne conserve ni ne calcule rien de ce domaine.
3. **L'application ne détient aucun secret** : ni clé de paiement, ni identifiants
   Salesforce.

Une contribution qui enfreint l'un de ces points sera refusée.

## Fonctionnalités

- **Profil enfant** et modes d'usage (famille / découverte)
- **Suivi d'épilepsie** : chronomètre, qualification, historique, export CSV
- **Médicaments** : plan, prises, journal, base publique BDPM embarquée
- **Humeur, observations quotidiennes, symptômes**
- **Tableau de bord** et analyses des données de suivi
- **Rapports** : rapport médical PDF, carnet de suivi (génération, scan/import par QR)
- **Apple Santé** en **lecture seule** : rien n'est lu par défaut, rien n'est écrit
- **Synchronisation CloudKit** entre parents, corbeille, sauvegardes combinées
  ([`docs/CLOUDKIT_SYNC.md`](docs/CLOUDKIT_SYNC.md))
- **Actualités** de l'AFSR et **espace adhérent**, avec l'annuaire des lieux « Rett
  friendly » ([`docs/MEMBER_AREA.md`](docs/MEMBER_AREA.md))
- **Don** : l'écran ouvre la page de don du site. Le don par Apple Pay est désactivé
  ([`disabled-features/donation-applepay/README.md`](disabled-features/donation-applepay/README.md))

## Stack

SwiftUI (iOS 17+, Swift 5.9), `@Observable`, SwiftData, CloudKit, HealthKit, WebKit.
**Aucune dépendance tierce.**

## Structure

```
RettApp/
├── Core/        # AFSRLinks, Backup, HealthKit, Profile, Sync, Trash, Update
├── Features/    # BookletImport, Dashboard, Discovery, Donation, HealthData,
│                # MedicationTracker, MemberArea, MoodTracker, News, Places,
│                # Reports, SeizureTracker, Settings, SymptomTracker
├── Shared/      # Composants (AFSR*), thème, utilitaires
└── Resources/   # Info.plist, entitlements, assets, Localizable.strings, bdpm.sqlite
RettAppTests/    # Tests unitaires
docs/            # Architecture, synchronisation, espace adhérent, fiche App Store, audit
scripts/         # Génération du projet Xcode et de la base BDPM
```

## Compiler

Il faut **macOS et Xcode**.

```bash
open RettApp.xcodeproj
```

Le projet Xcode est **généré** : après tout ajout, renommage ou suppression de
fichier source, relancez le générateur (gem `xcodeproj`). Une modification faite
à la main dans Xcode est perdue à la régénération suivante.

```bash
ruby scripts/generate_xcodeproj.rb
```

C'est le seul générateur. La version et le numéro de build vivent dans ce script
et nulle part ailleurs (voir [`.claude/rules/xcodeproj.md`](.claude/rules/xcodeproj.md)).

**Signature.** Les capacités iCloud (conteneur `iCloud.fr.afsr.RettApp`), HealthKit
et notifications sont rattachées au compte développeur de l'AFSR. Sans ce compte,
choisissez votre propre *Team* dans **Signing & Capabilities** et changez
l'identifiant de bundle et le conteneur iCloud, ou retirez ces capacités pour
compiler en local.

## Tests

```bash
xcodebuild test -scheme RettApp -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Contribuer

- Ouvrez d'abord une *issue* pour tout changement important.
- Respectez les trois engagements ci-dessus. Toute nouvelle permission, et toute
  donnée qui se met à sortir de l'appareil, oblige à corriger ensemble la clé
  d'usage, le manifeste de confidentialité et la politique publiée sur afsr.fr
  (voir [`.claude/rules/promesses-confidentialite.md`](.claude/rules/promesses-confidentialite.md)).
- Les commentaires sont en français et disent **pourquoi**, pas quoi.
- Ne signalez pas une faille de sécurité dans une *issue* publique : voir
  [`SECURITY.md`](SECURITY.md).

Les dossiers `.claude/` et le fichier `CLAUDE.md` contiennent les consignes données
aux assistants de code ; ils documentent aussi des pièges réels du projet et valent
la lecture.

## Licence

Copyright © 2026 Association Française du Syndrome de Rett (AFSR). Distribué sous
licence Apache 2.0 : voir [`LICENSE`](LICENSE) et [`NOTICE`](NOTICE).
