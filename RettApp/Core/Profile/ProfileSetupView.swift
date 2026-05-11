import SwiftUI
import SwiftData

/// Onboarding du profil enfant.
///
/// Flux : intro → identité (prénom, nom, sexe) → épilepsie → médicaments → done.
/// Chaque étape (sauf intro et done) a un bouton « Précédent » qui permet
/// de revenir corriger les informations saisies. Tous les libellés sont
/// personnalisés avec le prénom et le genre de l'enfant pour rendre
/// l'expérience plus naturelle (« Léa a-t-elle de l'épilepsie ? » au lieu
/// du générique « L'enfant a de l'épilepsie »).
struct ProfileSetupView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var sex: ChildSex = .unspecified
    @State private var hasEpilepsy: Bool = false
    @State private var initialMedications: [DraftMedication] = []
    @State private var step: Step = .intro
    @State private var disclaimerAcknowledged: Bool = false

    enum Step: Int, CaseIterable { case intro, child, epilepsy, medications, done }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.afsrBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    ProgressView(value: progress)
                        .tint(.afsrPurple)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    Group {
                        switch step {
                        case .intro:        introStep
                        case .child:        childStep
                        case .epilepsy:     epilepsyStep
                        case .medications:  medicationsStep
                        case .done:         doneStep
                        }
                    }
                    .animation(.easeInOut, value: step)
                }
            }
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var progress: Double {
        switch step {
        case .intro:       return 0.1
        case .child:       return 0.3
        case .epilepsy:    return 0.55
        case .medications: return 0.8
        case .done:        return 1.0
        }
    }

    /// Prénom à afficher dans les libellés. Garde « votre enfant » par défaut
    /// si l'utilisateur revient en arrière sans avoir encore saisi le prénom.
    private var childName: String {
        let trimmed = firstName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "votre enfant" : trimmed
    }

    // MARK: - Intro step

    private var introStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "person.2.circle.fill")
                    .resizable().scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundStyle(.afsrPurpleAdaptive)
                    .padding(.top, 24)
                Text("Bienvenue")
                    .font(AFSRFont.title())
                Text("Nous allons configurer le profil de votre enfant.\nCes informations restent sur votre appareil.")
                    .font(AFSRFont.body())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                disclaimerCard

                Toggle(isOn: $disclaimerAcknowledged) {
                    Text("J'ai lu et compris cet avertissement.")
                        .font(AFSRFont.body(15))
                }
                .padding(.horizontal)
                .tint(.afsrPurpleAdaptive)

                AFSRPrimaryButton(title: "Commencer") { step = .child }
                    .padding(.horizontal)
                    .disabled(!disclaimerAcknowledged)
                    .opacity(disclaimerAcknowledged ? 1 : 0.5)
                    .padding(.bottom, 24)
            }
        }
    }

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.afsrWarning)
                Text("Avertissement médical")
                    .font(AFSRFont.headline(16))
            }
            Text("RettApp est un outil de suivi destiné aux parents et aidants. **Ce n'est pas un dispositif médical** au sens du règlement UE 2017/745 (MDR). L'application ne diagnostique pas, ne traite pas et ne remplace pas l'avis d'un professionnel de santé.\n\nEn cas d'urgence, appelez le **15** (Samu) ou le **112**.")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.afsrWarning.opacity(0.12), in: RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius)
                .stroke(Color.afsrWarning.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    // MARK: - Child step

    private var childStep: some View {
        Form {
            Section {
                TextField("Prénom de l'enfant", text: $firstName)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                TextField("Nom de famille de l'enfant (optionnel)", text: $lastName)
                    .textContentType(.familyName)
                    .autocorrectionDisabled()
            } header: {
                Text("Identité de l'enfant")
            } footer: {
                Text("Le nom de famille n'apparaît que dans les documents imprimés. La date de naissance peut être ajoutée plus tard depuis Réglages → Profil.")
            }

            Section {
                Picker("Sexe", selection: $sex) {
                    ForEach(ChildSex.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Sexe")
            } footer: {
                Text("Utilisé uniquement pour adapter les libellés affichés dans l'app (« née » / « né »). Vous pouvez choisir « Non précisé » pour rester neutre.")
            }

            stepNavigationFooter(
                back: { step = .intro },
                next: { step = .epilepsy },
                nextDisabled: firstName.trimmingCharacters(in: .whitespaces).isEmpty
            )
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Epilepsy step

    private var epilepsyStep: some View {
        Form {
            Section {
                Toggle(isOn: $hasEpilepsy) {
                    Label("\(childName) a de l'épilepsie", systemImage: "waveform.path.ecg")
                }
            } header: {
                Text("Épilepsie")
            } footer: {
                Text("Active le module de suivi des crises dans l'application. Vous pouvez modifier ce réglage à tout moment depuis Réglages → Profil.")
            }

            stepNavigationFooter(
                back: { step = .child },
                next: { step = .medications }
            )
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Medications step

    private var medicationsStep: some View {
        Form {
            Section {
                ForEach($initialMedications) { $med in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(med.name).font(AFSRFont.headline(16))
                            Text("\(med.doseAmount.formatted()) \(med.doseUnit.label)")
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .onDelete { idx in initialMedications.remove(atOffsets: idx) }

                NavigationLink {
                    DraftMedicationEditor { new in
                        initialMedications.append(new)
                    }
                } label: {
                    Label("Ajouter un médicament", systemImage: "plus.circle.fill")
                        .foregroundStyle(.afsrPurpleAdaptive)
                }
            } header: {
                Text("Médicaments en cours")
            } footer: {
                Text("Vous pourrez modifier cette liste à tout moment.")
            }

            Section {
                Button {
                    step = .epilepsy
                } label: {
                    Label("Précédent", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.afsrPurpleAdaptive)

                AFSRPrimaryButton(title: "Terminer la configuration") {
                    save()
                    step = .done
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Done step

    private var doneStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .resizable().scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundStyle(.afsrSuccess)
            Text("Tout est prêt !")
                .font(AFSRFont.title())
            Text("Vous pouvez maintenant utiliser RettApp.")
                .font(AFSRFont.body())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    // MARK: - Navigation footer

    @ViewBuilder
    private func stepNavigationFooter(
        back: @escaping () -> Void,
        next: @escaping () -> Void,
        nextDisabled: Bool = false
    ) -> some View {
        Section {
            HStack(spacing: 12) {
                Button(action: back) {
                    Label("Précédent", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.afsrPurpleAdaptive)

                Button(action: next) {
                    HStack {
                        Text("Continuer")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.afsrPurpleAdaptive)
                .disabled(nextDisabled)
            }
        }
    }

    // MARK: - Save

    private func save() {
        let profile = ChildProfile(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            birthDate: nil,
            hasEpilepsy: hasEpilepsy,
            sex: sex
        )
        modelContext.insert(profile)

        for draft in initialMedications {
            let med = Medication(
                name: draft.name,
                doseAmount: draft.doseAmount,
                doseUnit: draft.doseUnit,
                scheduledHours: draft.scheduledHours,
                isActive: true
            )
            med.childProfile = profile
            modelContext.insert(med)
        }

        try? modelContext.save()
    }
}

// MARK: - Draft medication helpers

struct DraftMedication: Identifiable {
    let id = UUID()
    var name: String
    var doseAmount: Double
    var doseUnit: DoseUnit
    var scheduledHours: [HourMinute]
}

struct DraftMedicationEditor: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (DraftMedication) -> Void

    @State private var name: String = ""
    @State private var dose: String = ""
    @State private var unit: DoseUnit = .mg
    @State private var times: [HourMinute] = [HourMinute(hour: 8, minute: 0)]

    var body: some View {
        Form {
            Section("Nom du médicament") {
                TextField("Ex. Keppra, Doliprane, Mélatonine…", text: $name)
                    .autocorrectionDisabled()
                if !name.isEmpty {
                    let suggestions = CommonFrenchMedications.suggestions(matching: name, limit: 6)
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            // Strip DCI parenthetical (e.g., "Doliprane (paracétamol)" → "Doliprane")
                            if let parenIdx = suggestion.firstIndex(of: "(") {
                                name = String(suggestion[..<parenIdx]).trimmingCharacters(in: .whitespaces)
                            } else {
                                name = suggestion
                            }
                        } label: {
                            HStack {
                                Image(systemName: "pills.fill")
                                    .foregroundStyle(.afsrPurpleAdaptive)
                                    .font(.system(size: 13))
                                Text(suggestion)
                                    .font(AFSRFont.body(14))
                                Spacer()
                            }
                        }
                    }
                }
            }

            Section("Dose") {
                HStack {
                    TextField("Quantité", text: $dose)
                        .keyboardType(.decimalPad)
                    Picker("Unité", selection: $unit) {
                        ForEach(DoseUnit.allCases, id: \.self) { u in
                            Text(u.label).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Heures de prise") {
                ForEach($times) { $t in
                    DatePicker("", selection: Binding(
                        get: { t.asDate },
                        set: { t = HourMinute(date: $0) }
                    ), displayedComponents: .hourAndMinute)
                }
                .onDelete { idx in times.remove(atOffsets: idx) }

                Button {
                    times.append(HourMinute(hour: 12, minute: 0))
                } label: {
                    Label("Ajouter une heure", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Nouveau médicament")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    let amount = Double(dose.replacingOccurrences(of: ",", with: ".")) ?? 0
                    onSave(DraftMedication(
                        name: name.trimmingCharacters(in: .whitespaces),
                        doseAmount: amount,
                        doseUnit: unit,
                        scheduledHours: times
                    ))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Double(dose.replacingOccurrences(of: ",", with: ".")) == nil)
            }
        }
    }
}

#Preview {
    ProfileSetupView()
        .modelContainer(PreviewData.emptyContainer)
}
