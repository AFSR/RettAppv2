# Fiche App Store — RettApp

Tous les textes prêts à coller dans App Store Connect, avec les **longueurs
mesurées** (pas estimées) et les réponses aux questionnaires obligatoires.

> **Langues de la fiche** : français (France) — primaire —, anglais, portugais (Brésil).
> Ce sont les trois langues de la politique de confidentialité du site.
>
> ⚠️ **Les captures seront en français dans les trois fiches.** L'application n'a que
> le français dans `CFBundleLocalizations` : un visiteur anglophone lira un texte
> anglais au-dessus de captures françaises. C'est autorisé, et c'est le prix d'une
> fiche multilingue sur une app qui ne l'est pas.

## Ce document a été entièrement refait le 14 novembre 2026

La version précédente datait de la 1.0 et affirmait trois choses devenues fausses.
Elles sont listées ici parce qu'elles peuvent **encore** se trouver dans App Store
Connect, et qu'il faut aller les y chercher :

| Affirmation de la fiche 1.0 | Réalité vérifiée dans le code |
|---|---|
| « Authentification sécurisée par Sign in with Apple » | Aucun `AuthenticationServices`, rien dans les entitlements. Connexion par code à usage unique. |
| « JEU DU REGARD — caméra TrueDepth », décrit sur six lignes | N'existe pas dans l'app. Il vit sur la branche `rett-app-ios`, jamais fusionnée. Il n'en reste qu'un commentaire orphelin dans un fichier mort. |
| « Toutes les données restent sur votre iPhone » | Vrai du **suivi**. Faux en bloc : l'espace adhérent envoie identité et coordonnées à afsr.fr, l'épingle envoie une position précise. |

Les deux premières sont le genre qui attire un rejet : une description qui annonce une
fonction absente, et qui contredit `PrivacyInfo.xcprivacy` sur la caméra à détection de
profondeur. **Vérifiez la fiche en ligne avant toute chose.**

---

## Sommaire

1. [En-tête et résultats de recherche](#1-en-tête-et-résultats-de-recherche)
2. [Mots-clés](#2-mots-clés)
3. [Texte promotionnel](#3-texte-promotionnel)
4. [Description](#4-description)
5. [Nouveautés](#5-nouveautés)
6. [Captures d'écran](#6-captures-décran)
7. [Catégories et URL](#7-catégories-et-url)
8. [Confidentialité — étiquettes App Store](#8-confidentialité--étiquettes-app-store)
9. [Âge et dispositif médical](#9-âge-et-dispositif-médical)
10. [Notes au reviewer](#10-notes-au-reviewer)
11. [Outils de promotion](#11-outils-de-promotion)
12. [Checklist](#12-checklist)

---

## 1. En-tête et résultats de recherche

C'est ce qu'un parent voit **avant** d'ouvrir la fiche : icône, nom, sous-titre, et les
trois premières captures. Apple indexe fortement le nom et le sous-titre — davantage que
les mots-clés.

### Ce qui change

Le nom était `RettApp` seul : 7 caractères sur 30, soit 23 caractères de poids de
recherche laissés vides. Le nom proposé place « Syndrome de Rett » en toutes lettres,
qui est la requête exacte des familles qui viennent de recevoir le diagnostic.

| Champ | Français | Anglais | Portugais (BR) |
|---|---|---|---|
| **Nom** (30) | `RettApp · Syndrome de Rett` | `RettApp · Rett Syndrome` | `RettApp · Síndrome de Rett` |
| | *26 car.* | *23 car.* | *26 car.* |
| **Sous-titre** (30) | `Crises, médicaments, bilan` | `Seizures, medication, trends` | `Crises, medicamentos, resumo` |
| | *26 car.* | *28 car.* | *28 car.* |

Le sous-titre ne répète aucun mot du nom : les deux champs couvrent ensemble *rett*,
*syndrome*, *crises*, *médicaments*, *bilan*. « Épilepsie » passe dans les mots-clés.

### Alternatives pour le nom, si « Syndrome de Rett » paraît redondant avec « RettApp »

| Proposition | Long. | Ce qu'elle vise |
|---|---|---|
| `RettApp · Syndrome de Rett` | 26 | La requête exacte après un diagnostic. **Proposé.** |
| `RettApp · Suivi épilepsie` | 25 | Le terme le plus cherché, mais positionne l'app en outil d'épilepsie plutôt qu'en app de l'association. |
| `RettApp` | 7 | L'actuel. Rien à redire, sinon qu'il ne cherche rien. |

### Alternatives pour le sous-titre

| Proposition | Long. |
|---|---|
| `Crises, médicaments, bilan` | 26 |
| `Crises, traitements, rapports` | 29 |
| `Suivi quotidien, par l'AFSR` | 27 |
| `Le suivi, du côté des parents` | 29 |

### L'icône

Le dégradé magenta et violet depuis le 14 novembre 2026. C'est elle qui paraît dans les
résultats de recherche, à ~60 pt : le papillon blanc s'y lit, le monogramme ne s'y
lirait pas. Ne la changez pas pour une icône chargée sans la regarder à cette taille.

---

## 2. Mots-clés

Champ de 100 caractères, séparés par des **virgules sans espace**. Ne répétez ni le nom,
ni le sous-titre, ni le nom de l'éditeur : Apple les indexe déjà.

**Français** — 91 car.
```
épilepsie,convulsion,aidant,parent,handicap,polyhandicap,neurologie,journal,traitement,afsr
```

**Anglais** — 88 car.
```
epilepsy,seizure,caregiver,parent,disability,neurology,diary,treatment,rare disease,afsr
```

**Portugais (BR)** — 91 car.
```
epilepsia,convulsão,cuidador,pais,deficiência,neurologia,diário,tratamento,doença rara,afsr
```

Pourquoi ceux-là : `épilepsie` et `convulsion` sont les deux formulations d'une même
recherche, l'une savante et l'autre courante. `aidant`, `parent`, `handicap`,
`polyhandicap` sont l'audience. `neurologie` vise les professionnels qui orientent les
familles. `afsr` capte ceux qui cherchent l'association et non l'app.

---

## 3. Texte promotionnel

170 caractères, **modifiables sans nouvelle build** — c'est le champ à utiliser pour
annoncer quelque chose entre deux versions.

**Français** — 151 car.
```
L'annuaire des lieux qui accueillent bien arrive dans l'app, avec l'espace adhérent. Le suivi du quotidien, lui, ne quitte toujours pas votre appareil.
```

**Anglais** — 139 car.
```
The directory of places that welcome well is now in the app, alongside the member area. Day-to-day tracking still never leaves your device.
```

**Portugais (BR)** — 150 car.
```
O diretório de locais que acolhem bem chega ao aplicativo, junto com a área do associado. O acompanhamento do dia a dia continua sem sair do aparelho.
```

---

## 4. Description

4 000 caractères. Celle-ci décrit l'app telle qu'elle est au 14 novembre 2026 : chaque
section correspond à du code qui existe.

### Français

```
RettApp est l'application de l'Association Française du Syndrome de Rett. Elle accompagne les parents et les aidants au quotidien : noter ce qui se passe, s'y retrouver, et arriver au rendez-vous médical avec autre chose que des souvenirs.

LE JOURNAL
Une journée se note en quelques touches : crises, prises de médicaments, humeur, symptômes, observations. L'écran sépare ce qu'on enregistre de ce qu'on consulte, un bouton pour chaque intention — on n'ouvre pas l'app dans le même état d'esprit selon le cas.

LES CRISES
Le chronomètre se déclenche d'une seule main, pendant que l'autre tient l'enfant. La crise se qualifie après coup : type, durée, déclencheur possible. Chaque type est décrit en mots simples, pour les familles qui découvrent l'épilepsie.

LES MÉDICAMENTS
Le plan du jour est regroupé par moment de la journée. Un médicament pris plusieurs fois se configure d'un geste, aux heures des repas. L'application garde l'historique des prises, et celui des révisions du traitement : on retrouve quand une dose a changé, et laquelle.

LE BILAN
Fréquence et intensité des crises, par jour, semaine, mois ou année. Le bilan dit aussi en toutes lettres ce que les données montrent, plutôt que de laisser seul devant quatre graphiques.

POUR LE RENDEZ-VOUS
Un rapport PDF se prépare en un geste : crises, traitements, humeur et symptômes sur la période choisie. Export CSV également. Le cahier de suivi papier rempli par l'école ou le centre se réimporte en le photographiant.

APPLE SANTÉ
L'application peut lire sommeil, repas, hydratation, activité et rythme cardiaque pour les faire figurer au rapport. Rien n'est lu sans votre accord, et rien n'est jamais écrit dans Santé.

ENTRE PARENTS
Le suivi se partage entre deux appareils, par votre iCloud personnel. L'invitation passe par AirDrop seulement : les deux téléphones doivent être côte à côte.

L'ESPACE ADHÉRENT
Votre adhésion, vos dons et vos attestations fiscales, les publications réservées aux adhérents. Connexion par code à usage unique, sans mot de passe, protégée par Face ID.

LES LIEUX RETT FRIENDLY
L'annuaire des lieux qui accueillent bien, tenu par les familles : entrer sans marche, changer un adulte allongé, s'installer à l'écart du bruit. Sur une carte ou dans une liste. Vous pouvez donner votre avis, ou faire connaître un lieu absent en posant une épingle là où vous êtes.

VOS DONNÉES
Le suivi — crises, médicaments, symptômes, données Apple Santé — ne quitte jamais votre appareil ni votre iCloud personnel. Aucun serveur de l'AFSR ne le reçoit. Aucune mesure d'audience, aucun rapporteur d'incidents, aucune publicité, aucune dépendance tierce. L'espace adhérent, lui, dialogue avec afsr.fr pour ce qui regarde l'association : votre identité, votre adhésion, vos dons.

UNE PRÉCISION IMPORTANTE
RettApp est un outil de suivi destiné aux aidants. Elle ne constitue pas un dispositif médical au sens du règlement européen 2017/745, ne remplace pas l'avis d'un professionnel de santé, et ne recommande aucune dose. En cas d'urgence, appelez le 15 ou le 112.

L'AFSR
L'Association Française du Syndrome de Rett accompagne depuis 1988 les familles concernées par cette maladie neurologique rare, qui touche presque exclusivement les filles. RettApp est gratuite, sans publicité, financée par les dons. afsr.fr
```

### Anglais

```
RettApp is the app of the French Rett Syndrome Association (AFSR). It supports parents and carers day to day: writing down what happened, making sense of it, and walking into the next appointment with more than memories.

THE JOURNAL
A day is recorded in a few taps: seizures, medication taken, mood, symptoms, observations. The screen separates what you record from what you read back, one button for each — you don't open the app in the same frame of mind in both cases.

SEIZURES
The timer starts with one hand, while the other holds your child. You describe the seizure afterwards: type, duration, possible trigger. Each type is explained in plain words, for families new to epilepsy.

MEDICATION
The day's plan is grouped by time of day. A medication taken several times is set up in one tap, at mealtimes. The app keeps the history of doses given, and the history of changes to the treatment: you can find when a dose changed, and which one.

TRENDS
Frequency and intensity of seizures, by day, week, month or year. The overview also says in plain words what your data shows, instead of leaving you alone with four charts.

FOR THE APPOINTMENT
A PDF report is prepared in one step: seizures, treatments, mood and symptoms over the period you choose. CSV export too. The paper follow-up booklet filled in by school or by a care centre can be brought back in by photographing it.

APPLE HEALTH
The app can read sleep, meals, hydration, activity and heart rate to include them in the report. Nothing is read without your permission, and nothing is ever written to Health.

BETWEEN PARENTS
Tracking can be shared between two devices, through your own iCloud. The invitation goes by AirDrop only: both phones have to be side by side.

MEMBER AREA
Your membership, your donations and tax receipts, publications reserved for members. Sign in with a one-time code, no password, protected by Face ID.

RETT FRIENDLY PLACES
The directory of places that welcome well, kept by the families themselves: step-free entry, room to change an adult lying down, somewhere quiet away from the crowd. On a map or as a list. You can leave your own review, or make an unlisted place known by dropping a pin where you are.

YOUR DATA
Tracking — seizures, medication, symptoms, Apple Health data — never leaves your device or your own iCloud. No AFSR server receives it. No analytics, no crash reporter, no advertising, no third-party dependency. The member area does talk to afsr.fr, for what concerns the association: your identity, your membership, your donations.

AN IMPORTANT NOTE
RettApp is a tracking tool for carers. It is not a medical device within the meaning of European regulation 2017/745, it does not replace the advice of a health professional, and it recommends no dose. In an emergency, call your local emergency number.

ABOUT AFSR
The French Rett Syndrome Association has supported families affected by this rare neurological condition since 1988. It affects almost exclusively girls. RettApp is free, without advertising, funded by donations. afsr.fr
```

### Portugais (Brésil)

```
O RettApp é o aplicativo da Associação Francesa da Síndrome de Rett (AFSR). Ele acompanha pais e cuidadores no dia a dia: anotar o que aconteceu, entender o conjunto, e chegar à consulta com mais do que lembranças.

O DIÁRIO
Um dia se registra em alguns toques: crises, doses de medicamento, humor, sintomas, observações. A tela separa o que você registra do que você consulta, um botão para cada intenção — não se abre o aplicativo no mesmo estado de espírito nos dois casos.

AS CRISES
O cronômetro começa com uma só mão, enquanto a outra segura a criança. A crise é descrita depois: tipo, duração, possível desencadeante. Cada tipo é explicado em palavras simples, para as famílias que estão descobrindo a epilepsia.

OS MEDICAMENTOS
O plano do dia é agrupado por momento. Um medicamento tomado várias vezes é configurado em um toque, nos horários das refeições. O aplicativo guarda o histórico das doses dadas e o das mudanças no tratamento: dá para encontrar quando uma dose mudou, e qual.

O BALANÇO
Frequência e intensidade das crises, por dia, semana, mês ou ano. O balanço também diz em palavras claras o que seus dados mostram, em vez de deixar você sozinho diante de quatro gráficos.

PARA A CONSULTA
Um relatório em PDF se prepara em um gesto: crises, tratamentos, humor e sintomas no período escolhido. Exportação em CSV também. O caderno de acompanhamento em papel preenchido pela escola ou pelo centro pode ser trazido de volta fotografando-o.

APPLE SAÚDE
O aplicativo pode ler sono, refeições, hidratação, atividade e frequência cardíaca para incluí-los no relatório. Nada é lido sem a sua autorização, e nada nunca é escrito no Saúde.

ENTRE OS RESPONSÁVEIS
O acompanhamento pode ser compartilhado entre dois aparelhos, pelo seu próprio iCloud. O convite passa somente por AirDrop: os dois telefones precisam estar lado a lado.

ÁREA DO ASSOCIADO
Sua associação, suas doações e seus recibos fiscais, as publicações reservadas aos associados. Entrada por código de uso único, sem senha, protegida pelo Face ID.

LOCAIS RETT FRIENDLY
O diretório dos locais que acolhem bem, mantido pelas próprias famílias: entrar sem degrau, trocar um adulto deitado, ficar num canto longe do barulho. No mapa ou em lista. Você pode deixar a sua avaliação, ou dar a conhecer um local ausente colocando um alfinete onde você está.

SEUS DADOS
O acompanhamento — crises, medicamentos, sintomas, dados do Apple Saúde — nunca sai do seu aparelho nem do seu iCloud pessoal. Nenhum servidor da AFSR o recebe. Nenhuma medição de audiência, nenhum relator de falhas, nenhuma publicidade, nenhuma dependência de terceiros. A área do associado, essa sim, conversa com afsr.fr para o que diz respeito à associação: sua identidade, sua associação, suas doações.

UMA OBSERVAÇÃO IMPORTANTE
O RettApp é uma ferramenta de acompanhamento destinada a cuidadores. Não constitui um dispositivo médico no sentido do regulamento europeu 2017/745, não substitui a avaliação de um profissional de saúde e não recomenda nenhuma dose. Em caso de emergência, ligue para o número de emergência local.

SOBRE A AFSR
A Associação Francesa da Síndrome de Rett acompanha desde 1988 as famílias afetadas por essa doença neurológica rara, que atinge quase exclusivamente meninas. O RettApp é gratuito, sem publicidade, financiado por doações. afsr.fr
```

---

## 5. Nouveautés

Le champ « Nouveautés » est attaché à la **version**, pas au build : un build de plus sur
la 1.9 ne rouvre pas le champ. Les textes des trois langues sont dans
[`APP_STORE_WHATS_NEW.md`](APP_STORE_WHATS_NEW.md).

---

## 6. Captures d'écran

**Parti pris retenu le 14 novembre 2026 : captures brutes.** Pas de cadre d'iPhone, pas
de légende incrustée, pas de fond coloré. L'écran tel qu'il est.

Conséquence à assumer : la **première** capture doit se comprendre seule, puisque rien
ne l'explique. C'est pour cela que le Journal vient avant le chronomètre.

### Tailles à fournir

L'app est universelle (`TARGETED_DEVICE_FAMILY = 1,2`), donc l'iPad est **obligatoire**,
pas optionnel.

| Taille | Résolution portrait | Appareil qui la donne |
|---|---|---|
| iPhone 6,9" | 1290 × 2796 ou 1320 × 2868 | iPhone 15 Pro Max / 16 Pro Max |
| iPad 13" | 2048 × 2732 ou 2064 × 2752 | iPad Pro 12,9" / 13" |

Apple dérive les tailles inférieures de celles-ci. **Vérifiez quand même dans App Store
Connect au moment de téléverser** : ces exigences changent d'une année sur l'autre, et ce
document peut avoir pris du retard.

10 captures au maximum par taille et par langue. Les trois premières sont celles qui
paraissent dans les résultats de recherche.

### L'ordre

| # | Écran | Pourquoi là |
|---|---|---|
| 1 | **Journal**, une journée remplie | Montre ce qu'est l'app en une image : une journée d'enfant, notée. Se comprend sans légende. |
| 2 | **Chronomètre de crise en cours** | Le moment qui décide du téléchargement, pour un parent qui vient de vivre une crise. |
| 3 | **Bilan**, vue mois, graphiques remplis | Répond à « et après ? » : ce que les notes deviennent. |
| 4 | **Plan médicamenteux du jour**, groupé par moment | La seconde raison d'ouvrir l'app tous les jours. |
| 5 | **Rapport PDF**, aperçu | L'argument pour le rendez-vous médical. |
| 6 | **Annuaire des lieux**, carte avec épingles | La nouveauté, et la seule fonction visible par la communauté entière. |
| 7 | **Espace adhérent**, accueil connecté | Pour les adhérents, qui viennent par la newsletter. |
| 8 | **Actualités** | Montre que l'app vit, même sans suivi médical. |

Huit suffisent. Les deux dernières places restent libres si un écran manque à l'appel.

### Avant de capturer

- **Aucune donnée réelle d'enfant.** Ni prénom, ni date de naissance, ni photo. Les
  captures restent publiques des années.
- **Mode clair**, pour tout le jeu. Un jeu qui alterne clair et sombre paraît bâclé.
- **Barre d'état propre** : le simulateur en donne une (heure fixe, batterie pleine, pas
  d'opérateur). Sur appareil réel, désactivez les notifications et visez une heure ronde.
- **Même état de données** d'une capture à l'autre : si le Journal montre trois crises au
  mois, le Bilan doit en montrer trois.
- Sur le plan médicamenteux, des noms de médicaments plausibles conviennent — mais rien
  qui ressemble à une **recommandation de dose**, qui est ce que la revue d'Apple
  regarde sur une app de catégorie Medical.
- L'écran de don n'apparaît **pas** dans la fiche : il renvoie vers Safari tant que le
  don n'est pas actif dans l'app.

### Ce que je ne peux pas faire

Il n'y a pas de macOS dans les sessions Claude de ce dépôt : ni simulateur, ni capture.
Les images sont à produire sur un Mac ou un iPhone. Tout le reste de ce document ne
dépend pas d'elles.

---

## 7. Catégories et URL

| Type | Choix |
|---|---|
| Catégorie principale | **Medical** |
| Catégorie secondaire | Health & Fitness |

Choisir Medical déclenche le déclaratif « Regulated medical device » (§9).

Toutes les URL ci-dessous ont été vérifiées en production le 14 novembre 2026 : elles
répondent 200.

| Champ | URL |
|---|---|
| Privacy Policy (fr) | `https://afsr.fr/rettapp/confidentialite` |
| Privacy Policy (en) | `https://afsr.fr/rettapp/privacy-policy` |
| Privacy Policy (pt-BR) | `https://afsr.fr/rettapp/politica-de-privacidade` |
| Support URL | `https://afsr.fr/rettapp` |
| Marketing URL | `https://afsr.fr/rettapp` |

> Le pare-feu d'afsr.fr répond 403 à tout agent `curl/*`. Pour contrôler une URL depuis
> une session, passez un User-Agent de navigateur — sinon on croit le site cassé.

---

## 8. Confidentialité — étiquettes App Store

> ⚠️ Cette section est **entièrement refaite**. La précédente déclarait des données de
> santé et un identifiant Sign in with Apple. Les deux étaient faux, et le premier
> contredisait `PrivacyInfo.xcprivacy`.

### Le principe qu'Apple applique

Une donnée est « collectée » quand elle **sort de l'appareil**. Une donnée qui reste
locale, ou qui ne va que dans l'iCloud personnel de l'utilisateur, ne l'est pas.

C'est pourquoi les crises, les médicaments, les symptômes et ce qui est lu dans Apple
Santé **ne se déclarent pas** : ils ne sortent pas. Les déclarer dirait que l'AFSR les
détient, ce qui est faux, et pire que de les omettre.

### Ce qui se déclare

Ce sont exactement les six entrées de `RettApp/Resources/PrivacyInfo.xcprivacy`. Les deux
documents doivent concorder : Apple compare.

| Catégorie | Type | Lié à l'utilisateur | Pistage | Finalité |
|---|---|---|---|---|
| Contact Info | Name | Oui | Non | App Functionality |
| Contact Info | Email Address | Oui | Non | App Functionality |
| Contact Info | Physical Address | Oui | Non | App Functionality |
| Contact Info | Phone Number | Oui | Non | App Functionality |
| Identifiers | User ID | Oui | Non | App Functionality |
| Location | **Precise Location** | Oui | Non | App Functionality |

Les cinq premières viennent de l'espace adhérent, qui lit et écrit la fiche de l'adhérent
chez afsr.fr. La position précise vient de l'épingle posée sur un lieu Rett friendly :
elle part avec l'avis, comme emplacement du lieu.

> La position est la ligne qu'on oublie. Tant qu'elle ne servait qu'à centrer la carte,
> elle ne sortait pas. Depuis l'épingle, elle sort. Voir
> `.claude/rules/promesses-confidentialite.md`.

### Pistage

**No, this app does not track.** Aucune dépendance tierce dans le projet, aucune mesure
d'audience, aucun rapporteur d'incidents, aucune publicité.

### Ce que la fiche affichera

- Data Used to Track You : *None*
- Data Linked to You : *Contact Info · Identifiers · Location*
- Data Not Linked to You : *None*

---

## 9. Âge et dispositif médical

### Age Rating

Toutes les réponses à *None* / *No*, sauf :

| Question | Réponse |
|---|---|
| Medical/Treatment Information | **Infrequent/Mild** |
| Unrestricted Web Access | **No** |

→ Classification attendue : **4+**.

L'app ouvre des pages d'afsr.fr dans Safari (don, politique de confidentialité). Ce ne
sont pas des URL arbitraires saisissables par l'utilisateur, donc « Unrestricted Web
Access » reste *No*.

### Regulated medical device

| Juridiction | Réponse |
|---|---|
| UE / EEE | **No** |
| Royaume-Uni | **No** |
| États-Unis | **No** |

Aucune certification CE, UKCA ou FDA. Justification complète dans `SECURITY.md`.

---

## 10. Notes au reviewer

> Champ *App Review Information → Notes*, lu par le reviewer seul. Refait : l'ancienne
> version décrivait Sign in with Apple et un module de suivi du regard qui n'existent pas.

```
Bonjour,

RettApp est l'application de l'Association Française du Syndrome de Rett (AFSR), loi 1901, fondée en 1988. Elle s'adresse aux parents et aidants d'enfants atteints d'une maladie neurologique rare.

1. AUCUN COMPTE N'EST NÉCESSAIRE POUR LA REVUE
L'application s'ouvre sans compte. Au premier lancement, choisissez « Découvrir l'AFSR » pour voir les actualités et l'espace adhérent, ou « Suivre mon enfant » pour créer un profil local et accéder au journal, aux crises, aux médicaments et au bilan. Aucune donnée n'est demandée en ligne.

2. L'ESPACE ADHÉRENT
L'onglet « Adhérent » demande un compte d'adhérent de l'association. La connexion se fait par code à usage unique envoyé par SMS ou courriel — il n'y a pas de mot de passe, et pas de Sign in with Apple. Si vous souhaitez voir l'intérieur de cet espace, écrivez-nous à contact@afsr.fr et nous ouvrirons un compte de test pour la durée de la revue. L'annuaire des lieux Rett friendly se trouve dans cet espace.

3. LES DONNÉES DE SUIVI NE SORTENT PAS
Les crises, les médicaments, les symptômes et ce qui est lu dans Apple Santé restent sur l'appareil (SwiftData) et, si la famille partage le suivi avec l'autre parent, dans son iCloud personnel (CloudKit). Aucun serveur de l'AFSR ne les reçoit. C'est ce que déclarent PrivacyInfo.xcprivacy et la politique de confidentialité.

4. HEALTHKIT EST LU, JAMAIS ÉCRIT
L'autorisation est demandée à la première ouverture de l'écran Santé, jamais au lancement. Types lus : sommeil, hydratation, alimentation, pas, énergie dépensée, rythme cardiaque. Rien n'est écrit : l'API d'iOS 17 n'expose aucun type pour les crises d'épilepsie.

5. LOCALISATION
Demandée uniquement quand un adhérent pose une épingle pour faire connaître un lieu accessible. Un seul relevé, à sa demande. Aucun suivi de déplacement.

6. CAMÉRA
Utilisée pour photographier le cahier de suivi papier rempli par l'école ou le centre, et le réimporter par reconnaissance de caractères. Le traitement a lieu sur l'appareil et la photo est effacée ensuite. Aucune caméra à détection de profondeur, aucune donnée faciale.

7. PAS DE DISPOSITIF MÉDICAL
RettApp n'est pas un dispositif médical régulé (aucune certification CE, UKCA ou FDA). Un avertissement est affiché à la création du profil et reste accessible dans les Réglages. L'application ne diagnostique pas, ne traite pas, et ne recommande aucune dose.

8. DONNÉES DE SANTÉ DE MINEURS
L'écran de création du profil avertit explicitement que ces données concernent un mineur et qu'un consentement parental est requis.

Politique de confidentialité : https://afsr.fr/rettapp/confidentialite
Contact : contact@afsr.fr

Merci pour votre revue.
```

### Champs voisins

- *Sign-in required* : **No** — l'app s'ouvre sans compte.
- *This app uses Sign in with Apple* : **No**.
- Compte de démonstration : aucun à fournir d'office. La note ci-dessus propose d'en
  ouvrir un si le reviewer veut voir l'espace adhérent. **Si vous préférez en fournir un
  d'avance**, créez-le côté site et renseignez-le ici : cela évite un aller-retour.

---

## 11. Outils de promotion

### Ce qui est déjà préparé

Les **pages de produit personnalisées** sont documentées à part, dans
`APP_STORE_CUSTOM_PRODUCT_PAGES.md` (PR #62). Quatre pages y sont décrites, chacune avec
sa propre URL à mettre dans une newsletter ou un QR code. Deux corrections à y porter
avant usage : la page 4 montre l'écran de don, qui est écarté de la fiche ; et les
légendes incrustées qu'elle suppose ne s'appliquent plus, puisque les captures sont
brutes.

### Ce qui vaut la peine, dans l'ordre

| Outil | Ce que ça fait | Effort |
|---|---|---|
| **Pages de produit personnalisées** | Jusqu'à 70 pages, chacune avec son URL et ses captures. Une pour la newsletter adhérents, une pour les réseaux, une pour les neuropédiatres. Mesurable dans App Analytics. | Moyen — demande une revue Apple par page, sans nouvelle build |
| **Badge et QR code officiels** | Le badge « Télécharger dans l'App Store » aux bonnes proportions, dans les trois langues, et un QR vers la fiche. Générés sur `toolbox.marketingtools.apple.com`. À poser sur afsr.fr/rettapp, dans la newsletter, sur les affiches de congrès. | Faible — quinze minutes |
| **Optimisation de page produit (A/B)** | Teste jusqu'à trois variantes d'icône, de captures ou d'aperçu vidéo sur du trafic réel. Utile le jour où vous hésitez entre deux icônes. | Faible une fois les captures faites |
| **App Analytics → Product Page** | Impressions, téléchargements, taux de conversion, par page et par source. C'est ce qui dit si une campagne a servi. | Nul — c'est de la lecture |
| **Événements intégrés (In-App Events)** | Encarts événementiels dans l'App Store. Pensables pour la **Journée internationale du syndrome de Rett**, si l'app porte ce jour-là un contenu réel (une actualité dédiée, par exemple) — Apple refuse un événement qui n'existe pas dans l'app. | Moyen, et conditionné |

### Ce qui ne s'applique pas

- **Codes promotionnels** : l'app est gratuite, il n'y a rien à offrir.
- **Apple Search Ads** : un budget publicitaire, décision de l'association, hors de ce document.
- **Aperçus vidéo** : possibles, mais ils demandent une capture vidéo propre de l'app, soit
  plus de travail que les huit captures — à garder pour plus tard.

### Du côté d'afsr.fr

La page `afsr.fr/rettapp` est déjà la Support URL et la Marketing URL de la fiche. C'est
elle qui doit porter le badge App Store et, le moment venu, les liens vers les pages de
produit personnalisées. Le lien court de la fiche est de la forme
`https://apps.apple.com/app/id<identifiant>` — il se trouve dans App Store Connect, et
c'est lui qu'il faut partager plutôt qu'une URL de recherche.

---

## 12. Checklist

Avant *Submit for Review* :

- [ ] **Relire la fiche en ligne** et en retirer Sign in with Apple et le jeu du regard
- [ ] Nom et sous-titre dans les trois langues (§1)
- [ ] Mots-clés dans les trois langues (§2)
- [ ] Texte promotionnel dans les trois langues (§3)
- [ ] Description dans les trois langues (§4)
- [ ] Nouveautés dans les trois langues (`APP_STORE_WHATS_NEW.md`)
- [ ] 8 captures iPhone 6,9" et 8 captures iPad 13", sans donnée réelle d'enfant (§6)
- [ ] Icône 1024 × 1024 — le dégradé magenta et violet
- [ ] Les trois URL de politique de confidentialité, une par langue (§7)
- [ ] Étiquettes de confidentialité **conformes à `PrivacyInfo.xcprivacy`** (§8)
- [ ] Age Rating, dont Medical/Treatment Information à *Infrequent/Mild* (§9)
- [ ] Regulated medical device → *No* dans les trois juridictions (§9)
- [ ] Notes au reviewer, version refaite (§10)
- [ ] *Sign-in required* → **No**
- [ ] Copyright : `© 2026 Association Française du Syndrome de Rett`
- [ ] Numéro de build **supérieur au dernier reçu** — à lire dans App Store Connect, pas
      à déduire du générateur
- [ ] Le type d'enregistrement CloudKit `Tombstone` déployé en **production**
