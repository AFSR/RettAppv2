# Les décisions, et pourquoi

Ce que le code ne dit pas de lui-même. Chaque décision ci-dessous a été posée
explicitement avec l'association ; les raisons comptent autant que les
décisions, parce que c'est ce qui permet de savoir si un cas nouveau y entre.

## Deux domaines de données, qui ne se touchent pas

Toute l'architecture tient sur cette séparation.

### Le suivi médical : sur l'appareil, et nulle part ailleurs

Crises, prises de médicaments, symptômes, humeur, repas, sommeil, données Apple
Santé. Ils vivent dans SwiftData sur l'iPhone, et — si le partage entre parents
est activé — dans une zone de l'**iCloud personnel de la famille**.

**Aucun serveur de l'AFSR ne les reçoit.** L'association ne peut ni les lire,
ni les copier, ni les perdre. Ce n'est pas une précaution de confort : c'est ce
qu'affirme la politique de confidentialité publiée, c'est ce qui permet de ne
**pas** déclarer de données de santé dans la fiche App Store, et c'est ce qui
rend l'application acceptable pour des familles qui confient l'état de santé de
leur enfant.

Conséquences pratiques :

- l'app n'a pas de compte, pas de serveur, pas de sauvegarde côté AFSR ;
- l'association ne peut pas effacer les données d'une famille à sa demande —
  elle ne les détient pas, et la politique le dit ;
- la synchronisation entre parents passe par CloudKit, c'est-à-dire par Apple
  comme sous-traitant de la famille, pas de l'association.

### Les données de l'association : Salesforce fait foi

Adhésions, dons, reçus fiscaux, publications réservées, coordonnées. Salesforce
(hébergé par VerticalSoft, revendeur multi-hébergé) est la **base de
référence**.

L'application **ne conserve ni ne calcule rien** de ce domaine. Elle remonte les
actions vers afsr.fr, qui écrit dans Salesforce, et va relire chez Salesforce ce
qu'elle affiche.

> Un don ou une adhésion qui n'arrive pas dans Salesforce n'existe pas : pas
> d'attribution au bon contact, pas d'historique, pas de reçu fiscal. Toute
> copie locale finirait par diverger de la seule version qui fait foi.

## L'app ne détient aucun secret

Ni clé Stripe, ni identifiants Salesforce. Le jeton qui identifie l'application
auprès du site est **extractible du binaire** : il filtre le bruit, il ne
garantit pas qui appelle.

Ce qui protège réellement est ailleurs : montants bornés côté serveur, clé
Stripe qui ne quitte pas afsr.fr, rattachement à un contact depuis la session
seulement, limitation de débit.

## Le don en deux temps

Le chemin est : l'app encaisse par Apple Pay → poste à afsr.fr → le site débite
via Stripe → **Stripe appelle le webhook** → le site crée la `Commande__c`.

La première version faisait tout dans la même requête. Si Salesforce échouait,
le donateur était débité et le don n'existait nulle part ; un message dans les
journaux n'est pas un rattrapage.

Stripe réessaie la livraison d'un événement pendant environ trois jours tant que
l'endpoint ne répond pas 2xx. Le paiement devient donc la source de vérité du
« ça a abouti », et l'écriture dans Salesforce devient une **conséquence
garantie** plutôt qu'un espoir :

- pas de don sans paiement — on n'écrit que sur événement confirmé ;
- pas de paiement sans don — Stripe insiste jusqu'à ce que ça passe.

Le webhook répond **500 volontairement** quand Salesforce échoue. C'est tout le
mécanisme ; ne le « corrigez » pas en 200.

Un paiement de la boutique, qui encaisse sur le même compte Stripe, reçoit
**202** : un 500 de trop mettrait chacune de ses commandes en boucle de réessais
pendant trois jours.

## Le public sans compte

Dons et adhésions doivent fonctionner **même pour qui n'a pas d'espace
adhérent**. Une session ouverte rattache la commande au contact ; sans session,
elle reste sans contact et l'association la rattache comme un don reçu par
courrier.

Une adresse e-mail saisie n'est pas vérifiée : s'en servir pour rattacher
laisserait inscrire une attestation fiscale — document opposable à
l'administration — sur le dossier d'un tiers.

## Deux audiences dans une seule app

L'app complète pour les parents et aidants qui tiennent un suivi ; un
sous-ensemble pour les autres — professionnels, donateurs, sympathisants — qui
accèdent aux actualités, à l'espace adhérent et au soutien **sans créer de
profil enfant**. En usage découverte, ce qui ne sert pas n'apparaît pas.

L'onboarding précédent bloquait purement et simplement ce public.

## La corbeille est un fichier, pas un modèle

`RettAppApp` ouvre le `ModelContainer` avec une récupération qui **efface le
magasin** en cas d'échec. Ajouter un `@Model` modifie le schéma ; une migration
qui se passerait mal coûterait à chaque famille toutes ses données locales.

La corbeille suit donc le modèle de `PendingWriteStore` et `SafetySnapshots` :
un fichier JSON dans *Application Support*. Aucun changement de schéma, aucun
risque de migration. Le jeu n'en valait pas la chandelle pour une corbeille.

## Une suppression doit rester opposable

Sans trace d'une suppression, restaurer un instantané antérieur réinsère ce qui
avait été supprimé depuis : la donnée revient d'entre les morts, et le parent
qui l'avait retirée la retrouve sans comprendre.

D'où les **pierres tombales**, poussées vers CloudKit, qui disent « cet
enregistrement a été supprimé, à telle date » et qui l'emportent sur un
enregistrement entrant plus ancien. Trente jours de conservation avant
disparition définitive.

## Le référentiel vient du serveur

Types de lieu, critères d'accessibilité, libellés : l'app les **demande** à
`/lieux/meta`. Ajouter un critère côté site suffit à le voir dans le formulaire,
sans nouvelle version — et une app restée en arrière n'envoie pas de réponses à
un critère retiré.

## Des constats, pas des appréciations

Sur les lieux Rett friendly, les critères sont des **faits vérifiables** (« il y
a une table de change adulte »), et seule la note sur 5 porte sur l'accueil
ressenti.

Deux raisons. Une famille qui prépare un séjour a besoin de faits : savoir qu'il
faudra changer sa fille par terre décide d'une réservation, une note de 3 sur 5
ne décide de rien. Et l'association est éditrice de ce qu'elle publie : relater
un fait se défend, porter un jugement sur un commerce l'expose au grief de
dénigrement.

Troisième réponse possible, et c'est la plus honnête : **rien**. « Je ne sais
pas » n'est pas une réponse mais son absence, et une famille qui n'a pas essayé
les toilettes adaptées ne doit pas peser dans leur décompte.

## Rien ne se publie sans relecture

Avis déposé → en attente. Lieu proposé → brouillon. Avis déjà en ligne qu'on
modifie → **retour** en relecture. Sans ce retour, il suffirait de publier un
texte anodin puis de le réécrire.

L'association répond de ce qu'elle diffuse sur des commerces nommés.

## Le texte des avis est réservé aux adhérents à jour

Le partage n'est pas symétrique. L'annuaire, les notes et les constats sont
publics — des renseignements sur un commerce, utiles bien au-delà des adhérents,
et de nature à faire connaître l'association. Le **texte** des avis reste entre
adhérents : c'est là qu'une famille raconte son séjour, et le ton y est libre.

Avoir un compte ne suffit pas ; l'adhésion doit être en cours.

## Les pages légales vivent dans le dépôt du site

Elles ont été des fichiers HTML déposés une fois sur un sous-domaine séparé, que
rien ne déployait et dont plus personne ne savait où ils étaient servis. Or
l'URL de la politique de confidentialité est **citée dans la fiche App Store** :
une adresse qui ne répond pas fait refuser une mise à jour.

Elles sont désormais servies par `AFSR/website` depuis son dépôt, versionnées,
déployées avec lui et couvertes par ses tests. Un seul document de
confidentialité couvre l'association entière — site et application : l'AFSR est
un responsable de traitement, pas deux, et deux textes séparés finissent
toujours par se contredire.

## Une seule copie d'une règle

Le dépôt du gestionnaire d'avis est partagé entre le formulaire du site et
l'API mobile (`SubmitsEstablishmentReviews`). Deux copies d'une règle de
modération divergent toujours, et la copie oubliée est celle qui publie sans
relire.

Le même principe a conduit à servir le référentiel plutôt qu'à le dupliquer, et
à faire calculer par le serveur les phrases qui suivent des règles de langue
(« constaté par 2 adhérents sur 3 »).

## Ce qu'on ne sait pas, on ne l'écrit pas

Les listes de choix Salesforce inconnues restent **vides** en configuration :
une valeur hors liste fait échouer l'insertion — donc un paiement encaissé sans
don enregistré — et une valeur acceptée mais fausse s'imprime sur une
attestation fiscale, document opposable à l'administration.

De même, le RNA, le SIREN et le directeur de la publication sont lus en
configuration, et leur ligne **disparaît** de la page quand ils sont vides. Une
page incomplète vaut mieux qu'une page fausse, et beaucoup mieux qu'un
« [À COMPLÉTER] » publié.

## Dette assumée

- Tout `RettApp/Features/Places/**`, la corbeille et les pierres tombales
  **n'ont jamais été compilés** (pas de macOS dans les sessions).
- `SettingsView.swift` et `SettingsSubviews.swift` dupliquent `eraseAll()` et
  `exportAllCSV()`. À unifier, en commençant par déterminer lequel est vivant.
- `DonationService.isApplePayEnabled` est déclaré et lu par personne.
- `aps-environment` vaut `development` dans les entitlements, et
  `UIRequiredDeviceCapabilities` contient `armv7` sur une app iOS 17. Déjà
  publié ainsi, donc non bloquant — à nettoyer un jour.
- Les conditions générales de vente du site restent un brouillon.
