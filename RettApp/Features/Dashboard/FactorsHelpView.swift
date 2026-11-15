import SwiftUI

/// Explique la carte « Facteurs associés » à une famille.
///
/// Une phrase comme « les jours où l'humeur est plus basse, il y a plus de
/// crises » se lit trop facilement comme une cause, ou comme une consigne.
/// Cet écran dit ce que l'application compare, pourquoi elle se tait parfois,
/// et ce qu'on ne peut pas en conclure.
///
/// Les nombres cités viennent des constantes de `JournalFactors` : écrits en
/// dur ici, ils deviendraient faux au premier réglage d'un seuil.
struct FactorsHelpView: View {
    var body: some View {
        List {
            Section {
                Text("Cette carte cherche, dans votre journal, ce qui revient souvent les jours où il y a des crises ou des symptômes. C'est une aide pour repérer des pistes et préparer une consultation, pas un diagnostic.")
            }

            Section("Ce qui est comparé") {
                point("book.closed.fill", "Le journal",
                      "Qualité et durée du sommeil de nuit, repas, hydratation, selles, urines, humeur et observance générale.")
                point("pill.fill", "Le plan médicamenteux",
                      "Pour chaque médicament pris à heures fixes : la dose quotidienne prévue, et la part des prises réellement faites.")
                point("waveform.path.ecg", "Ce qu'on cherche à expliquer",
                      "Le nombre de crises, le temps passé en crise, et chaque symptôme que vous suivez.")
                point("calendar", "Le jour même, ou la veille",
                      "Une mauvaise nuit ou un oubli se paient parfois le lendemain : chaque lien est cherché les deux façons, et seul le plus net est gardé.")
            }

            Section("Comment lire une phrase") {
                Text("« Les jours où la qualité du sommeil de nuit est plus bas, il y a plus de crises. »")
                    .font(AFSRFont.body(15)).italic()
                Text("Cela veut dire : sur la période regardée, les nuits notées plus bas sont souvent suivies de journées avec plus de crises. Sous la phrase, l'application indique la force du lien (modérée ou forte) et le nombre de jours sur lequel il repose.")
            }

            Section("Pourquoi la carte reste parfois vide") {
                Text("Mieux vaut ne rien dire que dire une chose fausse. Le hasard fait apparaître de faux liens, surtout quand on compare beaucoup de choses à la fois. Un lien n'est donc montré que si :")
                bullet("il repose sur au moins \(JournalFactors.minimumDays) jours où les deux informations sont notées ;")
                bullet("la crise ou le symptôme est survenu au moins \(JournalFactors.minimumDaysWithOutcome) jours différents — un épisode isolé ne fait pas une tendance ;")
                bullet("le lien est au moins modéré, et peu probable par pur hasard ;")
                bullet("il s'appuie sur les \(JournalFactors.lookbackDays) derniers jours, quelle que soit l'échelle choisie en haut du Bilan.")
                Text("Une case non remplie n'est jamais comptée comme « zéro » : le jour est simplement écarté. Plus le journal est tenu régulièrement, plus la carte a de chances de dire quelque chose.")
            }

            Section("Un lien n'est pas une cause") {
                Text("Deux choses qui varient ensemble ne sont pas forcément liées l'une à l'autre. Une nuit agitée peut précéder une crise, mais une crise peut aussi perturber la nuit suivante. Une saison, une infection, une poussée de croissance peuvent jouer sur les deux à la fois.")
                Text("Ces phrases sont des pistes à en parler avec l'équipe soignante, pas des conclusions.")
            }

            Section("Le plan médicamenteux") {
                Text("Pour qu'un changement de dosage puisse être comparé, il faut qu'il soit daté. C'est pourquoi, quand vous changez la dose ou les horaires d'un médicament, l'application vous propose d'arrêter l'ancien plan et d'en créer un nouveau : chacun garde sa date, et le « avant » et le « après » restent lisibles. Les deux plans portant le même nom sont regroupés dans l'analyse.")
                Text("Les médicaments pris à la demande ne sont pas comparés : on les prend à cause d'une crise ou d'un symptôme, pas l'inverse. Les croiser ferait croire qu'ils les provoquent.")
                Label("Ne modifiez jamais un traitement à cause de cette carte. Toute décision se prend avec le médecin.", systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.afsrWarning)
            }

            Section("Vos données") {
                Text("Tout est calculé sur cet iPhone. Rien de cette analyse n'est envoyé à l'AFSR ni ailleurs.")
            }
        }
        .navigationTitle("Comprendre les facteurs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func point(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.afsrPurpleAdaptive)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AFSRFont.headline(15))
                Text(text).font(AFSRFont.body(14)).foregroundStyle(.secondary)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}
