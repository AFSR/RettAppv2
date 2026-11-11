# Pages de produit personnalisées (Custom Product Pages) — RettApp

Compte : **App Store Connect → compte développeur AFSR** · App : **RettApp** (`fr.afsr.RettApp`)
Chemin : *My Apps → RettApp → Distribution → Custom Product Pages → ➕ Create Custom Product Page*

## Ce qu'une page personnalisée peut changer

| Modifiable | Non modifiable (hérité de la fiche principale) |
|---|---|
| Texte promotionnel (170 car.) | Nom, sous-titre, description, mots-clés |
| Captures d'écran (par taille d'appareil) | Icône, catégories, âge, confidentialité |
| Aperçus vidéo (optionnel) | Notes de version |
| Nom interne (64 car., invisible du public) | |

Chaque page obtient sa **propre URL** (à utiliser dans les liens afsr.fr, newsletters, réseaux
sociaux, QR codes). Jusqu'à 70 pages par app. Une page doit être **soumise à la revue Apple**
(possible sans nouvelle build ; l'app doit déjà être publiée ou en revue).

Les captures sont celles du §12 de `APP_STORE_LISTING.md` : iPhone 6,9"/6,7" (1290×2796) obligatoire,
iPad 13" si l'app est universelle. Réutiliser les mêmes visuels, **réordonnés** selon la page.

> Le texte promotionnel respecte l'avertissement médical : aucune promesse de diagnostic ni de
> traitement. Pas de nom de médicament ni d'avis médical dans les captures (revue Apple, 1.4.1).

---

## Page 1 — « Familles · Suivi épilepsie » (priorité)

- **Nom interne** : `CPP1-Familles-Epilepsie`
- **Public / canal** : parents qui découvrent l'épilepsie du syndrome de Rett ; réseaux sociaux, page afsr.fr/rettapp
- **Texte promotionnel** (159 car.) :
```
Un chronomètre d'une main pour chaque crise, qualifiée en quelques secondes. Retrouvez fréquence et intensité dans un tableau de bord clair pour le neurologue.
```
- **Captures, dans l'ordre** :
  1. Chronomètre de crise actif — « Démarrez le chronomètre d'une seule main »
  2. Qualification + ⓘ description — « Qualifiez la crise avec un guide pour chaque type »
  3. Tableau de bord, vue mois — « Visualisez fréquence et intensité dans le temps »
  4. Historique / export CSV — « Exportez l'historique pour votre neurologue »
  5. Réglages (données sur l'appareil) — « Vos données restent protégées »

## Page 2 — « Médicaments »

- **Nom interne** : `CPP2-Medicaments`
- **Public / canal** : aidants gérant un traitement lourd ; groupes de parents
- **Texte promotionnel** (156 car.) :
```
Plan médicamenteux, rappels à chaque prise et historique des révisions. La base officielle des médicaments est intégrée à l'app, gratuite et sans publicité.
```
- **Captures, dans l'ordre** :
  1. Plan du jour regroupé par moment — « Vos médicaments du jour, regroupés par moment »
  2. Fiche médicament (recherche base BDPM) — « Base officielle intégrée »
  3. Journal des prises — « Gardez la trace de chaque prise »
  4. Historique des révisions du plan — « Retrouvez chaque changement de traitement »
  5. Tableau de bord — « Croisez traitements et crises »

## Page 3 — « Rendez-vous médical » (rapports)

- **Nom interne** : `CPP3-Rapport-Medecin`
- **Public / canal** : familles avant consultation ; courriers aux équipes de soin
- **Texte promotionnel** (162 car.) :
```
Générez en un geste un rapport PDF pour le médecin : crises, traitements, humeur, symptômes. Vos données restent protégées, partagées uniquement avec vos proches.
```
- **Captures, dans l'ordre** :
  1. Aperçu du rapport médical PDF — « Un rapport prêt pour la consultation »
  2. Carnet de suivi (génération / QR) — « Imprimez ou importez le carnet »
  3. Humeur et symptômes — « Notez le quotidien en quelques touches »
  4. Synchronisation entre parents — « Partagez le suivi entre parents »
  5. Tableau de bord — « Une vue claire des tendances »

## Page 4 — « Communauté AFSR » (adhérents, dons)

- **Nom interne** : `CPP4-Communaute-AFSR`
- **Public / canal** : adhérents, newsletter AFSR, événements, campagne de dons
- **Texte promotionnel** (142 car.) :
```
L'application de l'AFSR : actualités de l'association, espace adhérent et suivi du quotidien de votre enfant. Gratuite, financée par les dons.
```
- **Captures, dans l'ordre** :
  1. Actualités AFSR — « Les nouvelles de l'association »
  2. Espace adhérent — « Votre espace adhérent dans l'app »
  3. Chronomètre de crise — « Le suivi du quotidien »
  4. Plan médicamenteux — « Vos médicaments du jour »
  5. Écran de don — « Soutenez les familles »

> ⚠️ Page 4 : n'inclure l'écran de don que si le don est actif dans la build publiée
> (voir `disabled-features/donation-applepay/README.md`) ; sinon le remplacer par l'espace adhérent.

---

## Procédure dans App Store Connect (par page)

1. **Create Custom Product Page** → saisir le *nom interne*.
2. Coller le *texte promotionnel* (langue FR ; dupliquer pour EN/pt-BR si ces langues sont actives).
3. Importer les captures **dans l'ordre indiqué**, pour chaque taille requise.
4. *Save*, puis **Submit for Review** (peut être groupé avec une version).
5. Une fois approuvée, copier l'**URL de la page** et l'utiliser dans afsr.fr / newsletter / QR code.
6. Suivre les statistiques dans *App Analytics → Product Page* (impressions, téléchargements par page).

## Points à confirmer par l'AFSR

- [ ] Quelles pages lancer en premier (suggestion : 1 et 3)
- [ ] Captures prêtes (à produire depuis l'app, sans données réelles d'enfant)
- [ ] Langues à couvrir (FR seul, ou FR + EN + pt-BR comme la politique de confidentialité)
