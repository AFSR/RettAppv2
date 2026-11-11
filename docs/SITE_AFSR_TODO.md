# Modifications à faire sur le site AFSR (afsr.fr)

Ce document liste **toutes les actions** à mener côté site web et back-office Statamic
pour que l'app **RettApp** soit pleinement opérationnelle, conforme RGPD, et publiable
sur l'App Store.

> Périmètre : afsr.fr (Statamic), App Store Connect (côté Apple), portail Apple Developer.
> Hors périmètre : code de l'app iOS (déjà géré dans ce dépôt).

---

## Sommaire

1. API Statamic — module Actualités
2. Pages dédiées à l'application (dossier `/rettapp/`)
3. Page de présentation de l'app
4. Portail Apple Developer + App Store Connect
5. RGPD — registre, DPIA, consentement
6. Checklist avant publication

---

## 1. API Statamic — module Actualités

Le module Actualités est **actif** dans l'app (`FeatureFlags.newsEnabled = true`). Tant que
l'API n'est pas en ligne, l'onglet affiche un état vide : ces étapes sont à faire **avant** de
publier la build.

### 1.1 Activer la Content API

Fichier `config/statamic/api.php` (à créer si absent via `php please vendor:publish --tag=statamic-config`) :

```php
<?php
return [
    'enabled' => env('STATAMIC_API_ENABLED', false),
    'route'   => 'api',
    'cache'   => ['expiry' => 30],

    'resources' => [
        'collections' => true,
        'navs'        => false,
        'taxonomies'  => false,
        'assets'      => false,
        'globals'     => false,
        'forms'       => false,
        'users'       => false,
    ],

    'endpoints' => [
        'collections' => [
            'news' => true,   // handle de la collection à exposer (APIConfig.newsCollection)
        ],
    ],
];
```

Dans `.env` de production :
```
STATAMIC_API_ENABLED=true
```

Vide le cache après modification :
```bash
php artisan cache:clear
php please stache:clear
```

### 1.2 Vérifier le handle de la collection

Dans le CP : **Collections** → URL = `/cp/collections/news/...`. L'app attend le handle `news`. Si le
handle est différent (ex. `actualites`, `posts`, `articles`), adapter `endpoints.collections`
ci-dessus **et** prévenir pour qu'on ajuste `APIConfig.newsCollection` dans l'app.

### 1.3 Blueprint des entries

L'app attend ces handles de champs dans chaque entrée Actualité :

| Handle attendu | Type Statamic | Optionnel ? |
|---|---|---|
| `id` | (auto) | non |
| `title` | text | non |
| `slug` | (auto) | non |
| `date` | date (ISO ou `YYYY-MM-DD`) | recommandé |
| `content` | bard / markdown / replicator → rendu HTML | non (sinon entrée vide) |
| `excerpt` | text (court) | recommandé |
| `featured_image` | assets (image unique) OU URL | optionnel |

Si tes handles sont différents (ex. `body` au lieu de `content`), dis-le pour qu'on adapte
le parser dans `NewsArticle.swift`. Sinon, renomme-les côté blueprint.

### 1.4 Tester depuis le navigateur

```
https://afsr.fr/api/collections/news/entries?sort=-date&limit=20
```

Réponses attendues :
- `200` + JSON `{ "data": [...] }` → tout roule
- `404` → API non activée OU handle de collection incorrect
- `403` → la collection n'est pas listée dans `endpoints.collections`
- `500` → regarde les logs Laravel

### 1.5 Authentification (optionnelle)

Si on veut **restreindre** l'API à RettApp uniquement (et non publique) :

```bash
php please make:token Statamic\\Tokens\\Handlers\\ApiToken
```

→ implémenter le check du `bearer token` dans `app/Tokens/ApiToken.php`, mettre le secret
dans `.env` (`AFSR_API_TOKEN=...`) et le communiquer pour qu'on configure
`APIConfig.apiKey` dans l'app.

> Recommandation : laisser l'API **publique** pour les actualités (elles le sont déjà sur
> le site). Pas de plus-value à les restreindre, et ça évite de gérer un secret embarqué
> dans le binaire iOS (mauvaise pratique sécurité — voir `SECURITY.md` §4).

### 1.6 CORS

Pas critique pour iOS (pas de Same-Origin Policy en natif), mais utile si une future
app web consomme l'API. Statamic fournit ça via le middleware Laravel standard.

### 1.7 Champ image_alt (accessibilité — recommandé)

Si possible, ajouter un champ `featured_image_alt` (text) dans le blueprint pour décrire
l'image. RettApp pourrait l'utiliser pour VoiceOver à l'avenir.

---

## 2. Pages dédiées à l'application (dossier `/rettapp/`)

L'app a ses propres pages, distinctes du reste du site, regroupées sous un dossier
dédié `https://afsr.fr/rettapp/` (modèle de contrôleur et vues : dépôt AFSR/website).

| URL cible | Rôle | Statut |
|---|---|---|
| `/rettapp` | Présentation + **Support URL** App Store Connect (voir §3) | à créer |
| `/rettapp/confidentialite`, `/rettapp/privacy-policy`, `/rettapp/politica-de-privacidade` | Politique de confidentialité **de l'app** : données de santé, CloudKit, HealthKit, espace adhérent (Face ID, jeton) | à déplacer (aujourd'hui `/politique-de-confidentialite` etc. à la racine) |
| `/rettapp/mentions-legales`, `/rettapp/legal-notice`, `/rettapp/avisos-legais` | Mentions légales | à déplacer |
| `/rettapp/faq` | Questions fréquentes (synchro, export, suppression des données) | à créer |

À faire quand le dossier est en ligne :
1. Mettre des **redirections 301** depuis les adresses actuelles (`/politique-de-confidentialite`,
   `/privacy-policy`, `/politica-de-privacidade`, `/mentions-legales`, `/legal-notice`,
   `/avisos-legais`, `/confidentialite`) : elles sont déjà publiées dans la fiche App Store
   et dans les versions de l'app déjà distribuées.
2. Mettre à jour `RettApp/Core/AFSRLinks.swift`, `docs/APP_STORE_LISTING.md` et App Store Connect
   (Privacy Policy URL, Support URL, Marketing URL).
3. Le texte de la politique doit refléter l'état réel de l'app (**voir `SECURITY.md`**) :
   stockage local SwiftData **et** synchronisation CloudKit entre parents, HealthKit, espace
   adhérent (jeton 90 j / 365 j max, empreinte seule côté serveur, Face ID), pas de Sign in
   with Apple, mineurs et consentement parental (art. 8 et 9.2.a RGPD), avertissement médical
   (voir la fiche App Store), droits RGPD et CNIL.
4. Renseigner `AFSR_LEGAL_RNA`, `AFSR_LEGAL_SIREN`, `AFSR_LEGAL_PUBLICATION_DIRECTOR` en production
   (obligation pénalement sanctionnée ; sinon les lignes ne s'affichent pas).
5. Faire valider le texte par le **DPO** et, idéalement, un avocat santé numérique (1-2 h).

---

## 3. Page de présentation de l'app

URL : `https://afsr.fr/rettapp` (page d'accueil du dossier §2)

Contenu :
- Capture d'écran (icône + 3-5 screenshots — à fournir au moment de la soumission App Store)
- Texte de présentation court (~150 mots) : à qui s'adresse l'app, ce qu'elle fait, ce
  qu'elle ne fait pas (rappel non-MD)
- Bouton **App Store** (avec le badge officiel Apple)
- Lien vers la politique de confidentialité et mentions légales
- Section FAQ (5-10 questions)
- Bloc « Une question ? » avec contact AFSR

Cette page sert :
- De **support URL** dans App Store Connect (champ obligatoire)
- De vitrine pour les familles qui découvrent l'app via l'AFSR

---

## 4. Portail Apple Developer + App Store Connect

Hors site web, mais à coordonner depuis le compte Apple Developer de l'AFSR.

### 4.1 Compte Apple Developer

- Compte payant (99 $/an pour individuel ou organisation)
- L'AFSR doit ouvrir un **compte Organisation** (D-U-N-S Number requis, 1-2 semaines
  d'attente pour l'enregistrement)

### 4.2 Bundle ID

- `fr.afsr.RettApp` à enregistrer sur https://developer.apple.com/account/resources/identifiers/list
- Capabilities à activer sur le Bundle ID :
  - HealthKit
  - Push Notifications
  - iCloud (CloudKit) → synchronisation entre parents
- Container CloudKit : `iCloud.fr.afsr.RettApp` (à créer dans CloudKit Dashboard)

### 4.3 App Store Connect — fiche app

Page à créer : https://appstoreconnect.apple.com → My Apps → +

Champs à remplir :
- Nom : **RettApp**
- Sous-titre : *outil de suivi pour familles concernées par le syndrome de Rett*
- Catégorie principale : **Medical**
- Catégorie secondaire : Health & Fitness
- Age rating : à préciser (probablement 4+)
- **Privacy Policy URL** : `https://afsr.fr/politique-de-confidentialite`
  (cf. §2 pour les adresses finales et les versions EN/PT)
- **Support URL** : `https://afsr.fr/rettapp`
- **Marketing URL** (optionnel) : `https://afsr.fr/rettapp`
- Description (4 000 car. max) — voir §3
- Mots-clés (100 car.) : « épilepsie, syndrome de rett, médicaments, suivi, santé »
- Screenshots (iPhone 6.7", 6.5", iPad 12.9", 11") — à produire

### 4.4 Privacy Manifest (déjà côté code à créer)

**Toujours absent** de `RettApp/Resources/` : à créer côté code (voir `SECURITY.md` §7)
et à inclure dans la build avant soumission.

### 4.5 Déclaratif "Regulated medical device"

→ Sélectionner **No** (justifié par l'absence de certification CE/FDA/UKCA, voir
`SECURITY.md` §10).

---

## 5. RGPD — registre, DPIA, consentement

### 5.1 Registre des traitements (art. 30)

Ajouter une **fiche RettApp** au registre de l'AFSR : suivi quotidien par parents et aidants ;
personnes concernées : enfants (mineurs) et leurs parents/aidants ; données : identité,
santé (crises, médicaments, humeur, symptômes), identifiants CloudKit/adhérent ; sous-traitant :
Apple (CloudKit, HealthKit, iCloud — DPA Apple, DPF) ; conservation : contrôlée par
l'utilisateur ; sécurité : `SECURITY.md`.

### 5.2 DPIA (analyse d'impact)

**Obligatoire** (données de santé de mineurs). À conduire par le DPO avec le développeur avant la
mise en ligne. Modèle : <https://www.cnil.fr/fr/RGPD-analyse-impact-protection-des-donnees-aipd>

### 5.3 Consentement parental

Géré dans l'app (onboarding). Le DPO valide le wording de l'avertissement médical et du consentement.

---

## 6. Checklist avant publication

- [ ] API Statamic activée et testée (`/api/collections/news/entries` répond `200`)
- [ ] Dossier `/rettapp/` en ligne (présentation, confidentialité, mentions, FAQ) + redirections des anciennes URL
- [ ] `AFSRLinks.swift`, fiche App Store et App Store Connect alignés sur les nouvelles URL
- [ ] `AFSR_LEGAL_RNA`, `AFSR_LEGAL_SIREN`, `AFSR_LEGAL_PUBLICATION_DIRECTOR` renseignés en production
- [ ] Compte **Apple Developer Organisation** ouvert et validé (D-U-N-S)
- [ ] Bundle ID `fr.afsr.RettApp` enregistré, capabilities activées
- [ ] Container CloudKit `iCloud.fr.afsr.RettApp` créé
- [ ] Fiche App Store Connect créée et remplie
- [ ] **Screenshots** produits (iPhone + iPad)
- [ ] **Icône** 1024×1024 finalisée
- [ ] Privacy Manifest (`PrivacyInfo.xcprivacy`) créé et ajouté à la build
- [ ] Déclaratif "Regulated medical device" → **No** validé
- [ ] Registre des traitements et **DPIA** par le DPO
- [ ] Textes validés par avocat santé numérique
- [ ] **Build TestFlight** validée par des familles pilotes
- [ ] Soumission App Store

---

*Document vivant : retirer les tâches au fur et à mesure qu'elles sont faites. Déjà fait : pages légales
servies par le dépôt du site (`LegalController`).*
