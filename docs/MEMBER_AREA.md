# Espace adhérent dans l'app

L'espace adhérent est **natif** : écrans SwiftUI (`RettApp/Features/MemberArea`),
données lues en JSON sur l'API du site (`/api/membre`, voir `docs/api-membre.md`
dans le dépôt AFSR/website). Il ne s'agit plus de pages du site affichées dans
une vue web.

## Ce que fait l'app

| Écran | Source |
|---|---|
| Connexion (code SMS / e-mail, choix de fiche) | `POST /connexion`, `/connexion/verification`, `/connexion/compte` |
| Accueil : identité, statut d'adhésion, rubriques | `GET /moi`, `GET /rubriques` |
| Mon adhésion, demande d'arrêt du renouvellement | `GET /adhesion`, `POST /adhesion/renouvellement/arret` |
| Mes informations (coordonnées, adresse) | `POST /moi`, `POST /moi/adresse` |
| Ma famille | `GET /famille` |
| Dons et attestations fiscales (PDF) | `GET /dons`, `GET /dons/{id}/attestation` |
| Réception des envois (papier / e-mail) | `GET/POST /preferences` |
| Publications, communications, rubriques du back-office | `GET /publications`, `/communications`, `/rubriques/{slug}` |

Les documents s'ouvrent dans Aperçu (lecture, partage, « Enregistrer dans
Fichiers »). Ils sont téléchargés dans le dossier temporaire et effacés à la
déconnexion.

## Décisions à connaître

- **Jeton dans le trousseau** (`MemberKeychain`, `ThisDeviceOnly`), jamais dans
  UserDefaults ni iCloud. 90 jours glissants ; un 401 déconnecte et l'écran de
  connexion dit pourquoi.
- **Session éphémère** pour l'API : ni cache disque ni cookies — ce sont des
  données personnelles.
- **Le site reste la source de vérité** des droits : l'app affiche `locked`,
  `membership_required`, `renewal.state` tels que le site les calcule.
- **`renewal.state == "unavailable"` n'est pas « aucun »** : Salesforce n'a pas
  répondu. L'écran dit « nous ne parvenons pas à afficher… », jamais « aucun
  renouvellement » (voir `MemberAPIDecodingTests`).
- **Compte AFSR ≠ données de suivi** : se déconnecter ne touche pas aux données
  du journal, qui restent sur l'appareil et dans l'iCloud personnel.

## Pas encore dans l'app

L'annuaire « Rett friendly » est un lien vers afsr.fr (public). **Déposer ou
modifier un avis** reste sur le site : c'est un formulaire avec carte et
géocodage, à porter dans un second temps.

## Prérequis de mise en ligne

Le site doit être déployé **avant** l'app, avec `php artisan migrate` (table
`member_api_tokens`). Sans cela la connexion répond 404 et l'écran affiche une
erreur — l'app ne plante pas, mais l'espace est inutilisable.
