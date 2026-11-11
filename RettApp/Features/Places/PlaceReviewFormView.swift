import SwiftUI

/// Déposer ou modifier un avis sur un lieu.
///
/// Deux chemins y mènent, et le formulaire s'adapte sans changer de nature :
/// depuis une fiche, le lieu est connu et la première section n'est qu'un
/// rappel ; depuis l'annuaire, l'adhérent commence par dire si le lieu y
/// figure déjà — et le propose sinon.
///
/// ## Ce que le formulaire ne fait pas
///
/// Il ne juge pas. Les critères sont des **constats** — « avez-vous pu entrer
/// sans marche » se vérifie, « l'hôtel est accueillant » s'apprécie — et seule
/// la note sur 5 porte sur l'accueil ressenti. Cette distinction vient du
/// site, et elle n'est pas cosmétique : une famille qui prépare un séjour a
/// besoin de faits, et l'association répond de ce qu'elle publie sur un
/// commerce nommé.
///
/// ## « Je ne sais pas » n'est pas une réponse
///
/// C'est l'absence de réponse, et c'est ainsi qu'elle part : la clé n'est pas
/// envoyée. Le serveur écarte d'ailleurs tout ce qui n'est ni « oui » ni
/// « non ». Une famille qui n'a pas essayé d'utiliser les toilettes adaptées
/// ne doit pas peser dans le décompte de ce constat.
struct PlaceReviewFormView: View {
    let session: MemberSession
    /// Fourni depuis l'annuaire : sert à choisir un lieu existant et à
    /// recharger la liste après le dépôt.
    let store: PlacesStore?
    /// Fourni depuis une fiche : le lieu est alors fixé.
    let lieu: (id: String, nom: String, criteres: [PlaceCriterion])?
    let existant: MyPlaceReview?
    var onDone: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var brouillon = PlaceReviewDraft()
    @State private var lieuChoisi: Place?
    @State private var choisirLieu = false
    @State private var envoi = false
    @State private var erreurGenerale: String?
    @State private var erreursChamps: [String: String] = [:]
    @State private var annee: Int = Calendar.current.component(.year, from: Date())
    @State private var mois: Int = Calendar.current.component(.month, from: Date())
    @State private var visitePrecisee = false

    private static let commentaireMax = 2000

    var body: some View {
        Form {
            sectionLieu
            if criteresCourants.isEmpty == false { sectionCriteres }
            sectionNote
            sectionTemoignage
            sectionVisite
            sectionEngagement
            sectionEnvoi
        }
        .navigationTitle(existant == nil ? "Partager un lieu" : "Modifier mon avis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
        }
        .sheet(isPresented: $choisirLieu) {
            NavigationStack {
                PlacePickerView(store: store) { choix in
                    lieuChoisi = choix
                    brouillon.establishmentID = choix.id
                    brouillon.mode = .existant
                    choisirLieu = false
                }
            }
        }
        .onAppear(perform: preparer)
        .interactiveDismissDisabled(envoi)
    }

    // MARK: - Le lieu

    @ViewBuilder
    private var sectionLieu: some View {
        if let lieu {
            Section("Le lieu") {
                Label(lieu.nom, systemImage: "mappin.and.ellipse")
            }
        } else {
            Section("Le lieu") {
                Picker("Ce lieu", selection: $brouillon.mode) {
                    Text("Est déjà dans l'annuaire").tag(PlaceReviewDraft.Mode.existant)
                    Text("N'y figure pas encore").tag(PlaceReviewDraft.Mode.nouveau)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if brouillon.mode == .existant {
                Section {
                    Button {
                        choisirLieu = true
                    } label: {
                        HStack {
                            Text(lieuChoisi?.name ?? "Choisir le lieu")
                                .foregroundStyle(lieuChoisi == nil ? Color.accentColor : .primary)
                            Spacer()
                            if let ville = lieuChoisi?.city {
                                Text(ville).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    erreur("establishment_id")
                }
            } else {
                Section("Le lieu que vous proposez") {
                    TextField("Nom", text: $brouillon.name)
                        .textInputAutocapitalization(.words)

                    Picker("Type", selection: $brouillon.establishmentType) {
                        Text("À choisir").tag(String?.none)
                        ForEach(store?.meta?.types ?? []) { type in
                            Text(type.label).tag(Optional(type.key))
                        }
                    }

                    TextField("Adresse", text: $brouillon.address)
                        .textInputAutocapitalization(.words)
                    TextField("Code postal", text: $brouillon.postalCode)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Commune", text: $brouillon.city)
                        .textInputAutocapitalization(.words)
                    TextField("Site web (facultatif)", text: $brouillon.website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                footerProposition
            }
        }
    }

    @ViewBuilder
    private var footerProposition: some View {
        Section {
            EmptyView()
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                erreur("name")
                erreur("establishment_type")
                erreur("city")
                erreur("website")
                Text("La commune suffit à situer le lieu ; l'adresse le situe précisément. Le lieu proposé n'apparaîtra dans l'annuaire qu'après relecture par l'association.")
            }
        }
    }

    // MARK: - Les constats

    private var criteresCourants: [PlaceCriterion] {
        if let lieu { return lieu.criteres }
        if let existant, !existant.criteria.isEmpty { return existant.criteria }
        if brouillon.mode == .nouveau {
            return store?.criteres(pourType: brouillon.establishmentType) ?? []
        }
        return lieuChoisi.flatMap { choix in store?.criteres(pourType: choix.type) } ?? []
    }

    private var sectionCriteres: some View {
        Section {
            ForEach(criteresCourants) { critere in
                VStack(alignment: .leading, spacing: 6) {
                    Text(critere.question)
                        .font(AFSRFont.body())

                    Picker(critere.question, selection: reponse(critere.handle)) {
                        Text("Oui").tag("oui")
                        Text("Non").tag("non")
                        Text("Je ne sais pas").tag("")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Ce que vous avez pu faire sur place")
        } footer: {
            Text("Des constats, pas des appréciations. « Je ne sais pas » ne compte pas : laissez-le si vous n'avez pas essayé.")
        }
    }

    /// Un lien vers la réponse d'un critère. La chaîne vide vaut « je ne sais
    /// pas », et retire la clé : ce qu'on n'a pas constaté ne doit pas peser.
    private func reponse(_ handle: String) -> Binding<String> {
        Binding(
            get: { brouillon.answers[handle] ?? "" },
            set: { nouvelle in
                if nouvelle.isEmpty {
                    brouillon.answers.removeValue(forKey: handle)
                } else {
                    brouillon.answers[handle] = nouvelle
                }
            }
        )
    }

    // MARK: - La note

    private var sectionNote: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { cran in
                    Button {
                        brouillon.rating = cran
                    } label: {
                        Image(systemName: cran <= brouillon.rating ? "star.fill" : "star")
                            .font(.system(size: 26))
                            .foregroundStyle(cran <= brouillon.rating ? Color.afsrWarning : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(cran) sur 5")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        } header: {
            Text("L'accueil que vous avez reçu")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                erreur("rating")
                Text("La note ne porte que sur l'accueil ressenti, pas sur l'accessibilité — celle-ci est décrite par les constats ci-dessus.")
            }
        }
    }

    // MARK: - Le témoignage

    private var sectionTemoignage: some View {
        Section {
            TextEditor(text: $brouillon.comment)
                .frame(minHeight: 120)
                .font(AFSRFont.body())
        } header: {
            Text("Votre témoignage (facultatif)")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                erreur("comment")
                HStack {
                    Text("Ce que vous auriez aimé savoir avant de venir.")
                    Spacer()
                    Text("\(brouillon.comment.count) / \(Self.commentaireMax)")
                        .foregroundStyle(brouillon.comment.count > Self.commentaireMax ? .red : .secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - La visite

    private var sectionVisite: some View {
        Section {
            Toggle("Préciser le mois de ma visite", isOn: $visitePrecisee)

            if visitePrecisee {
                Picker("Mois", selection: $mois) {
                    ForEach(1...12, id: \.self) { numero in
                        Text(Self.nomDuMois(numero)).tag(numero)
                    }
                }
                Picker("Année", selection: $annee) {
                    ForEach(Self.annees, id: \.self) { valeur in
                        Text(String(valeur)).tag(valeur)
                    }
                }
            }
        } header: {
            Text("Quand y êtes-vous allé ?")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                erreur("visited_on")
                Text("Un mois suffit. Un séjour vieux de plusieurs années ne dit plus l'état actuel des lieux, et la fiche le signale.")
            }
        }
    }

    // MARK: - L'engagement

    private var sectionEngagement: some View {
        Section {
            Toggle(isOn: $brouillon.engagement) {
                Text("J'ai visité ce lieu et j'accepte que mon prénom apparaisse avec mon avis.")
                    .font(AFSRFont.body())
            }

            Toggle(isOn: $brouillon.showArea) {
                Text("Afficher aussi mon département")
                    .font(AFSRFont.body())
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                erreur("engagement")
                Text("Ce n'est pas une formalité : c'est ce qui autorise la publication, et ce que l'association pourra montrer si l'établissement contestait votre avis.")
            }
        }
    }

    // MARK: - Envoi

    private var sectionEnvoi: some View {
        Section {
            Button {
                Task { await envoyer() }
            } label: {
                HStack {
                    Spacer()
                    if envoi {
                        ProgressView()
                    } else {
                        Text(existant == nil ? "Déposer mon avis" : "Enregistrer les modifications")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(!complet || envoi)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let erreurGenerale {
                    Label(erreurGenerale, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(AFSRFont.caption())
                }
                Text(existant == nil
                    ? "Votre avis part en relecture : il paraîtra une fois validé par l'association."
                    : "Un avis modifié repasse en relecture avant d'être publié.")
                    .font(AFSRFont.caption())
            }
        }
    }

    /// Ce que l'écran sait vérifier avant d'envoyer. Le serveur revérifie
    /// tout : ceci n'évite qu'un aller-retour, ce n'est pas la règle.
    private var complet: Bool {
        guard brouillon.rating >= 1, brouillon.engagement else { return false }
        guard brouillon.comment.count <= Self.commentaireMax else { return false }

        if lieu != nil || existant != nil { return true }

        switch brouillon.mode {
        case .existant:
            return brouillon.establishmentID != nil
        case .nouveau:
            return !brouillon.name.trimmingCharacters(in: .whitespaces).isEmpty
                && brouillon.establishmentType != nil
                && !brouillon.city.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func envoyer() async {
        envoi = true
        erreurGenerale = nil
        erreursChamps = [:]

        brouillon.visitedOn = visitePrecisee ? String(format: "%04d-%02d", annee, mois) : nil

        let chemin = existant.map { "/avis/\($0.id)" } ?? "/avis"

        do {
            let _: PlaceReviewSubmissionResponse = try await session.client.post(
                chemin,
                encoding: brouillon.payload()
            )
            envoi = false
            await onDone?()
            if let store { await store.charger() }
            dismiss()
        } catch let erreur as MemberAPIError {
            envoi = false
            switch erreur {
            case .validation(let message, let champs):
                erreursChamps = champs
                // Un message général seulement si aucun champ n'est désigné :
                // sinon il doublerait ce qui est déjà affiché sous le champ.
                erreurGenerale = champs.isEmpty ? message : nil
            default:
                erreurGenerale = erreur.localizedDescription
            }
        } catch {
            envoi = false
            erreurGenerale = MemberAPIError.unreadable.localizedDescription
        }
    }

    // MARK: - Pièces

    @ViewBuilder
    private func erreur(_ champ: String) -> some View {
        if let message = erreursChamps[champ] {
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
                .font(AFSRFont.caption())
        }
    }

    /// Reprend l'avis existant, ou part du lieu fourni.
    private func preparer() {
        if let lieu {
            brouillon.mode = .existant
            brouillon.establishmentID = lieu.id
        }

        guard let existant else { return }

        brouillon.mode = .existant
        brouillon.establishmentID = existant.establishmentId
        brouillon.rating = existant.rating
        brouillon.answers = existant.answers
        brouillon.comment = existant.comment ?? ""
        brouillon.showArea = existant.showArea
        // Un avis qu'on modifie a déjà été attesté ; le redemander n'aurait
        // pas de sens, mais le serveur l'exige à chaque envoi.
        brouillon.engagement = true

        if let visite = existant.visitedOn,
           let date = visite.split(separator: "-").compactMap({ Int($0) }) as [Int]?,
           date.count == 2 {
            annee = date[0]
            mois = date[1]
            visitePrecisee = true
        }
    }

    private static var annees: [Int] {
        let courante = Calendar.current.component(.year, from: Date())
        return Array((courante - 12)...courante).reversed()
    }

    private static func nomDuMois(_ numero: Int) -> String {
        var composants = DateComponents()
        composants.year = 2000
        composants.month = numero
        composants.day = 1

        guard let date = Calendar.current.date(from: composants) else { return String(numero) }

        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.setLocalizedDateFormatFromTemplate("MMMM")
        return f.string(from: date).capitalized
    }
}

/// Choisir un lieu de l'annuaire, avec la même recherche que la liste.
struct PlacePickerView: View {
    let store: PlacesStore?
    let onChoix: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recherche = ""

    var body: some View {
        List {
            ForEach(resultats) { lieu in
                Button {
                    onChoix(lieu)
                } label: {
                    PlaceRow(lieu: lieu)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay {
            if resultats.isEmpty {
                ContentUnavailableView {
                    Label("Aucun lieu trouvé", systemImage: "mappin.slash")
                } description: {
                    Text("S'il n'est pas dans l'annuaire, revenez en arrière et choisissez « N'y figure pas encore ».")
                }
            }
        }
        .searchable(text: $recherche, prompt: "Chercher un lieu")
        .navigationTitle("Choisir le lieu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
        }
    }

    /// La recherche se fait ici, sur la liste déjà chargée : on ne relance pas
    /// l'annuaire pour choisir un lieu qu'on a sous les yeux.
    private var resultats: [Place] {
        let lieux = store?.places ?? []
        let terme = recherche.trimmingCharacters(in: .whitespaces)

        guard !terme.isEmpty else { return lieux }

        return lieux.filter {
            $0.name.localizedCaseInsensitiveContains(terme)
                || ($0.city?.localizedCaseInsensitiveContains(terme) ?? false)
        }
    }
}
