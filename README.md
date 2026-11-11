# RettApp — Application iOS AFSR

Application iOS native (SwiftUI) développée pour l'**Association Française du Syndrome de Rett** afin d'accompagner les parents et aidants dans le suivi quotidien d'enfants atteints du syndrome de Rett.

## Fonctionnalités

- 👤 **Profil enfant** et modes d'usage (famille / découverte)
- 📊 **Tableau de bord** et analyses des crises
- 🚨 **Suivi d'épilepsie** : chronomètre, qualification, historique, export CSV, HealthKit
- 💊 **Médicaments** : plan, prises, journal, historique de révisions, base BDPM embarquée
- 🙂 **Humeur, observations quotidiennes, symptômes**
- 📄 **Rapports** : rapport médical PDF, carnet de suivi (génération, scan/import par QR)
- ☁️ **Synchronisation CloudKit** entre parents, corbeille, sauvegardes combinées (voir `docs/CLOUDKIT_SYNC.md`)
- 📰 **Actualités AFSR** (API Statamic) et 🔐 **espace adhérent** (voir `docs/MEMBER_AREA.md`)
- 💜 **Dons** (voir `disabled-features/donation-applepay/README.md` pour Apple Pay)
- ⚙️ **Réglages** : partage, diagnostic, import historique, corbeille

## Stack

SwiftUI (iOS 17+), `@Observable`, SwiftData, CloudKit, HealthKit, WebKit. Aucune dépendance tierce.

## Structure

```
RettApp/
├── Core/        # AFSRLinks, Backup, HealthKit, Profile, Sync, Trash, Update
├── Features/    # BookletImport, Dashboard, Discovery, Donation, HealthData,
│                # MedicationTracker, MemberArea, MoodTracker, News, Reports,
│                # SeizureTracker, Settings, SymptomTracker
├── Shared/      # Composants (AFSR*), thème, utilitaires
└── Resources/   # Info.plist, entitlements, assets, Localizable.strings, bdpm.sqlite
RettAppTests/    # Tests unitaires
docs/            # Documentation (sync, espace adhérent, fiche App Store, TODO site)
scripts/         # Génération du projet Xcode et de la base BDPM
```

## Ouvrir le projet Xcode

```bash
open RettApp.xcodeproj
```

Après ajout, renommage ou suppression de fichiers sources, régénérer le projet :

```bash
ruby scripts/generate_xcodeproj.rb   # gem xcodeproj
```

C'est le **seul** générateur. `project.yml` (XcodeGen) a été supprimé en
novembre 2026 : il annonçait `MARKETING_VERSION 1.3.0` alors que le script
annonçait `1.9.1`, et ce README présentait les deux comme équivalents — lancer
`xcodegen generate` aurait publié une version inférieure à celle de l'App
Store.

La version et le numéro de build vivent dans ce script, et nulle part ailleurs :
une valeur corrigée dans Xcode est perdue à la régénération suivante.

Puis, dans Xcode : target **RettApp** → **Signing & Capabilities** → choisir son **Team** (iCloud/CloudKit, HealthKit, Push Notifications).

## Tests

```bash
xcodebuild test -scheme RettApp -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Notes

- **HealthKit** n'expose pas d'API pour les médicaments : les prises restent dans SwiftData. Seules les crises sont écrites dans HealthKit.
- **Confidentialité** : voir `SECURITY.md`.

## Licence

Copyright © AFSR. Voir `LICENSE`.
