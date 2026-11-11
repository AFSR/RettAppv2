---
description: Synchronisation CloudKit entre parents, corbeille et pierres tombales. Zone où une erreur coûte les données d'une famille.
globs:
  - "RettApp/Core/Sync/**"
  - "RettApp/Core/Trash/**"
  - "RettApp/Core/Backup/**"
---

# Synchronisation, corbeille, pierres tombales

C'est la zone la plus dangereuse du dépôt : ce qui s'y casse ne se voit pas en
développement et coûte à des familles le suivi médical de leur enfant.

## La récupération du magasin EFFACE les données

`RettAppApp.swift` ouvre le `ModelContainer` avec une récupération qui, en cas
d'échec, **supprime le fichier et recommence**. Une migration légère qui se
passerait mal coûterait donc à chaque famille la totalité de ses données
locales.

Conséquence directe : **n'ajoutez pas de `@Model` SwiftData pour du confort.**
C'est pourquoi la corbeille (`TrashStore`) est un fichier JSON dans
*Application Support*, comme `PendingWriteStore` et `SafetySnapshots` — aucun
changement de schéma, aucun risque de migration.

Si un nouveau modèle est vraiment nécessaire, c'est une décision à poser
explicitement avec l'association, pas un détail d'implémentation.

## Les pierres tombales ne sont pas un luxe

Une suppression doit rester **opposable**. Sans trace, restaurer un
instantané de sécurité du 1er réinsère ce qui a été supprimé le 3 : la donnée
revient d'entre les morts et le parent qui l'avait retirée la retrouve sans
comprendre.

Trois mécanismes tiennent ensemble, ne cassez pas l'un en touchant l'autre :

1. `TrashStore.record()` dépose l'entrée **avant** la suppression effective, et
   met en file une pierre tombale vers CloudKit ;
2. `TrashStore.shouldRejectIncoming(recordName:lastModifiedAt:)` refuse un
   enregistrement entrant plus ancien que sa suppression ;
3. `CombinedBackupService` saute à l'import tout ce qui a été supprimé après la
   date de la sauvegarde.

Une pierre tombale **reçue** n'est jamais renvoyée : sinon deux appareils se la
relanceraient indéfiniment. C'est le rôle du drapeau `restorable`.

### Le piège du décodeur

`TrashStore.Item.restorableFlag` est optionnel, lu par un accesseur calculé.
Ce n'est pas du style : le décodeur synthétisé de Swift **échoue sur une clé
absente** et ne retombe pas sur la valeur par défaut d'une propriété. Un champ
non optionnel ajouté à `Item` rendrait illisibles tous les fichiers de corbeille
existants — et avec eux la garde contre les résurrections.

## Le schéma CloudKit doit être déployé

Un type d'enregistrement naît au premier écrit vers l'environnement de
**développement**. La production est un environnement séparé, et une app
publiée lui parle.

Un type ajouté ici et non déployé là-bas casse le partage entre parents **chez
les vraies familles uniquement** : rien en développement, rien en TestFlight si
les testeurs utilisent un build de développement, rien à la revue d'Apple.

Ajouter un type à `CKRecordType` impose donc d'inscrire au suivi de version :

- faire tourner un build de développement jusqu'à voir le type dans le CloudKit
  Dashboard du conteneur `iCloud.fr.afsr.RettApp` ;
- **Deploy Schema Changes** vers Production ;
- vérifier dans l'onglet Production.

`Tombstone` est dans ce cas au 11 novembre 2026 : ajouté, pas déployé.

## La synchronisation ne tourne pas sans rôle

`performCycle` commence par `guard role != .none`, et le rôle ne devient
`.owner` qu'au moment où un partage est créé. Sur un appareil sans partage, une
suppression met bien une pierre tombale en file d'attente, mais **rien ne la
pousse**. C'est à savoir avant de conclure qu'une écriture ne part pas.

`Réglages → Partage → Diagnostic` affiche le nombre d'écritures en attente et
l'erreur du dernier cycle.

## L'invitation passe par AirDrop seulement

`ProximityShare` exclut explicitement tous les autres canaux. Les deux iPhones
doivent être côte à côte : un lien d'invitation ne peut pas être intercepté
dans une messagerie. La politique de confidentialité l'affirme — ne rouvrez pas
les autres canaux sans la corriger.
