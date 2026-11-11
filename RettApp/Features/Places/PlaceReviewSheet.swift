import SwiftUI

/// Laisser un avis sur un lieu.
///
/// ## Pourquoi ce n'est pas un formulaire
///
/// La première version était un `Form` avec ses sections grises et ses
/// contrôles segmentés : l'écran des Réglages, pas un avis qu'on laisse. Or
/// personne n'apprend à noter un lieu — on l'a fait dans Plans ou dans Google
/// Maps, et on s'attend aux mêmes gestes. Celui-ci les reprend : des étoiles
/// qu'on balaie, des pastilles qu'on touche, un « Publier » dans la barre qui
/// s'allume quand c'est prêt.
///
/// L'ordre aussi est le leur, et il n'est pas arbitraire : la note d'abord,
/// parce que c'est ce qu'on vient faire et que c'est le seul champ obligatoire ;
/// le texte libre en dernier, parce que la plupart des gens ne l'écriront pas,
/// et qu'un formulaire qui s'ouvre sur un grand cadre vide décourage avant
/// d'avoir commencé.
///
/// ## Ce qui reste propre à l'AFSR
///
/// Les pastilles ne sont pas des étiquettes d'ambiance (« bon pour les
/// groupes ») mais des **constats** vérifiables, et elles ont trois états et
/// non deux : on a pu, on n'a pas pu, on n'a pas essayé. Cette troisième
/// réponse est celle qui manque partout ailleurs, et c'est la plus honnête —
/// une famille qui n'a pas demandé les toilettes adaptées ne doit pas peser
/// dans leur décompte.
struct PlaceReviewSheet: View {
    let session: MemberSession
    let place: Context
    let existing: MyPlaceReview?
    var onDone: (() async -> Void)?

    /// Le lieu noté, et ce qu'il faut pour le créer s'il est proposé.
    struct Context {
        var establishmentID: String?
        var name: String
        var subtitle: String?
        var criteria: [PlaceCriterion]
        /// Renseigné seulement quand le lieu n'est pas encore dans
        /// l'annuaire : ces champs voyagent avec l'avis, et le site crée la
        /// fiche en brouillon.
        var proposal: Proposal?

        struct Proposal {
            var type: String
            var address: String = ""
            var postalCode: String = ""
            var city: String = ""
            var website: String = ""
            /// Le point posé sur la carte, s'il y en a un.
            var latitude: Double?
            var longitude: Double?
        }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var note = 0
    @State private var reponses: [String: CriterionAnswer] = [:]
    @State private var temoignage = ""
    @State private var moisVisite: Int?
    @State private var anneeVisite: Int?
    @State private var atteste = false
    @State private var afficherDepartement = false

    @State private var envoi = false
    @State private var erreurGenerale: String?
    @State private var erreursChamps: [String: String] = [:]

    private static let temoignageMax = 2000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                entete
                sectionNote
                if !place.criteria.isEmpty { sectionConstats }
                sectionTemoignage
                sectionVisite
                sectionAttestation
                pied
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.afsrBackground)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(existing == nil ? "Votre avis" : "Modifier mon avis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
                    .disabled(envoi)
            }
            ToolbarItem(placement: .confirmationAction) {
                if envoi {
                    ProgressView()
                } else {
                    Button(existing == nil ? "Publier" : "Enregistrer") {
                        Task { await envoyer() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!pret)
                }
            }
        }
        .interactiveDismissDisabled(envoi)
        .onAppear(perform: preparer)
    }

    // MARK: - Les sections

    private var entete: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.name)
                .font(AFSRFont.headline(22))
            if let sous = place.subtitle, !sous.isEmpty {
                Text(sous)
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionNote: some View {
        VStack(spacing: 12) {
            Text("Quel accueil avez-vous reçu ?")
                .font(AFSRFont.headline(17))
                .frame(maxWidth: .infinity, alignment: .leading)

            StarRatingPicker(rating: $note)

            if let message = erreursChamps["rating"] {
                messageErreur(message)
            }

            Text("La note ne porte que sur l'accueil. L'accessibilité, elle, se décrit juste en dessous.")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sectionConstats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Qu'avez-vous pu faire sur place ?")
                .font(AFSRFont.headline(17))

            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(place.criteria) { critere in
                    CriterionChip(
                        question: critere.question,
                        answer: reponses[critere.handle] ?? .inconnu
                    ) {
                        reponses[critere.handle] = (reponses[critere.handle] ?? .inconnu).suivant
                    }
                }
            }

            HStack(spacing: 14) {
                legende(symbole: "questionmark.circle", texte: "Pas essayé", couleur: .secondary)
                legende(symbole: "checkmark.circle.fill", texte: "Oui", couleur: .afsrSuccess)
                legende(symbole: "xmark.circle.fill", texte: "Non", couleur: .afsrEmergency)
            }
            .padding(.top, 2)

            Text("Touchez une pastille pour passer d'une réponse à l'autre. Laissez « pas essayé » si vous n'avez pas eu l'occasion : c'est une réponse en soi, et elle ne compte pas dans les décomptes.")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
        }
    }

    private var sectionTemoignage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Votre témoignage")
                    .font(AFSRFont.headline(17))
                Spacer()
                Text("facultatif")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }

            PromptedTextEditor(
                text: $temoignage,
                prompt: "Ce que vous auriez aimé savoir avant de venir."
            )
            .padding(10)
            .background(Color.afsrSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            HStack {
                if let message = erreursChamps["comment"] {
                    messageErreur(message)
                } else {
                    Text("Lu par les adhérents, après relecture par l'association.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(temoignage.count) / \(Self.temoignageMax)")
                    .font(AFSRFont.caption())
                    .monospacedDigit()
                    .foregroundStyle(temoignage.count > Self.temoignageMax ? .red : .secondary)
            }
        }
    }

    private var sectionVisite: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quand y êtes-vous allé ?")
                .font(AFSRFont.headline(17))

            Menu {
                Button("Je ne sais plus") {
                    moisVisite = nil
                    anneeVisite = nil
                }
                ForEach(Self.moisRecents, id: \.cle) { choix in
                    Button(choix.libelle) {
                        moisVisite = choix.mois
                        anneeVisite = choix.annee
                    }
                }
            } label: {
                HStack {
                    Text(libelleVisite)
                        .foregroundStyle(moisVisite == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.afsrSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .font(AFSRFont.body())

            if let message = erreursChamps["visited_on"] {
                messageErreur(message)
            } else {
                Text("Un mois suffit. Un séjour ancien ne dit plus l'état actuel des lieux, et la fiche le signale.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sectionAttestation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $atteste) {
                Text("J'ai visité ce lieu, et j'accepte que mon prénom apparaisse avec mon avis.")
                    .font(AFSRFont.body())
            }

            Toggle(isOn: $afficherDepartement) {
                Text("Afficher aussi mon département")
                    .font(AFSRFont.body())
            }

            if let message = erreursChamps["engagement"] {
                messageErreur(message)
            } else {
                Text("Cette case n'est pas une formalité : c'est elle qui autorise la publication, et ce que l'association pourra montrer si l'établissement contestait votre avis.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.afsrSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var pied: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let erreurGenerale {
                messageErreur(erreurGenerale)
            }

            Text(existing == nil
                ? "Votre avis part en relecture. Il paraîtra une fois validé par l'association — vous le suivrez dans « Mes avis »."
                : "Un avis modifié repasse en relecture avant d'être publié.")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)

            if let proposition = place.proposal {
                Text("Le lieu que vous proposez sera créé en brouillon : il n'apparaîtra dans l'annuaire qu'après relecture.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)

                if proposition.latitude == nil {
                    Text("Vous ne l'avez pas placé sur la carte : l'association le situera d'après l'adresse, au mieux de ce qu'elle permet.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pièces

    private func legende(symbole: String, texte: String, couleur: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbole).font(.caption2)
            Text(texte).font(AFSRFont.caption())
        }
        .foregroundStyle(couleur)
    }

    private func messageErreur(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(AFSRFont.caption())
            .foregroundStyle(.red)
    }

    // MARK: - État

    /// Prêt à publier : une note, et la case attestée. Le serveur revérifie
    /// tout — ceci n'évite qu'un aller-retour.
    private var pret: Bool {
        note >= 1 && atteste && temoignage.count <= Self.temoignageMax
    }

    private var libelleVisite: String {
        guard let moisVisite, let anneeVisite else { return "Je ne sais plus" }
        return Self.libelle(mois: moisVisite, annee: anneeVisite)
    }

    private func preparer() {
        guard let existing else { return }

        note = existing.rating
        reponses = existing.answers.mapValues { CriterionAnswer($0) }
        temoignage = existing.comment ?? ""
        afficherDepartement = existing.showArea
        // Un avis qu'on modifie a déjà été attesté ; le redemander n'aurait pas
        // de sens, mais le serveur l'exige à chaque envoi.
        atteste = true

        if let visite = existing.visitedOn {
            let morceaux = visite.split(separator: "-").compactMap { Int($0) }
            if morceaux.count == 2 {
                anneeVisite = morceaux[0]
                moisVisite = morceaux[1]
            }
        }
    }

    private func envoyer() async {
        envoi = true
        erreurGenerale = nil
        erreursChamps = [:]

        var brouillon = PlaceReviewDraft()
        brouillon.rating = note
        brouillon.comment = temoignage
        brouillon.showArea = afficherDepartement
        brouillon.engagement = atteste
        brouillon.answers = reponses.compactMapValues(\.valeurEnvoyee)

        if let mois = moisVisite, let annee = anneeVisite {
            brouillon.visitedOn = String(format: "%04d-%02d", annee, mois)
        }

        if let proposition = place.proposal {
            brouillon.mode = .nouveau
            brouillon.name = place.name
            brouillon.establishmentType = proposition.type
            brouillon.address = proposition.address
            brouillon.postalCode = proposition.postalCode
            brouillon.city = proposition.city
            brouillon.website = proposition.website
            brouillon.latitude = proposition.latitude
            brouillon.longitude = proposition.longitude
        } else {
            brouillon.mode = .existant
            brouillon.establishmentID = place.establishmentID
        }

        let chemin = existing.map { "/avis/\($0.id)" } ?? "/avis"

        do {
            let _: PlaceReviewSubmissionResponse = try await session.client.post(
                chemin,
                encoding: brouillon.payload()
            )
            envoi = false
            await onDone?()
            dismiss()
        } catch let erreur as MemberAPIError {
            envoi = false
            if case .validation(let message, let champs) = erreur {
                erreursChamps = champs
                // Un message général seulement si aucun champ n'est désigné,
                // sinon il doublerait ce qui s'affiche déjà sous le champ.
                erreurGenerale = champs.isEmpty ? message : nil
            } else {
                erreurGenerale = erreur.localizedDescription
            }
        } catch {
            envoi = false
            erreurGenerale = MemberAPIError.unreadable.localizedDescription
        }
    }

    // MARK: - Les mois proposés

    /// Les trente-six derniers mois, du plus récent au plus ancien.
    ///
    /// Un menu et non deux roues : on se souvient d'un séjour comme « en août
    /// dernier », pas comme d'un couple mois-année à composer. Au-delà de
    /// trois ans, « je ne sais plus » est de toute façon la réponse honnête.
    private static var moisRecents: [(cle: String, mois: Int, annee: Int, libelle: String)] {
        let calendrier = Calendar.current
        let maintenant = Date()

        return (0..<36).compactMap { recul in
            guard let date = calendrier.date(byAdding: .month, value: -recul, to: maintenant) else { return nil }
            let mois = calendrier.component(.month, from: date)
            let annee = calendrier.component(.year, from: date)
            return (
                cle: "\(annee)-\(mois)",
                mois: mois,
                annee: annee,
                libelle: libelle(mois: mois, annee: annee)
            )
        }
    }

    private static func libelle(mois: Int, annee: Int) -> String {
        var composants = DateComponents()
        composants.year = annee
        composants.month = mois
        composants.day = 1

        guard let date = Calendar.current.date(from: composants) else { return "\(mois)/\(annee)" }

        let formateur = DateFormatter()
        formateur.locale = Locale(identifier: "fr_FR")
        formateur.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formateur.string(from: date).capitalized
    }
}
