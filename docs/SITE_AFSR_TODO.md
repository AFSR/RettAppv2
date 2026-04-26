# Modifications à faire sur le site AFSR (afsr.fr)

Ce document liste **toutes les actions** à mener côté site web et back-office Statamic
pour que l'app **RettApp** soit pleinement opérationnelle, conforme RGPD, et publiable
sur l'App Store.

> Périmètre : afsr.fr (Statamic), App Store Connect (côté Apple), portail Apple Developer.
> Hors périmètre : code de l'app iOS (déjà géré dans ce dépôt).

---

## Sommaire

1. [API Statamic — module Actualités](#1-api-statamic--module-actualités)
2. [Pages légales obligatoires](#2-pages-légales-obligatoires)
3. [Politique de confidentialité — contenu détaillé](#3-politique-de-confidentialité--contenu-détaillé)
4. [Mentions légales — contenu détaillé](#4-mentions-légales--contenu-détaillé)
5. [Page de présentation de l'app](#5-page-de-présentation-de-lapp)
6. [Portail Apple Developer + App Store Connect](#6-portail-apple-developer--app-store-connect)
7. [RGPD — registre, consentements, DPO](#7-rgpd--registre-consentements-dpo)
8. [Checklist finale avant publication](#8-checklist-finale-avant-publication)

---

## 1. API Statamic — module Actualités

Le module Actualités de l'app est **désactivé** par feature flag tant que l'API n'est pas
opérationnelle. Une fois ces étapes faites côté site, on rebascule
`FeatureFlags.newsEnabled = true` côté code et on push une nouvelle version.

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
            'actualites' => true,   // handle de la collection à exposer
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

Dans le CP : **Collections → Actualites** → URL = `/cp/collections/actualites/...`. Si le
handle n'est pas `actualites` (ex. `news`, `posts`, `articles`), adapter `endpoints.collections`
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
https://afsr.fr/api/collections/actualites/entries?sort=-date&limit=20
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

## 2. Pages légales obligatoires

Apple **refusera** la soumission App Store si ces deux pages n'existent pas. RGPD les
exige aussi.

| URL à publier | Liée depuis | Statut |
|---|---|---|
| `https://afsr.fr/confidentialite` | App (Réglages → À propos), App Store Connect | ❌ à créer |
| `https://afsr.fr/mentions-legales` | App (Réglages → À propos) | ❌ à créer |

Les deux doivent être :
- Accessibles publiquement (pas derrière login)
- Référencées par leur URL exacte (les URLs sont déjà hardcodées dans `SettingsView.swift`)
- En français (la cible primaire est francophone)

---

## 3. Politique de confidentialité — contenu détaillé

### Structure recommandée

```
1. Identité du responsable de traitement
   → Association Française du Syndrome de Rett, [adresse], [SIRET]
   → DPO : [nom, email]

2. Données collectées
   - Identité enfant : prénom, date de naissance optionnelle
   - Données de santé : crises d'épilepsie (date, durée, type, déclencheur, notes),
     médicaments (nom, dose, horaires, prises), flag épilepsie
   - Identifiant Apple (Apple User ID opaque, via Sign in with Apple)
   - Aucune donnée de localisation, ni biométrie, ni contacts, ni photos

3. Finalités
   → Suivi quotidien par les parents et aidants, communication avec professionnels
     de santé (export CSV)

4. Base légale (RGPD art. 6 + 9)
   → Consentement explicite du titulaire de l'autorité parentale (art. 9.2.a)

5. Stockage
   → Local uniquement sur l'appareil iOS de l'utilisateur (SwiftData chiffré au repos
     par iOS Data Protection)
   → Aucune transmission vers un serveur AFSR ou tiers
   → Les sauvegardes iCloud peuvent contenir une copie chiffrée par Apple

6. Durée de conservation
   → L'utilisateur contrôle entièrement la durée de conservation
   → Bouton "Effacer toutes les données" disponible dans les Réglages
   → Aucune purge automatique

7. Destinataires
   → Aucun, sauf si l'utilisateur exporte volontairement (CSV) vers un tiers de son choix
     (e.g. son neurologue par email)

8. Transferts hors UE
   → Apple Inc. (États-Unis) pour Sign in with Apple et iCloud, sous accord DPF
     (Data Privacy Framework)

9. Droits RGPD
   - Accès : visible dans l'app
   - Rectification : édition libre
   - Effacement : "Effacer toutes les données" (Réglages)
   - Portabilité : export CSV complet (Réglages)
   - Opposition / limitation : désinstaller l'app
   - Réclamation auprès de la CNIL : https://www.cnil.fr/fr/plaintes

10. Cookies / traceurs
    → Aucun cookie, aucun traceur, aucun analytics tiers

11. Mineurs
    → L'app est destinée à des données concernant des mineurs.
    → L'usage requiert le consentement du titulaire de l'autorité parentale (art. 8 RGPD).

12. AVERTISSEMENT MÉDICAL — copie EXACTE :
    > « RettApp est un outil de suivi destiné aux parents et aidants. Elle ne constitue
    > pas un dispositif médical au sens du règlement européen 2017/745 (MDR). Elle ne
    > diagnostique pas, ne traite pas, et ne remplace en aucun cas l'avis d'un
    > professionnel de santé. En cas d'urgence, appelez le 15 (Samu) ou le 112. »

13. Modifications de la politique
    → Comment l'utilisateur sera informé d'une mise à jour

14. Contact
    → Email du DPO + adresse postale AFSR
```

### Modèle de référence

La CNIL fournit un modèle adaptable : <https://www.cnil.fr/fr/exemple-de-mentions-pour-un-formulaire-de-collecte-de-donnees>

### À faire valider

Le texte final **doit** être validé par :
- Le **DPO** de l'AFSR
- Idéalement un avocat spécialisé santé numérique (1-2 h de conseil)

---

## 4. Mentions légales — contenu détaillé

```
1. Éditeur du site et de l'app
   → Association Française du Syndrome de Rett
   → Statut juridique : association loi 1901
   → Adresse du siège social
   → SIRET, RNA
   → Représentant légal (Président)
   → Téléphone, email de contact

2. Directeur de la publication
   → Nom + qualité

3. Hébergeur du site web
   → Nom, adresse, téléphone de l'hébergeur de afsr.fr

4. Crédits
   → Mention de l'app iOS (RettApp)
   → Crédits éventuels (designer, développeur)

5. Propriété intellectuelle
   → Logo AFSR, nom RettApp, contenus → propriété AFSR

6. Liens hypertexte
   → Politique de l'AFSR sur les liens entrants/sortants
```

---

## 5. Page de présentation de l'app

URL suggérée : `https://afsr.fr/rettapp`

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

## 6. Portail Apple Developer + App Store Connect

Hors site web, mais à coordonner depuis le compte Apple Developer de l'AFSR.

### 6.1 Compte Apple Developer

- Compte payant (99 $/an pour individuel ou organisation)
- L'AFSR doit ouvrir un **compte Organisation** (D-U-N-S Number requis, 1-2 semaines
  d'attente pour l'enregistrement)

### 6.2 Bundle ID

- `fr.afsr.RettApp` à enregistrer sur https://developer.apple.com/account/resources/identifiers/list
- Capabilities à activer sur le Bundle ID :
  - Sign in with Apple
  - HealthKit
  - Push Notifications
  - iCloud (CloudKit) → pour la future synchronisation entre parents
- Container CloudKit : `iCloud.fr.afsr.RettApp` (à créer dans CloudKit Dashboard)

### 6.3 App Store Connect — fiche app

Page à créer : https://appstoreconnect.apple.com → My Apps → +

Champs à remplir :
- Nom : **RettApp**
- Sous-titre : *outil de suivi pour familles concernées par le syndrome de Rett*
- Catégorie principale : **Medical**
- Catégorie secondaire : Health & Fitness
- Age rating : à préciser (probablement 4+)
- **Privacy Policy URL** : `https://afsr.fr/confidentialite`
- **Support URL** : `https://afsr.fr/rettapp`
- **Marketing URL** (optionnel) : `https://afsr.fr/rettapp`
- Description (4 000 car. max) — voir §5
- Mots-clés (100 car.) : « épilepsie, syndrome de rett, médicaments, suivi, santé »
- Screenshots (iPhone 6.7", 6.5", iPad 12.9", 11") — à produire

### 6.4 Privacy Manifest (déjà côté code à créer)

`PrivacyInfo.xcprivacy` dans `RettApp/Resources/` — voir `SECURITY.md` §7. Pas
d'action côté site web, mais à inclure dans la build avant soumission.

### 6.5 Déclaratif "Regulated medical device"

→ Sélectionner **No** (justifié par l'absence de certification CE/FDA/UKCA, voir
`SECURITY.md` §10).

---

## 7. RGPD — registre, consentements, DPO

### 7.1 Registre des traitements (art. 30)

L'AFSR doit ajouter dans son registre des traitements une **fiche RettApp** :

```
- Nom du traitement     : RettApp — suivi familial du syndrome de Rett
- Finalité              : suivi quotidien par parents et aidants
- Catégories de personnes : enfants atteints du syndrome de Rett
                            (mineurs) + leurs parents/aidants
- Catégories de données : identité (prénom, date de naissance), santé (épilepsie,
                          médicaments, crises), identifiant Apple
- Destinataires         : aucun (stockage local uniquement)
- Sous-traitants        : Apple Inc. (Sign in with Apple, iCloud) — DPA Apple
- Transferts hors UE    : USA via DPF (Apple)
- Durée de conservation : contrôlée par l'utilisateur (pas de purge automatique)
- Mesures de sécurité   : voir SECURITY.md
```

### 7.2 DPIA (Analyse d'impact)

**Obligatoire** dès lors qu'on traite des données de santé de mineurs (CNIL liste les
traitements DPIA obligatoires). À conduire par le DPO de l'AFSR avec le développeur
avant la mise en ligne publique.

Modèle CNIL : <https://www.cnil.fr/fr/RGPD-analyse-impact-protection-des-donnees-aipd>

### 7.3 Consentement parental

Géré côté app (onboarding). Le DPO doit valider le wording de l'écran d'avertissement
médical et le toggle de consentement.

---

## 8. Checklist finale avant publication

À cocher avant soumission App Store :

- [ ] API Statamic activée et testée (`/api/collections/actualites/entries` répond `200`)
- [ ] Page **politique de confidentialité** publiée à `https://afsr.fr/confidentialite`
- [ ] Page **mentions légales** publiée à `https://afsr.fr/mentions-legales`
- [ ] Page **présentation app** publiée à `https://afsr.fr/rettapp`
- [ ] Compte **Apple Developer Organisation** ouvert et validé (D-U-N-S)
- [ ] Bundle ID `fr.afsr.RettApp` enregistré, capabilities activées
- [ ] Container CloudKit `iCloud.fr.afsr.RettApp` créé
- [ ] Fiche App Store Connect créée et remplie
- [ ] **Screenshots** produits (iPhone + iPad, 5-10 par taille)
- [ ] **Icône** 1024×1024 finalisée
- [ ] Privacy Manifest (`PrivacyInfo.xcprivacy`) ajouté dans la build
- [ ] Déclaratif "Regulated medical device" → **No** validé
- [ ] **Fiche RGPD registre des traitements** rédigée par le DPO
- [ ] **DPIA** conduite et signée
- [ ] Texte des **mentions médicales** validé par avocat santé numérique (1-2 h)
- [ ] **Build TestFlight** validée par les premiers testeurs (familles AFSR pilotes)
- [ ] Soumission App Store

---

*Ce document est vivant. Mettre à jour au fur et à mesure que les actions sont réalisées.*
