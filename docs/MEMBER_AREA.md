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

## Verrou biométrique

- **Trois états** : déconnecté (écran de connexion) → verrouillé (l'onglet reste affiché, aucune
  donnée) → déverrouillé. `MemberSession` porte l'état ; `MemberLockView` l'écran de verrouillage.
- **Jeton d'accès** dans le trousseau avec `SecAccessControl` *biométrie actuelle OU code*,
  `WhenPasscodeSetThisDeviceOnly` : jamais iCloud, détruit si le code de l'iPhone est retiré.
  Changer les visages enregistrés n'ouvre plus rien par biométrie ; le code reste en repli.
- **Jeton de révocation** hors verrou : il ne sert qu'à détruire le jeton d'accès côté site
  (`POST /revocation`), pour pouvoir le faire même quand Face ID a échoué.
- **Reverrouillage** : à chaque lancement et après plus d'une minute en arrière-plan
  (`MemberSession.gracePeriod`). Écran flouté dans le sélecteur d'apps. Documents temporaires
  effacés à chaque verrouillage.
- **Échecs** : annuler l'invite n'est *pas* un échec. Un refus compte ; au 5ᵉ
  (`MemberSession.maxFailures`) le jeton local est détruit et la révocation envoyée — rejouée
  au lancement suivant si le réseau manquait.
- **Appareil sans code** : le jeton ne peut pas être protégé, donc pas conservé. La session
  vit en mémoire, avec un avertissement.
- **Face ID est opaque pour l'app** : elle ne reçoit que « accepté » ou « refusé ».
  `NSFaceIDUsageDescription` est dans `Info.plist`.
- Le **seuil de 5** s'ajoute au verrouillage propre d'iOS (qui impose le code après des échecs
  de Face ID) : un « refus » ici est déjà une série d'échecs côté système.

## Décisions à connaître

- **Session éphémère** pour l'API : ni cache disque ni cookies — ce sont des données personnelles.
- **Le site reste la source de vérité** des droits : l'app affiche `locked`,
  `membership_required`, `renewal.state` tels que le site les calcule.
- **`renewal.state == "unavailable"` n'est pas « aucun »** : Salesforce n'a pas répondu. L'écran
  dit « nous ne parvenons pas à afficher… », jamais « aucun renouvellement ».
- **Compte AFSR ≠ données de suivi** : se déconnecter ne touche pas aux données du journal.
- L'onglet **Adhérent** remplace l'entrée « Espace adhérent » de Réglages et de l'accueil
  découverte dès qu'on est connecté.

## Lieux Rett friendly (onglet « Lieux »)

Intégrés à l'app, publics pour la lecture, réservés aux adhérents à jour pour l'écriture.

- **Carte et liste** (`PlacesView`) : recherche instantanée (sans accents ni casse, filtrée en
  mémoire — tout l'annuaire tient en une réponse), filtres par type et département,
  « Autour de moi » (position **uniquement sur l'appareil**, jamais envoyée ; autorisation
  demandée au premier appui, pas à l'ouverture de l'onglet).
- **Fiche** (`PlaceDetailView`) : itinéraire dans Plans, appel, site, ce que les adhérents ont
  constaté (« constaté par 3 adhérents sur 4 »), avis. Le **texte** des avis n'est lisible
  que d'un adhérent à jour déverrouillé ; la note et les constats restent publics.
- **Donner un avis** (`PlaceChooserView` → `PlaceReviewForm`) : on cherche le lieu dans
  l'annuaire, puis sur **Plans** (MapKit) s'il n'y figure pas — nom, adresse, ville et
  position viennent avec le résultat, le type est déduit de la catégorie et se corrige. Tout
  arrive **en relecture**, un lieu proposé arrive en **brouillon**, comme sur le site.
- **Mes avis** (Adhérent › Mes avis sur les lieux) : état en relecture / publié / refusé,
  modification (repasse en relecture) et retrait.
- Règles identiques au site, vérifiées par `PlacesApiTest` côté site : un avis par lieu, cinq
  dépôts par jour, engagement de visite obligatoire.

## Prérequis de mise en ligne

Le site doit être déployé **avant** l'app, avec `php artisan migrate` (tables
`member_api_tokens` et colonne `revoke_hash`). Liste complète : `SITE_ESPACE_ADHERENT_TODO.md`. Sans cela la connexion répond 404 et l'écran affiche une
erreur — l'app ne plante pas, mais l'espace est inutilisable.
