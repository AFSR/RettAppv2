---
description: Espace adhérent natif et lieux Rett friendly. Le contrat avec l'API du site, et les pièges du client HTTP.
globs:
  - "RettApp/Features/MemberArea/**"
  - "RettApp/Features/Places/**"
---

# Espace adhérent et lieux Rett friendly

Ces écrans parlent à l'API `/api/membre` du dépôt **`AFSR/website`**. Le contrat
y est défini, pas ici : avant de deviner la forme d'une réponse, lisez
`app/Http/Controllers/Api/` et `routes/member-api.php` côté site.

## Ce n'est plus une vue web

L'espace adhérent a été une `WKWebView` sur afsr.fr jusqu'en novembre 2026. Il
est désormais **natif** : connexion par code à usage unique, jeton d'accès dans
le trousseau derrière Face ID, écrans SwiftUI. `AFSRWebView` a disparu.

Si vous lisez quelque part « vue web », « cookie de session » ou « se connecter
sur le site », c'est périmé — y compris dans la politique de confidentialité, où
cela a été faux le temps d'une fusion.

## Le client HTTP a deux pièges

`MemberAPIClient` a dû être étendu deux fois, pour des raisons qui ne se
devinent pas :

**Les paramètres de requête ne peuvent pas voyager dans le chemin.**
`URLComponents.path` échappe le `?` et les `&` : `/lieux?q=gite` partirait comme
un chemin nommé littéralement ainsi, et répondrait 404 sans indice. Utilisez :

```swift
try await session.client.get("/lieux", query: ["type": type, "q": recherche])
```

Les valeurs nulles ou vides sont écartées : un filtre absent ne doit pas devenir
`type=`, que le serveur lirait comme une chaîne vide.

**Un corps imbriqué ne passe pas par `[String: String]`.** Le dépôt d'un avis
porte `criteres`, un objet `handle → réponse`. Aplati en `criteres[handle]`,
Laravel ne le reconstruit pas : l'avis serait enregistré **sans aucune réponse
aux critères, et sans erreur**, ce qui est le pire des cas. Utilisez :

```swift
try await session.client.post("/avis", encoding: brouillon.payload())
```

Les clés du `payload` sont celles du formulaire du site, parce que c'est le même
`FormRequest` qui les valide. Les renommer casse le dépôt sans qu'aucun test de
l'app ne s'en aperçoive.

## Décodage

Le décodeur applique `convertFromSnakeCase` : `type_label` arrive en
`typeLabel`, `reviews_readable` en `reviewsReadable`. Les clés JSON restent en
snake_case côté serveur — n'y touchez pas.

## Ce qui est public et ce qui ne l'est pas

Le partage n'est **pas symétrique**, et l'app doit le respecter à la lettre :

- l'annuaire, les notes et les constats d'accessibilité sont publics — des
  renseignements sur un commerce, utiles bien au-delà des adhérents ;
- le **texte** des avis ne sort que pour un adhérent **à jour de cotisation**.
  Avoir un compte ne suffit pas. Le serveur le décide (`reviews_readable`) ;
  l'app affiche l'explication, elle ne recalcule pas la règle.

Ce qui précède décrit l'**API**. Dans l'**application**, l'annuaire reste
derrière la connexion : il vit dans l'espace adhérent et n'est pas atteignable
sans compte. Ce n'est pas un oubli, c'est une décision de l'association, prise
le 14 novembre 2026 sur question explicite. Ne l'ouvrez pas au public au motif
que le serveur, lui, le permettrait.

## Ne codez pas en dur les types et les critères

Ils viennent de `/lieux/meta`. Ajouter un critère côté site doit suffire à le
voir dans le formulaire, sans nouvelle version de l'app — et une app restée en
arrière ne doit pas envoyer de réponses à un critère retiré.

## Trois états, pas deux

Un constat se répond par **oui**, **non**, ou **rien**. « Je ne sais pas » n'est
pas une réponse mais son absence, et part comme telle : la clé n'est pas
envoyée. Une famille qui n'a pas demandé les toilettes adaptées ne doit pas
peser dans leur décompte. Le serveur écarte d'ailleurs tout ce qui n'est ni
`oui` ni `non`.

## Rien ne se publie sans relecture

Un avis déposé arrive **en attente**, un lieu proposé arrive **en brouillon**,
et une modification d'un avis déjà en ligne **repasse** en relecture. L'écran
« Mes avis » existe pour cette raison : sans lui, déposer un avis ressemble à le
perdre, et l'adhérent le redépose.

## Les gestes attendus

Ces écrans suivent Plans et Google Maps, délibérément : personne n'apprend à
noter un lieu. Étoiles qu'on balaie, pastilles qu'on touche, « Publier » dans la
barre de navigation, parcours qui **commence par une recherche** — demander « ce
lieu est-il déjà dans l'annuaire ? » avant toute recherche produit des doublons
que l'association fusionne à la main.

Un `Form` reste le bon outil pour les champs d'identité d'un lieu qu'on ajoute.
Il ne l'était pas pour l'avis lui-même.
