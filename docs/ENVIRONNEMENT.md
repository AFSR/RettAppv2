# L'environnement de session

Ce que la machine d'une session Claude sait faire sur ce projet, et ce qu'elle
ne sait pas. Écrit le 11 novembre 2026, après une journée de tâtonnements qu'il
est inutile de refaire.

## Pas de macOS

Ni `xcodebuild`, ni `swift`, ni `swiftc`, ni simulateur. **L'application ne peut
être ni compilée ni testée ici.**

Ce qui fonctionne :

```bash
ruby scripts/generate_xcodeproj.rb     # la gem xcodeproj est installée
```

Conséquence à tenir : ne dites jamais qu'un code Swift fonctionne. Dites qu'il
n'a pas été compilé, et nommez les endroits où vous attendez des corrections.

## Le dépôt du site n'est pas là par défaut

```
add_repo(owner: "AFSR", repo: "website")
```

Puis clonez comme l'outil l'indique. **Ne vérifiez pas d'abord si le dépôt
existe** avec `curl` ou `git ls-remote` : une requête non authentifiée sur un
dépôt privé répond 404 même quand l'accès est accordé, et ce 404 trompeur fait
renoncer à tort.

## Le clone est superficiel

`git log` ne remonte pas avant le 8 mai 2026 (une racine greffée). Les commits
antérieurs existent sur GitHub mais pas ici. N'en déduisez pas que le projet
commence là.

## Tests du site : MariaDB est obligatoire

sqlite **ne passe pas** les migrations (une migration de la table `sessions`
échoue). Et MariaDB ne survit pas d'une session à l'autre : relancez-le.

```bash
mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld
(mysqld_safe > /dev/null 2>&1 &)
for i in $(seq 1 20); do sleep 3; mysqladmin -uroot -proot status >/dev/null 2>&1 && break; done
```

Il écoute sur `127.0.0.1:3306`, utilisateur `root`, mot de passe `root`, base
`afsr`. Sans le mot de passe, `mysqladmin status` répond « Access denied » — ce
n'est **pas** un serveur éteint, c'est une authentification manquante. Cette
confusion m'a fait relancer un serveur qui tournait.

Si la base n'existe pas :

```bash
mysql -uroot -proot -e "CREATE DATABASE IF NOT EXISTS afsr CHARACTER SET utf8mb4;"
cd /home/user/website && php artisan migrate --force
```

Le `.env` local doit porter `DB_CONNECTION=mysql`, `DB_DATABASE=afsr`,
`DB_USERNAME=root`, `DB_PASSWORD=root`, et une `APP_KEY` — sinon les tests
échouent sur `MissingAppKeyException` :

```bash
php artisan key:generate --force
```

### Le manifeste Vite

Sans `public/build/manifest.json`, toute page qui passe par le gabarit échoue.
Une fois par session suffit :

```bash
npm ci --no-audit --no-fund && npm run build
```

### Puis

```bash
php artisan test                       # ~320 tests, ~85 s
php artisan test --filter=MonTest
```

PHP est en **8.3** ici, en **8.5** en CI. Une incompatibilité de version ne se
verra donc pas localement.

## Réseau

Allowlist : `afsr.fr`, `www.afsr.fr`, `verticalsoft.my.salesforce-sites.com`.
Les registres de paquets (composer, npm, apt) passent sans être listés.

**Le pare-feu d'afsr.fr répond 403 à tout User-Agent commençant par `curl/`**,
page d'accueil comprise. Avec un en-tête de navigateur ou d'application, tout
répond normalement :

```bash
UA="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
curl -s -A "$UA" -o /dev/null -w '%{http_code}\n' https://afsr.fr/
```

J'ai conclu que le site entier était cassé avant de comprendre.

Le sous-domaine `rettapp.afsr.fr` est hors allowlist. Il est de toute façon
obsolète : ses pages sont servies par le dépôt du site depuis novembre 2026.

## GitHub

Les outils MCP `mcp__github__*` couvrent les deux dépôts. Il n'y a **pas** de
`gh` pour créer une pull request, mais `gh api` fonctionne en lecture — c'est
ce qui sert à attendre la CI.

| Dépôt | CI | Déploiement |
|---|---|---|
| `AFSR/RettAppv2` | **aucune** | aucun |
| `AFSR/website` | `tests.yml`, sur PR et sur push vers `main` | `deploy.yml` déploie **en production** à chaque push sur `main`, migrations comprises |

## Durable et jetable

Le conteneur est éphémère : ce qui n'est pas committé et poussé est perdu. Les
services installés à la main (MariaDB) et les fichiers hors dépôt ne survivent
pas.

Le répertoire bac à sable de la session sert aux fichiers de travail ; ne les
mettez pas dans les dépôts.

## Pièges de commandes

- **Ne bornez jamais `composer install` par un `timeout`.** Il est mort en
  exit 143 à 540 s, laissant 92 paquets sans autoload, et l'erreur suivante ne
  parlait pas de ça.
- `npm ci` a réécrit `yarn.lock` une fois, alors que le dépôt porte les deux
  fichiers de verrouillage. Vérifiez `git status` après, et ne committez pas
  cette réécriture.
- `git log --reverse -1` ne donne **pas** le premier commit : la limite
  s'applique avant l'inversion. Utilisez `git log --reverse --format=... | head -1`.
