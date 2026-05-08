# Donation — Apple Pay (en attente)

Ces fichiers sont **temporairement hors du target** RettApp pour respecter la
Guideline 2.1 d'Apple : « PassKit framework included but no Apple Pay
integration ».

Tant que l'AFSR :
- n'a pas finalisé son compte Stripe et l'enregistrement nonprofit,
- n'a pas déployé le backend Vercel (cf. `backend/`),
- n'a pas validé son merchant ID `merchant.fr.afsr.RettApp` côté Apple
  Developer Portal et Stripe,

…le bouton Apple Pay reste désactivé. Tout le code lié est isolé ici pour que
PassKit ne soit pas linké dans le binaire publié sur l'App Store.

## Réintégration

Quand tout est branché côté AFSR :

1. Déplacer ces trois fichiers vers `RettApp/Features/Donation/`.
2. Réajouter dans `RettApp.entitlements` :
   ```xml
   <key>com.apple.developer.in-app-payments</key>
   <array>
       <string>merchant.fr.afsr.RettApp</string>
   </array>
   ```
3. Réajouter `import PassKit` dans `DonationService.swift` et restaurer la
   méthode `makeRequest(amount:)` ainsi que `availability()`.
4. Réajouter `StripeBootstrap.configure()` dans `RettAppDelegate
   .application(_:didFinishLaunchingWithOptions:)`.
5. Réajouter le SDK Stripe (Swift Package Manager) si on est en mode Stripe,
   ou simplement le mode local-only sinon.
6. Passer `DonationService.isApplePayEnabled` à `true`.
7. Régénérer le xcodeproj (`ruby scripts/generate_xcodeproj.rb`) et tester.

L'historique git contient l'intégration complète au commit `410d618`.
