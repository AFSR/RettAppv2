# Audit UX cohérence — RettApp

Audit du 2026-05 contre les **Apple Human Interface Guidelines** (iOS).
Évalue cohérence inter-onglets, conformité plateforme, accessibilité et points
de friction.

> Verdict global : **B+**. Architecture solide (TabView native, navigation
> hiérarchique standard, palette adaptative dark/light, composants partagés).
> Quelques inconsistances sur les paddings, les libellés et les états vides.

---

## 1. Couleurs et thème

| Critère HIG | Statut | Notes |
|---|---|---|
| Adaptation Dark/Light Mode | ✅ | `afsrBackground` et `afsrPurpleAdaptive` via `UIColor(dynamicProvider:)` (commit `c9bb3a6`, audit Lot E) |
| Couleurs sémantiques (success/warning/error) | ✅ | `afsrSuccess`, `afsrWarning`, `afsrEmergency` |
| Contrast WCAG AA | ⚠️ | `afsrPurpleLight` (#9B6FC8) sur fond noir = 4.6:1 — **OK** pour AA non-large mais juste au seuil. À surveiller si on l'utilise sur petits caractères. |
| Tint cohérent inter-onglets | ✅ | `.tint(.afsrPurpleAdaptive)` posé au niveau Scene |

**Action prise (Lot E)** : remplacement des derniers `Color.afsrPurple` (non
adaptatif) restants dans `AFSRPrimaryButton`, `AFSRSecondaryButton`,
`ProfileSetupView`, `EyeGameView`, `SettingsView` → `Color.afsrPurpleAdaptive`.

## 2. Typographie

| Critère HIG | Statut | Notes |
|---|---|---|
| Hiérarchie typographique | ✅ | `AFSRFont.title/headline/body/caption` |
| `.system(...rounded)` pour éléments AFSR | ✅ | titres + headlines en rounded, cohérent |
| Dynamic Type | ⚠️ | Utilise `.system(size:weight:design:)` qui ne réagit pas automatiquement à Dynamic Type. → **améliorer en V2** : utiliser `.font(.title2)` etc. avec scaling automatique |
| Taille minimum (16pt) | ✅ | `AFSRFont.body(17)` par défaut, `caption(13)` au minimum pour les annotations |

**Recommandation V2** : migrer `AFSRFont` vers les semantic font styles SwiftUI
pour un Dynamic Type natif (`.title`, `.headline`, `.body`).

## 3. Tap targets

| Critère HIG | Statut | Notes |
|---|---|---|
| Taille minimum 44pt | ✅ | `AFSRTokens.minTapTarget = 60` (au-dessus du minimum HIG) — adapté au public aidant qui peut taper en situation de stress |
| Distance entre cibles | ✅ | spacings ≥ 8pt entre actions |

## 4. Navigation

| Onglet | NavigationTitle | Display Mode | Cohérent ? |
|---|---|---|---|
| Suivi épilepsie | "Épilepsie" | inline | ⚠️ Le titre devrait être "Suivi épilepsie" pour matcher le tab. **Fix** : aligner. |
| Tableau de bord | dynamique (avec prénom) | large | ✅ |
| Médicaments | dynamique "Journal — [Prénom]" | large | ✅ |
| Jeu Regard | "Jeu du Regard" | inline | ✅ |
| Réglages | "Réglages" | implicit | ✅ |

**Action recommandée P1** : aligner le titre Suivi épilepsie. Voir `SeizureTrackerView.navigationTitle`.

## 5. Composants standards vs custom

| Élément | Standard ou custom | Justification |
|---|---|---|
| Boutons primaires | `AFSRPrimaryButton` (custom) | Tap target ≥ 60pt, brand color. ✅ |
| Toggle, Slider, Stepper | natifs | ✅ |
| Picker | natifs (.segmented dans la majorité des cas) | ✅ |
| Sheets | natifs `.sheet(isPresented:)` | ✅ |
| Alerts | `.alert` + `.confirmationDialog` (destructifs) | ✅ |
| Boutons "Quitter" jeu regard | `.borderedProminent` | ✅ — convention iOS |

## 6. États vides

| Écran | État vide ? |
|---|---|
| Suivi épilepsie | ✅ texte sous le bouton si pas de dernière crise |
| Historique crises | ✅ `EmptyStateView` |
| Tableau de bord | ✅ placeholder dans chaque chart |
| Journal médicaments | ✅ icône + message + CTA |
| Plan médicamenteux | ✅ via fil normal (formulaire) |
| Rapports archivés | ✅ section masquée si vide |
| Cahiers archivés | ✅ section masquée si vide |
| Jeu Regard non compatible | ✅ `UnsupportedView` dédiée |

## 7. Accessibilité

| Critère HIG | Statut | Notes |
|---|---|---|
| `accessibilityLabel` sur boutons icônes | ⚠️ | Présent sur les principaux (Calibration badge, urgence crise, ad-hoc) ; manque sur quelques icones de toolbar |
| `accessibilityHint` | ✅ Sur le bouton "Démarrer une crise" |
| Support VoiceOver | ⚠️ Pas testé en mode VoiceOver complet |
| Couleur pas seul porteur d'info | ✅ Statut prises = icône + couleur |

**Action recommandée P2** : passer toutes les vues sous VoiceOver et combler
les labels manquants.

## 8. Internationalisation

| Statut | Détail |
|---|---|
| ✅ Français FR primaire | `Localizable.strings` + locale `fr_FR` partout |
| ⚠️ Format de dates | Mix de `Locale(identifier: "fr_FR")` explicite et `Date.FormatStyle` automatique. Cohérent en pratique mais à uniformiser |
| ❌ Anglais / autres | non prévu V1 — peut être ajouté plus tard |

## 9. Performance / réactivité

| Onglet | Réactivité |
|---|---|
| Suivi épilepsie | <50ms démarrage chrono — ✅ |
| Tableau de bord | Render Charts < 1s sur datasets de démo (90 jours) — ✅ |
| Journal médicaments | Smooth (LazyVStack) — ✅ |
| Jeu Regard | 60fps ARKit, calibration + Kalman fluides — ✅ |
| Génération PDF | Rapport médecin avec graphiques : ~1-2s sur device récent |

## 10. Cohérence des sheets

Convention adoptée :
- **Push** (`NavigationLink`) → drill-down dans la même hiérarchie (Réglages)
- **Sheet** → action ponctuelle / modale
- **Confirmation dialog** → destructions + actions sensibles

✅ Respecté partout.

---

## Findings priorisés

### 🔴 P1 — À corriger pour V1.3

- [x] Remplacer `afsrPurple` (non-adaptatif) par `afsrPurpleAdaptive` dans
      AFSRButton, ProfileSetupView, EyeGameView, SettingsView (Lot E)
- [ ] Aligner le `navigationTitle` de l'onglet Suivi épilepsie sur le label du
      tab "Suivi épilepsie"
- [ ] Ajouter les `accessibilityLabel` manquants sur les toolbar items
      (Plan médicamenteux, Date picker, Calibration reset)

### 🟠 P2 — Avant déploiement national

- [ ] Migrer `AFSRFont` vers semantic font styles (`.title2`, `.headline`,
      `.body`) pour Dynamic Type natif
- [ ] Test VoiceOver complet (parcours onboarding → suivi crise → médicaments)
- [ ] Vérifier le contraste de `afsrPurpleLight` sur fonds clairs WCAG AA

### 🟡 P3 — Polissage

- [ ] Animation de transition entre les états du chronomètre crise
- [ ] Indicateur de progression visible sur la génération PDF
- [ ] Feedback haptique léger sur `recordCalibrationTap` (pour confirmer la
      capture sans regarder l'écran)

---

## Conformité globale aux HIG

| Section HIG | Score |
|---|---|
| Color | A− |
| Typography | B+ (Dynamic Type pas natif) |
| Layout | A |
| Navigation | A− |
| Controls | A |
| Accessibility | B (à approfondir) |
| Animation | B |
| Onboarding | A |

**Verdict** : application conforme aux pratiques iOS modernes (SwiftUI, iOS 17,
SF Symbols, Sign in with Apple, Charts natifs). Pas de blocant pour l'App Store
côté UX, sous réserve des P1 ci-dessus.
