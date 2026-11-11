# Site afsr.fr : ce qu'il faut faire pour l'espace adhérent natif et Face ID

Complète `SITE_AFSR_TODO.md`. Code concerné : dépôt AFSR/website, branche
`claude/eager-pascal-nz59mz` (API `/api/membre`, voir `docs/api-membre.md` là-bas).

## A. Déploiement (bloquant)

1. Fusionner la PR du site et laisser `deploy.yml` tourner.
2. **`php artisan migrate --force --no-interaction`** en production. Deux migrations :
   `member_api_tokens` (jetons) et `add_revoke_hash_to_member_api_tokens` (révocation).
   Sans elles, la connexion depuis l'app répond 500.
3. Vérifier que le **cache de production est partagé et persistant** (`CACHE_STORE` =
   `database`, `redis` ou `file`, jamais `array`) : les défis de connexion, la sélection de
   fiche et le contact en cache y vivent. Un cache vidé à chaque requête empêche de se connecter.
4. Vérifier que les **SMS** (fournisseur configuré) et l'**e-mail** partent bien : l'app
   envoie le code par e-mail via la vue `emails.login-code`.
5. Déployer **avant** de publier la build de l'app.
6. Vérifier que `php artisan schedule:run` est bien appelé par le cron de l'hébergement :
   `model:prune` purge les jetons expirés (sans lui ils sont refusés mais s'accumulent).

## B. Pages légales et RGPD (à faire avant la publication)

7. **Politique de confidentialité du site afsr.fr** : ajouter l'application mobile.
   Texte prêt dans `website/confidentialite.html` §2.5 (FR/EN/PT), à reprendre. Points à
   couvrir : données affichées à la demande et non copiées dans l'app ; jeton conservé 90 jours
   après le dernier usage, 365 au plus ; empreinte seule côté serveur ; nom d'appareil générique.
8. **Pages de l'app** (`rettapp.afsr.fr/confidentialite.html`, `privacy-policy.html`,
   `politica-de-privacidade.html`) : republier les fichiers du dossier `website/` de ce dépôt.
   L'ancienne version affirmait que l'app « ne demande pas de permission Face ID » : c'est
   désormais faux, et la page est liée depuis l'App Store.
9. **Registre des traitements** : ajouter « authentification et sessions de l'application
   mobile » (finalité : accès sécurisé à l'espace adhérent ; données : identifiant de contact,
   empreinte de jeton, date d'usage ; durée 90 j glissants / 365 j max ; base légale :
   exécution du service d'adhésion).
10. Mentionner Salesforce, le fournisseur SMS et le fournisseur d'e-mail comme sous-traitants,
    si ce n'est pas déjà fait.
11. Le **journal des téléchargements** (nom, IP, user-agent) alimente aussi les téléchargements
    depuis l'app : sa durée de conservation (365 j) est déjà dans la politique ? À vérifier.

## C. Sécurité (recommandé)

12. **« Mes appareils connectés »** dans `/mon-compte` : liste des jetons (`member_api_tokens` :
    nom, dernier usage) avec bouton « Déconnecter » et « Tout déconnecter ». Aujourd'hui, un
    adhérent qui perd son téléphone n'a aucun moyen de couper la session depuis le site.
13. **E-mail de prévenance** à chaque nouvelle connexion depuis l'app (« Connexion à votre
    espace depuis RettApp — ce n'était pas vous ? »). Détecte une prise de contrôle.
14. **Alerte sur les codes demandés en masse** (logs `Envoi du code de connexion impossible`,
    limites 10/min/IP et 5/h/identifiant déjà en place) : surveiller le coût SMS.
15. Passer en revue le **pare-feu OVH** : l'API n'utilise que GET et POST, rien à ouvrir. Vérifier
    que l'en-tête `Authorization` n'est pas supprimé par le proxy ou par `.htaccess`
    (sinon tout répond 401 : ajouter `SetEnvIf Authorization ... HTTP_AUTHORIZATION` si besoin).

## D. Nettoyage (optionnel)

16. `App\Classes\AppShell`, `afsr.app_shell_token`, et les `@unless($appShell)` des gabarits ne
    servent plus à l'app (elle n'affiche plus de pages du site). Ils sont inoffensifs ; à retirer
    quand on voudra alléger.
17. La page « Lieux Rett friendly » (dépôt d'avis) n'est pas dans l'app : elle ne s'ouvre plus
    dans l'application, seulement dans Safari, où l'adhérent doit se reconnecter.

## E. Côté Apple (hors site)

18. **App Store Connect → Confidentialité de l'app** : déclarer « Coordonnées » (nom, e-mail,
    téléphone, adresse) et « Achats / informations financières » (historique de dons), liés à
    l'utilisateur, pour la fonctionnalité de l'app, sans suivi. Face ID n'est pas une collecte :
    rien de biométrique ne quitte l'appareil.
19. Notes de version : mentionner l'espace adhérent et le verrouillage Face ID.
