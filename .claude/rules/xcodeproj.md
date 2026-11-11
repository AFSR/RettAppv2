---
description: Le projet Xcode est généré. Quand et comment le régénérer, où vit la version, comment résoudre ses conflits.
globs:
  - "RettApp.xcodeproj/**"
  - "scripts/generate_xcodeproj.rb"
---

# Le projet Xcode est généré, pas écrit

`RettApp.xcodeproj` est produit par `scripts/generate_xcodeproj.rb`, qui
parcourt l'arborescence des sources. Rien ne s'y modifie à la main : la
prochaine exécution écrase tout.

```bash
ruby scripts/generate_xcodeproj.rb
```

**À lancer après tout ajout, renommage ou suppression de fichier source.** Un
fichier Swift absent du projet ne compile pas, et rien ne le signale avant le
premier build — qui n'a pas lieu dans cette session.

## Vérifier qu'un fichier est bien entré

```bash
grep -c "MonFichier.swift" RettApp.xcodeproj/project.pbxproj   # attendu : 4
```

Quatre occurrences : la référence, le fichier de build, le groupe, la phase de
compilation. Zéro signifie que le générateur ne l'a pas vu.

Pour une **ressource** (plist, base de données, manifeste), vérifiez qu'elle est
dans la phase `Resources` et pas seulement référencée :

```bash
ruby -e 'src = File.read("RettApp.xcodeproj/project.pbxproj"); \
  puts src[/\/\* Resources \*\/ = \{.*?\};/m].include?("PrivacyInfo")'
```

Déclarée en simple référence, elle apparaît dans Xcode **sans être copiée dans
le bundle** — et l'envoi est rejeté sans que rien ne le montre dans le projet.

## La version vit dans le script

```ruby
'MARKETING_VERSION'       => '1.9.1',
'CURRENT_PROJECT_VERSION' => '12',
```

C'est la **seule** source de vérité. Une version corrigée dans l'interface de
Xcode est perdue à la prochaine régénération.

Ça s'est produit : le projet portait `1.9 / 11`, corrigé à la main, pendant que
le script annonçait encore `1.5.0 / 11`. Une régénération aurait fait régresser
la version annoncée, et **App Store Connect refuse un numéro inférieur au
dernier publié**.

Le build doit être supérieur à tout ce qui a existé, pas seulement à ce qui est
en ligne.

> `project.yml` (XcodeGen) a été supprimé en novembre 2026. Il annonçait
> `1.3.0 / 1` alors que le script annonçait `1.9.1 / 12`, et le README
> présentait les deux comme équivalents : lancer `xcodegen generate` sur un Mac
> aurait publié une version inférieure à celle de l'App Store. Ne le
> réintroduisez pas sans régler cette divergence.

## Les conflits de fusion

Le générateur **réattribue tous les identifiants internes** à chaque exécution.
Deux branches qui ajoutent chacune un fichier produisent donc un conflit sur
l'intégralité du `project.pbxproj` et du scheme. C'est attendu, et ce n'est pas
un conflit à lire.

```bash
git checkout --theirs RettApp.xcodeproj/project.pbxproj \
                      RettApp.xcodeproj/xcshareddata/xcschemes/RettApp.xcscheme
git add RettApp.xcodeproj
ruby scripts/generate_xcodeproj.rb        # réintègre VOS fichiers par-dessus
git add -A
```

`--theirs` prend la version de `main`, puis le générateur y remet les fichiers
des deux côtés, puisqu'il lit le disque et non le projet. Résoudre à la main,
ligne par ligne, produit un projet corrompu.

Vérifiez ensuite que la version n'a pas régressé :

```bash
grep -n "MARKETING_VERSION\|CURRENT_PROJECT_VERSION" RettApp.xcodeproj/project.pbxproj | head -2
```
