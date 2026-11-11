---
name: fusionner-sur-main
description: Fusionner la branche de travail dans main, sur le dépôt de l'app ou du site. À utiliser quand l'utilisateur demande de fusionner, de pousser sur main, ou d'intégrer le travail. Couvre le conflit systématique du project.pbxproj, l'attente de la CI et le déploiement en production du site.
---

# Fusionner sur `main`

Fait six fois le 11 novembre 2026, raté une fois faute d'avoir rattrapé `main`
d'abord. Les étapes sont dans cet ordre pour des raisons précises.

## 1. Rattraper `main` AVANT tout

```bash
git fetch origin main
git log --oneline origin/main..HEAD | wc -l   # ce que vous apportez
git log --oneline HEAD..origin/main | wc -l   # ce que vous ignorez
```

D'autres sessions Claude écrivent sur ces dépôts en même temps. Le retard n'est
pas théorique : j'ai écrit une API entière en double pour avoir lu un `main`
local périmé. Si le second compteur n'est pas nul :

```bash
git merge origin/main --no-edit
```

## 2. Résoudre les conflits

### Dépôt de l'app : le `project.pbxproj` conflite TOUJOURS

Le générateur réattribue tous les identifiants internes à chaque exécution.
N'essayez pas de lire ce conflit.

```bash
git checkout --theirs RettApp.xcodeproj/project.pbxproj \
                      RettApp.xcodeproj/xcshareddata/xcschemes/RettApp.xcscheme
git add RettApp.xcodeproj
ruby scripts/generate_xcodeproj.rb
git add -A
git diff --name-only --diff-filter=U        # doit être vide
```

Vérifiez ensuite que la version n'a pas régressé — voir
`.claude/rules/xcodeproj.md`.

### Les autres conflits

Lisez-les. En particulier : si `main` apporte une version d'un fichier que vous
avez aussi écrit, demandez-vous **lequel des deux est le meilleur**, et dites-le.
Un `PrivacyInfo.xcprivacy` vide venu de `main` a été remplacé par le mien, qui
le complétait ; une API de lieux que j'avais écrite en double a été jetée, parce
que celle de `main` était mieux placée.

## 3. Pousser

```bash
git push -u origin <branche>
```

En cas d'échec réseau, réessayer avec attente croissante (2 s, 4 s, 8 s, 16 s),
jusqu'à quatre fois.

## 4. Ouvrir la pull request

Avec `mcp__github__create_pull_request`. Le corps dit **le problème, la
décision, et ce qui a été écarté** — pas la liste des fichiers, que GitHub
affiche déjà. Signalez explicitement ce qui n'a pas été vérifié : pour l'app,
que le code n'a pas été compilé.

## 5. Attendre la CI — site seulement

Le dépôt du site a une CI (`tests.yml`) qui ne tourne **que** sur pull request
et sur push vers `main`. Le dépôt de l'app n'en a aucune.

```bash
gh api repos/AFSR/website/commits/$(git rev-parse HEAD)/check-runs \
  --jq '.check_runs[0] | "\(.status)|\(.conclusion)"'
```

Bouclez dessus en tâche de fond jusqu'à `completed`. Ne fusionnez pas avant.

## 6. Fusionner

`mcp__github__merge_pull_request`, `merge_method: "merge"`.

`expectedHeadSha` veut le SHA **complet, 40 caractères** — un SHA court est
refusé. Prenez-le avec `git rev-parse <branche>`.

Pourquoi `merge` et non `squash` : la branche de l'app est réutilisée d'une
session à l'autre, et un squash l'en ferait divergper.

## 7. Réaligner la branche de travail

```bash
git fetch origin && git merge --ff-only origin/main && git push origin <branche>
```

Sans cela la branche reste derrière et la session suivante repart d'un état
périmé. Un hook signale les commits non poussés : il a raison.

## 8. Site : vérifier le déploiement en production

**Pousser sur `main` déploie afsr.fr en production**, automatiquement
(`deploy.yml`, qui exécute `php artisan migrate --force`). Vérifiez qu'il
aboutit :

```bash
gh api "repos/AFSR/website/actions/runs?branch=main&per_page=2" \
  --jq '.workflow_runs[] | "\(.name)=\(.status)|\(.conclusion)"'
```

Puis, si la modification se voit sur une page, contrôlez-la **en production** —
avec un User-Agent de navigateur, sans quoi le pare-feu répond 403 à tout :

```bash
UA="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
curl -s -A "$UA" -o /dev/null -w '%{http_code}\n' https://afsr.fr/politique-de-confidentialite
```

J'ai cru le site entièrement cassé à cause de ce 403, page d'accueil comprise.

## Ce qu'il ne faut pas faire

- **Ouvrir une pull request sans qu'on l'ait demandée.**
- Fusionner une PR dont la CI n'est pas verte.
- Forcer un push sur une branche partagée.
- Toucher aux branches des autres sessions. Au 11 novembre 2026, le dépôt de
  l'app en portait trois qui ne m'appartenaient pas, dont une écrite dans la
  minute.
