# Don Apple Pay — code à reprendre, architecture décidée

Ces fichiers sont **hors du target** RettApp pour respecter la Guideline 2.1
d'Apple : « PassKit framework included but no Apple Pay integration ». Tant
que l'identifiant marchand `merchant.fr.afsr.RettApp` n'est pas validé chez
Apple, relier PassKit au binaire est un motif de refus.

## Ce qui a changé, et pourquoi ce code ne peut pas être réintégré tel quel

Ce code visait un point d'entrée Vercel (`backend/`, supprimé) qui créait un
paiement Stripe **et rien d'autre**. C'était une erreur d'architecture : un
don ainsi encaissé n'existait nulle part pour l'association — pas de
`Commande__c`, pas d'attribution à un contact, pas de reçu fiscal. L'AFSR
aurait reçu des virements orphelins à réconcilier à la main.

**Salesforce est la base de référence.** Un don ou une adhésion qui n'y
arrive pas n'existe pas. L'architecture retenue :

1. L'app présente la feuille Apple Pay et obtient un jeton de paiement.
2. Elle envoie ce jeton et les informations du donateur à **afsr.fr**.
3. afsr.fr débite via Stripe — la clé secrète y vit, jamais dans l'app — puis
   crée la `Commande__c` et sa `ProduitCommande__c` dans Salesforce.
4. L'app affiche la confirmation. Elle ne conserve rien.

L'app ne parle donc **jamais** directement à Stripe pour débiter, ni à
Salesforce. Elle n'embarque aucun secret : un binaire de l'App Store
s'inspecte en quelques minutes.

## À reprendre dans ces fichiers

- `ApplePayButtonView.swift` : la présentation reste valable.
- `ApplePayDonationCoordinator.swift` : **à réécrire**. Il parlait au point
  d'entrée Vercel et à Stripe en direct ; il doit désormais poster vers
  afsr.fr et ne plus rien savoir de Stripe.
- `StripeBootstrap.swift` : **probablement à supprimer**. Si la tokenisation
  se fait avec la clé publiable, elle ne demande pas le SDK complet.

## Réintégration

1. Obtenir l'identifiant marchand chez Apple et l'associer au compte Stripe
   de l'AFSR.
2. Réajouter dans `RettApp.entitlements` :
   ```xml
   <key>com.apple.developer.in-app-payments</key>
   <array>
       <string>merchant.fr.afsr.RettApp</string>
   </array>
   ```
3. Déplacer les fichiers retenus vers `RettApp/Features/Donation/`.
4. Passer `DonationService.isApplePayEnabled` à `true`.
5. Régénérer le projet (`ruby scripts/generate_xcodeproj.rb`) et tester.

L'historique git contient l'intégration Vercel d'origine au commit `410d618`,
pour mémoire — elle ne doit pas servir de modèle.
