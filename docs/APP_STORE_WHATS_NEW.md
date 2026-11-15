# Nouveautés — RettApp

Le champ « Nouveautés » d'App Store Connect est attaché à la **version**, pas au build :
un build de plus sur la 1.9 ne le rouvre pas. Le remplacer suppose de soumettre une
nouvelle version.

Limite : 4 000 caractères par langue. Les longueurs ci-dessous sont mesurées.

Ces textes décrivent la 1.9 **telle qu'elle sera une fois le code de novembre 2026
compilé et envoyé** : l'icône qui change réellement, l'écran d'ouverture au logo de
l'association, l'onglet adhérent toujours visible. Ne les collez pas pour un build
antérieur.

---

# Version suivante — travaux du 14 au 15 novembre 2026

**Avant de coller ceci, deux vérifications.**

1. **Le numéro de version.** Le champ « Nouveautés » est attaché à la version. La 1.9
   étant publiée, un build de plus ne le rouvre pas : il faut une **nouvelle version
   marketing** (1.9.1 ou 1.10). Elle se change dans `scripts/generate_xcodeproj.rb`,
   jamais dans Xcode, et c'est une décision de publication — voir
   `.claude/rules/xcodeproj.md`.
2. **Ce que contenait déjà le build 14.** Les blocs de la section « 1.9 » ci-dessous
   (espace adhérent en onglet, annuaire des lieux, corbeille, choix de l'icône) n'ont
   pas forcément été publiés. S'ils ne l'ont pas été, **reprenez-les à la suite** du
   texte ci-dessous : la liste n'a de sens que pour qui découvre l'une et l'autre.

## Français

*1 683 caractères sur 4 000*

```
Le Bilan sait maintenant croiser votre journal avec les crises et les symptômes. La carte « Facteurs associés » regarde les trois derniers mois et vous dit, en toutes lettres, ce qui va souvent ensemble : le sommeil de la veille, l'hydratation, les repas, le transit, la dose prévue d'un traitement. Elle se tait tant qu'elle n'a pas de quoi conclure, et chaque phrase rappelle qu'un lien n'est pas une cause — on ne modifie jamais un traitement sans son médecin. Un écran d'aide explique ce qu'elle compare, et ce qu'on ne peut pas en conclure.

Vous choisissez désormais quels graphiques le Bilan affiche, et dans quel ordre.

Le journal accueille le suivi des selles et des urines, reporté jusqu'au cahier de suivi de l'école et au compte rendu pour le médecin.

Vous pouvez supprimer une entrée directement depuis le journal : comme les crises et les médicaments, elle part en corbeille et reste récupérable trente jours.

Entre parents, le partage se lit enfin des deux côtés. Chaque entrée porte le prénom de celui qui l'a notée, et le parent invité voit qu'il reçoit bien les données de l'autre. Une invitation acceptée alors que l'application était fermée ne se perd plus.

Changer le dosage d'un traitement en cours propose d'arrêter l'ancien plan et d'en créer un nouveau, pour que le changement reste daté — et comparable.

Le QR du cahier de suivi s'imprime plus net et se lit dans de moins bonnes conditions. S'il résiste malgré tout, l'application retrouve la page dans la liste des cahiers qu'elle a imprimés.

Le rapport de diagnostic du partage ne contient plus aucun lien d'invitation : il peut être envoyé à l'assistance sans ouvrir l'accès au dossier de l'enfant.
```

## Anglais

*1 582 caractères sur 4 000*

```
The overview can now cross-reference your journal with seizures and symptoms. The "Associated factors" card looks at the last three months and tells you in plain words what tends to go together: the previous night's sleep, hydration, meals, bowel and bladder, a treatment's planned dose. It stays silent until it has enough to say anything, and every sentence is a reminder that a link is not a cause — never change a treatment without your doctor. A help screen explains what it compares, and what you cannot conclude from it.

You now choose which charts the overview shows, and in what order.

The journal gains bowel and bladder tracking, carried through to the school follow-up booklet and to the report for your doctor.

You can delete an entry straight from the journal: like seizures and medications, it goes to the bin and stays recoverable for thirty days.

Between parents, sharing finally reads the same from both sides. Each entry carries the first name of whoever recorded it, and the invited parent can see they are receiving the other's data. An invitation accepted while the app was closed is no longer lost.

Changing the dose of an ongoing treatment now offers to stop the old plan and start a new one, so the change stays dated — and comparable.

The follow-up booklet's QR code prints more sharply and reads in poorer conditions. If it still resists, the app can find the page in the list of booklets it has printed.

The sharing diagnostic report no longer contains any invitation link: it can be sent to support without opening access to your child's records.
```

## Portugais (Brésil)

*1 588 caractères sur 4 000*

```
O balanço agora cruza o seu diário com as crises e os sintomas. O cartão «Fatores associados» analisa os últimos três meses e diz, por extenso, o que costuma aparecer junto: o sono da véspera, a hidratação, as refeições, o trânsito intestinal, a dose prevista de um tratamento. Ele fica em silêncio enquanto não tiver com que concluir, e cada frase lembra que uma relação não é uma causa — nunca altere um tratamento sem o seu médico. Uma tela de ajuda explica o que ele compara, e o que não se pode concluir.

Agora você escolhe quais gráficos o balanço mostra, e em que ordem.

O diário recebe o acompanhamento das fezes e da urina, levado até o caderno de acompanhamento da escola e o relatório para o médico.

Você pode excluir um registro direto do diário: como as crises e os medicamentos, ele vai para a lixeira e fica recuperável por trinta dias.

Entre os pais, o compartilhamento enfim se lê dos dois lados. Cada registro traz o primeiro nome de quem o anotou, e o pai convidado vê que está mesmo recebendo os dados do outro. Um convite aceito com o aplicativo fechado não se perde mais.

Alterar a dose de um tratamento em curso passa a propor encerrar o plano antigo e criar um novo, para que a mudança fique datada — e comparável.

O QR do caderno de acompanhamento é impresso com mais nitidez e se lê em condições piores. Se ainda assim resistir, o aplicativo encontra a página na lista dos cadernos que imprimiu.

O relatório de diagnóstico do compartilhamento não contém mais nenhum link de convite: pode ser enviado ao suporte sem abrir o acesso ao prontuário da criança.
```

### Ce qui a été écarté de ces textes

- **Les correctifs invisibles** : avertissements du build, navigation des lieux réparée,
  rôle de partage persisté. Une note de version n'est pas un journal de commits.
- **« Analyse statistique »** pour la carte Facteurs associés. Le mot promet une rigueur
  que les garde-fous assurent mais que personne ne vérifiera, et il invite à décider
  d'un traitement sur une corrélation. « Ce qui va souvent ensemble » dit la même chose
  sans la promesse.
- **Le repli du cahier présenté comme une garantie.** Il ne vaut que pour les cahiers
  imprimés à partir de cette version : le dire « retrouve la page dans la liste des
  cahiers qu'elle a imprimés » est exact, « retrouve toujours la page » ne l'était pas.

---

## Français

*1478 caractères sur 4 000*

```
L'application s'ouvre désormais à tous, sans créer de suivi : actualités de l'AFSR, espace adhérent et soutien à l'association sont accessibles directement.

L'espace adhérent est désormais un onglet, présent même avant de vous connecter.

Dans votre espace adhérent, l'annuaire des lieux Rett friendly : à parcourir sur une carte ou dans une liste. Vous y lisez ce que d'autres familles ont constaté sur place — entrer sans marche, changer un adulte allongé, s'installer à l'écart du bruit — et vous pouvez donner votre avis, ou faire connaître un lieu absent en posant une épingle là où vous êtes.

Les crises et les médicaments supprimés passent en corbeille et restent récupérables trente jours. Une suppression faite par un parent ne peut plus réapparaître chez l'autre, même après la restauration d'une sauvegarde plus ancienne.

Le bilan vous dit ce que vos données montrent, en toutes lettres, plutôt que de vous laisser seul devant quatre graphiques.

Le journal sépare ce que vous notez de ce que vous ouvrez : un bouton pour chaque intention.

Un médicament pris plusieurs fois par jour se configure d'un geste, aux heures des repas, au lieu d'une prise à la fois.

Vous pouvez choisir l'icône de l'application dans les Réglages : elle change sur l'écran d'accueil et en haut des Actualités.

Les appareils connectés à votre espace adhérent portent maintenant un nom reconnaissable, pour savoir lequel révoquer, et un lien vers l'assistance a été ajouté aux Réglages.
```

---

## Anglais

*1301 caractères sur 4 000*

```
The app now opens to everyone, with no tracking to set up: AFSR news, the member area and ways to support the association are available straight away.

The member area is now a tab of its own, there even before you sign in.

In your member area, the directory of Rett friendly places: on a map or as a list. You can read what other families found on the spot — step-free entry, room to change an adult lying down, somewhere quiet away from the crowd — and you can leave your own review, or make an unlisted place known by dropping a pin where you are.

Deleted seizures and medications go to a bin and stay recoverable for thirty days. A deletion made by one parent can no longer reappear on the other's device, even after an older backup is restored.

The overview now tells you what your data shows, in plain words, instead of leaving you alone with four charts.

The journal separates what you record from what you open — one button for each.

A medication taken several times a day is set up in one tap, at mealtimes, instead of one dose at a time.

You can choose the app icon in Settings: it changes on the Home Screen and at the top of News.

Devices signed in to your member area now carry a recognisable name, so you know which one to revoke, and a link to support has been added to Settings.
```

---

## Portugais (Brésil)

*1415 caractères sur 4 000*

```
O aplicativo agora abre para todos, sem precisar criar um acompanhamento: notícias da AFSR, área do associado e apoio à associação ficam acessíveis de imediato.

A área do associado agora é uma aba própria, presente mesmo antes de você entrar.

Na sua área do associado, o diretório de locais Rett friendly: no mapa ou em lista. Você lê o que outras famílias constataram no local — entrar sem degrau, trocar um adulto deitado, ficar num canto longe do barulho — e pode deixar a sua avaliação, ou dar a conhecer um local ausente colocando um alfinete onde você está.

Crises e medicamentos excluídos vão para a lixeira e podem ser recuperados por trinta dias. Uma exclusão feita por um dos responsáveis não volta mais a aparecer no aparelho do outro, mesmo depois de restaurar uma cópia de segurança mais antiga.

O balanço passa a dizer o que seus dados mostram, em palavras claras, em vez de deixar você sozinho diante de quatro gráficos.

O diário separa o que você registra do que você abre — um botão para cada intenção.

Um medicamento tomado várias vezes ao dia é configurado em um toque, nos horários das refeições, em vez de uma dose por vez.

Você pode escolher o ícone do aplicativo nos Ajustes: ele muda na Tela de Início e no topo das Notícias.

Os aparelhos conectados à sua área do associado agora têm um nome reconhecível, para saber qual revogar, e foi adicionado um link para o suporte nos Ajustes.
```
