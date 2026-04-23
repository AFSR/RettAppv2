import SwiftUI
import SwiftData

struct ProfileSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager

    @State private var firstName: String = ""
    @State private var hasBirthDate: Bool = false
    @State private var birthDate: Date = Date()
    @State private var hasEpilepsy: Bool = false
    @State private var initialMedications: [DraftMedication] = []
    @State private var step: Step = .intro

    enum Step { case intro, child, epilepsy, medications, done }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.afsrBackground.ignoresSafeArea()
                VStack {
                    ProgressView(value: progress)
                        .tint(.afsrPurple)
                        .padding(.horizontal)

                    Group {
                        switch step {
                        case .intro: introStep
                        case .child: childStep
                        case .epilepsy: epilepsyStep
                        case .medications: medicationsStep
                        case .done: doneStep
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
        case .intro: return 0.1
        case .child: return 0.3
        case .epilepsy: return 0.55
        case .medications: return 0.8
        case .done: return 1.0
        }
    }

    // MARK: - Steps

    private var introStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.2.circle.fill")
                .resizable().scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundStyle(.afsrPurple)
            Text("Bienvenue")
                .font(AFSRFont.title())
            Text("Nous allons configurer le profil de votre enfant.\nCes informations restent sur votre appareil.")
                .font(AFSRFont.body())
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            AFSRPrimaryButton(title: "Commencer") { step = .child }
                .padding(.horizontal)
        }
        .padding()
    }

    private var childStep: some View {
        Form {
            Section("Prénom de l'enfant") {
                TextField("Prénom", text: $firstName)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
            }
            Section {
                Toggle("Renseigner la date de naissance", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker("Née le", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                }
            } footer: {
                Text("Utilisé pour calculer l'âge dans les exports.")
            }
            Section {
                AFSRPrimaryButton(title: "Continuer") { step = .epilepsy }
                    .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var epilepsyStep: some View {
        Form {
            Section {
                Toggle(isOn: $hasEpilepsy) {
                    Label("L'enfant a de l'épilepsie", systemImage: "waveform.path.ecg")
                }
            } footer: {
                Text("Active le module de suivi des crises dans l'application.")
            }
            Section {
                AFSRPrimaryButton(title: "Continuer") { step = .medications }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var medicationsStep: some View {
        VStack {
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
                            .foregroundStyle(.afsrPurple)
                    }
                } header: {
                    Text("Médicaments en cours")
                } footer: {
                    Text("Vous pourrez modifier cette liste à tout moment.")
                }
            }
            .scrollContentBackground(.hidden)

            AFSRPrimaryButton(title: "Terminer la configuration") {
                save()
                step = .done
            }
            .padding()
        }
    }

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

    // MARK: - Save

    private func save() {
        let appleID: String? = {
            if case .signedIn(let id) = authManager.state { return id }
            return nil
        }()

        let profile = ChildProfile(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            birthDate: hasBirthDate ? birthDate : nil,
            hasEpilepsy: hasEpilepsy,
            appleUserID: appleID
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

    private static let commonNames = [
        "Dépakine", "Keppra", "Lamictal", "Rivotril", "Valium", "Urbanyl",
        "Sabril", "Topamax", "Tegretol", "Diacomit", "Ospolot"
    ]

    var body: some View {
        Form {
            Section("Nom du médicament") {
                TextField("Ex. Keppra", text: $name)
                    .autocorrectionDisabled()
                if !name.isEmpty {
                    ForEach(Self.commonNames.filter { $0.localizedCaseInsensitiveContains(name) && $0.lowercased() != name.lowercased() }, id: \.self) { suggestion in
                        Button(suggestion) { name = suggestion }
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
        .environment(AuthManager.previewSignedIn())
}
