# RettApp — Application iOS AFSR

Application iOS native (SwiftUI) développée pour l'**Association Française du Syndrome de Rett** afin d'accompagner les parents et aidants dans le suivi quotidien d'enfants atteints du syndrome de Rett.

## Fonctionnalités

- 🔐 **Authentification** : Sign in with Apple + session Keychain
- 👤 **Profil enfant** : prénom, date de naissance, toggle épilepsie, liste médicaments
- 📰 **Actualités AFSR** : lecture des articles depuis l'API Statamic (pull-to-refresh, cache offline)
- 🚨 **Suivi d'épilepsie** : chronomètre d'urgence (gros boutons), qualification type/déclencheur, historique, export CSV, intégration `HKCategoryType(.seizure)`
- 💊 **Plan médicamenteux** : CRUD médicaments, vue journalière par moment (matin/midi/soir), notifications locales, marquage des prises
- 👁️ **Jeu du regard "tarte à la crème"** : ARKit `ARFaceTrackingConfiguration`, logique de dwell, animations, mode mock simulateur
- ⚙️ **Réglages** : gestion permissions, export CSV complet, effacement, déconnexion

## Stack

- SwiftUI (iOS 17+)
- `@Observable` (Swift 5.9 macro)
- SwiftData (persistance locale)
- HealthKit, ARKit, AuthenticationServices, UserNotifications, WebKit
- Aucune dépendance tierce

## Structure

```
AFSR/
├── AFSRApp.swift                # Entry point @main
├── ContentView.swift            # TabView racine
├── Core/
│   ├── Auth/                    # AuthManager + SignInView
│   ├── Profile/                 # ChildProfile + ProfileSetupView
│   └── HealthKit/               # HealthKitManager
├── Features/
│   ├── News/                    # Actualités AFSR
│   ├── SeizureTracker/          # Suivi crises
│   ├── MedicationTracker/       # Plan & prises
│   ├── EyeGame/                 # Jeu ARKit
│   └── Settings/                # Réglages
├── Shared/
│   ├── Components/              # Boutons, cartes, état vide
│   └── Theme/                   # AFSRTheme (couleurs, typo, tokens)
└── Resources/
    ├── Info.plist
    ├── AFSR.entitlements
    ├── Assets.xcassets
    └── Localizable.strings
AFSRTests/                       # Tests unitaires
```

## Générer le projet Xcode

Le dépôt ne contient pas de `.xcodeproj` — le projet est décrit dans `project.yml` (XcodeGen).

### Avec XcodeGen (recommandé)

```bash
brew install xcodegen
xcodegen generate
open AFSR.xcodeproj
```

### Sans XcodeGen

1. Dans Xcode : **File → New → Project → iOS → App**
2. Product name : `RettApp`, Bundle ID : `fr.afsr.RettApp`, Interface : SwiftUI, Language : Swift
3. Glisser le dossier `AFSR/` dans le navigator (ne pas cocher "Copy items")
4. Dans **Signing & Capabilities**, ajouter :
   - Sign in with Apple
   - HealthKit (avec Clinical Health Records désactivé)
   - Push Notifications
   - Background Modes → Background fetch
5. Remplacer l'`Info.plist` par celui de `AFSR/Resources/Info.plist`
6. Associer `AFSR/Resources/AFSR.entitlements` au target

## Configuration API

Éditer `AFSR/Features/News/Models/NewsArticle.swift` :

```swift
enum APIConfig {
    static var baseURL = URL(string: "https://www.afsr.fr/api")!
    static var apiKey: String = "" // bearer token si endpoint protégé
}
```

## Exécution

- **Simulateur** : le jeu eye-tracking utilise automatiquement un mock (positions aléatoires autour de la cible) — la caméra TrueDepth n'existe pas sur simulateur
- **Device physique** : nécessite un iPhone X+ ou iPad Pro (Face ID) pour le jeu eye-tracking. Les autres modules fonctionnent sur tout iPhone/iPad iOS 17+

## Tests

```bash
xcodegen generate
xcodebuild test -scheme AFSR -destination 'platform=iOS Simulator,name=iPhone 15'
```

Tests inclus :
- `SeizureViewModelTests` : calcul durée, transitions d'état, timer
- `GazeProcessorTests` : logique de dwell, hit-test, classification horaire

## Notes importantes

- **HealthKit** : Apple Santé n'expose pas d'API tierce pour les médicaments. Les prises restent locales (SwiftData) et sont exportables en CSV. Seules les crises sont écrites dans HealthKit (`HKCategoryType(.seizure)`, iOS 17+).
- **Multi-profils** : HealthKit n'est pas conçu pour gérer plusieurs personnes. Le prénom de l'enfant est stocké en métadonnée (`AFSRChildFirstName`).
- **Confidentialité** : aucune donnée de santé n'est envoyée à un serveur tiers. Tout reste sur l'appareil + Apple Santé.

## Roadmap

- [ ] Widget WidgetKit "Démarrer une crise" depuis l'écran d'accueil
- [ ] Sons et assets graphiques personnalisés (splash, confettis)
- [ ] Export PDF médical formaté
- [ ] Sync iCloud optionnelle (CloudKit + SwiftData)
- [ ] Accessibilité : test complet VoiceOver, Dynamic Type jusqu'à XXXL

## Licence

Copyright © AFSR. Voir `LICENSE`.
