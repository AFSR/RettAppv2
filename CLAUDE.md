# RettApp — application iOS de l'AFSR

Application de suivi pour les familles touchées par le syndrome de Rett, éditée
par l'Association Française du Syndrome de Rett. Publiée sur l'App Store.

## Les trois règles non négociables

Elles ont été posées explicitement par l'association. Une modification qui les
enfreint est à refuser, pas à livrer.

1. **Les données de suivi médical ne quittent jamais l'appareil** ni l'iCloud
   personnel de la famille. Crises, prises de médicaments, symptômes, Apple
   Santé : aucun serveur de l'AFSR ne les reçoit. C'est l'affirmation portante
   de la politique de confidentialité et de la fiche App Store.
2. **Salesforce est la base de référence** pour tout ce qui touche à
   l'association — dons, adhésions, reçus fiscaux. L'app remonte les actions
   vers afsr.fr, qui écrit dans Salesforce, et va y relire ce qu'elle affiche.
   Elle ne conserve ni ne calcule rien de ce domaine.
3. **L'app ne détient aucun secret.** Ni clé Stripe, ni identifiants
   Salesforce. Le jeton d'API est extractible du binaire : ce qui protège est
   côté serveur.

Le détail et les raisons : `docs/ARCHITECTURE.md`.

## Ce qui est impossible dans cette session

**Il n'y a pas de macOS.** Ni `xcodebuild`, ni `swift`, ni simulateur.
L'application ne peut être **ni compilée ni testée** ici. N'annoncez jamais
qu'un code Swift fonctionne : dites qu'il n'a pas été compilé.

Ce qui fonctionne : lire, écrire, régénérer le projet, raisonner sur le code.

## Commandes

```bash
# Régénérer le projet Xcode. OBLIGATOIRE après tout ajout, renommage ou
# suppression de fichier source : le .xcodeproj est généré, pas écrit à la main.
ruby scripts/generate_xcodeproj.rb

# Tests — sur une machine macOS uniquement, jamais ici.
xcodebuild test -scheme RettApp -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Le second dépôt

L'app parle à **`AFSR/website`** (Laravel + Statamic), qui sert l'API de
l'espace adhérent, l'annuaire des lieux, les actualités et les pages légales.
Il n'est pas attaché par défaut. Pour l'obtenir :

```
add_repo(owner: "AFSR", repo: "website")   # puis cloner comme l'outil l'indique
```

Toute modification du contrat entre les deux touche les deux dépôts. Les règles
propres au site sont dans son propre `CLAUDE.md`.

## Avant d'écrire : `git fetch`

Plusieurs sessions Claude travaillent sur ces dépôts **en même temps**. J'ai
écrit une API entière en double pour avoir lu un `main` local périmé.

```bash
git fetch origin main && git log --oneline origin/main -5
```

Faites-le **avant de commencer**, pas avant de pousser.

## Branche et fusion

- Développement sur la branche désignée dans la consigne de session, jamais sur
  `main` directement.
- **Ne jamais ouvrir de pull request sans demande explicite.**
- Quand la fusion est demandée, suivez `.claude/skills/fusionner-sur-main` : le
  `project.pbxproj` entre en conflit à chaque fois, et la résolution n'est pas
  celle qu'on croit.
- Messages de commit **en français**, longs : le problème, puis la décision,
  puis ce qui a été écarté. Regardez `git log` pour le ton.

## Conventions de code

- Commentaires **en français**, et ils disent **pourquoi**, jamais quoi. Un
  commentaire qui paraphrase la ligne suivante est à supprimer.
- Ce qu'on ne sait pas, on ne l'écrit pas : pas de valeur devinée, pas de
  `[À COMPLÉTER]` livré. Une ligne absente vaut mieux qu'une ligne fausse.
- SwiftUI, SwiftData, CloudKit. iOS 17 minimum, Swift 5.9.
- **Ne jamais réimporter les données de démonstration** que l'utilisateur a
  supprimées.

## Règles par zone

Chargez la règle correspondante **avant** de toucher à ces chemins :

| Zone | Règle |
|---|---|
| `RettApp.xcodeproj/**`, `scripts/generate_xcodeproj.rb` | `.claude/rules/xcodeproj.md` |
| `RettApp/Core/Sync/**`, `RettApp/Core/Trash/**` | `.claude/rules/sync-cloudkit.md` |
| `RettApp/Features/MemberArea/**`, `RettApp/Features/Places/**` | `.claude/rules/espace-adherent.md` |
| `RettApp/Resources/Info.plist`, `PrivacyInfo.xcprivacy`, `Features/Donation/**` | `.claude/rules/promesses-confidentialite.md` |

## Pièges connus

- **Le `project.pbxproj` est régénéré avec de nouveaux identifiants à chaque
  exécution.** Deux branches qui ajoutent chacune un fichier produisent un
  conflit de bout en bout. Résolution : prendre la version de `main`, puis
  rejouer le générateur.
- **La version vit dans `scripts/generate_xcodeproj.rb`**, pas dans Xcode. Une
  version corrigée à la main est perdue à la prochaine régénération — et App
  Store Connect refuse un numéro inférieur au dernier publié.
- **La récupération du `ModelContainer` efface le magasin** en cas d'échec
  (`RettAppApp.swift`). Tout changement de schéma SwiftData risque les données
  locales de chaque famille. C'est pourquoi la corbeille est un fichier JSON et
  non un `@Model`.
- **Le schéma CloudKit doit être déployé de Development vers Production.** Un
  type d'enregistrement ajouté et non déployé casse le partage entre parents
  chez les vraies familles, sans rien casser en développement ni à la revue
  d'Apple.
- **`DonationService.isApplePayEnabled` est lu par personne.** Il ressemble à un
  interrupteur et n'en est pas un.
- L'environnement de session : `docs/ENVIRONNEMENT.md` (pare-feu d'afsr.fr qui
  refuse `curl`, allowlist réseau, pas de CI sur ce dépôt).

## État au 11 novembre 2026

- Publiée en **1.9**. Le générateur prépare **1.9.1 / build 12**.
- Tout le dossier `RettApp/Features/Places/**`, la corbeille et les pierres
  tombales **n'ont jamais été compilés**.
- Le don depuis l'app est **désactivé** en attendant les réponses de
  l'administrateur Salesforce. `DonationView` ouvre la page de don du site.
- Bloquants avant envoi : compiler ; déployer le type `Tombstone` en production
  CloudKit ; la déclaration de confidentialité d'App Store Connect.
