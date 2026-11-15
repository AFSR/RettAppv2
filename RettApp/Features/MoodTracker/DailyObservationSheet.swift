import SwiftUI
import SwiftData

/// Saisie qualitative + quantitative quotidienne : 4 repas distincts, hydratation,
/// sommeil de nuit (qualité + durée), sieste.
struct DailyObservationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudKitSyncService.self) private var sync
    @Query private var profiles: [ChildProfile]

    let dayStart: Date

    @State private var existing: DailyObservation?

    @State private var mealRatings: [MealSlot: QualityRating?] = [:]
    @State private var mealNotes: [MealSlot: String] = [:]

    @State private var hydrationRating: QualityRating?
    @State private var hydrationNotes: String = ""

    @State private var nightSleepRating: QualityRating?
    @State private var nightSleepDurationMinutes: Int = 0
    @State private var nightSleepNotes: String = ""

    @State private var napDurationMinutes: Int = 0
    @State private var napNotes: String = ""

    @State private var stoolCount: Int?
    @State private var stoolAspect: StoolAspect?
    @State private var stoolNotes: String = ""

    @State private var urineOutput: UrineOutput?
    @State private var urineNotes: String = ""

    @State private var generalNotes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(MealSlot.allCases) { slot in
                        MealRow(
                            slot: slot,
                            rating: Binding(
                                get: { mealRatings[slot] ?? nil },
                                set: { mealRatings[slot] = $0 }
                            ),
                            notes: Binding(
                                get: { mealNotes[slot] ?? "" },
                                set: { mealNotes[slot] = $0 }
                            )
                        )
                    }
                } header: {
                    Text("Repas")
                } footer: {
                    Text("Notez l'appétit / la qualité de chaque repas. Laissez vide ce qui n'a pas eu lieu.")
                }

                Section("Hydratation") {
                    QualityPicker(rating: $hydrationRating, label: "Quantité bue sur la journée")
                    TextField("Détails (boissons, refus, déshydratation…)", text: $hydrationNotes, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Sommeil de nuit") {
                    HStack {
                        Text("Durée").foregroundStyle(.secondary)
                        Spacer()
                        Stepper(value: $nightSleepDurationMinutes, in: 0...900, step: 15) {
                            Text(formatNightDuration(nightSleepDurationMinutes))
                                .monospacedDigit()
                        }
                    }
                    QualityPicker(rating: $nightSleepRating, label: "Qualité")
                    TextField("Détails (réveils, agitation, heure de coucher…)", text: $nightSleepNotes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Sieste") {
                    HStack {
                        Text("Durée").foregroundStyle(.secondary)
                        Spacer()
                        Stepper(value: $napDurationMinutes, in: 0...300, step: 15) {
                            Text(napDurationMinutes == 0 ? "Pas de sieste" : "\(napDurationMinutes) min")
                                .monospacedDigit()
                        }
                    }
                    TextField("Détails", text: $napNotes, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    // « Non noté » est une réponse à part entière, et il faut
                    // qu'elle se distingue de « aucune selle ». Confondre les
                    // deux ferait apparaître une constipation qui n'a jamais
                    // été constatée — exactement ce qu'on vient suivre ici.
                    Picker("Nombre de selles", selection: $stoolCount) {
                        Text("Non noté").tag(Int?.none)
                        Text("Aucune").tag(Optional(0))
                        Text("1").tag(Optional(1))
                        Text("2").tag(Optional(2))
                        Text("3 et plus").tag(Optional(DailyObservation.stoolCountCap))
                    }

                    Picker("Aspect", selection: $stoolAspect) {
                        Text("Non noté").tag(StoolAspect?.none)
                        ForEach(StoolAspect.allCases) { aspect in
                            Text(aspect.label).tag(Optional(aspect))
                        }
                    }

                    TextField("Détails (douleurs, sang, effort…)", text: $stoolNotes, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Selles")
                } footer: {
                    Text("La constipation est fréquente dans le syndrome de Rett. Noter « aucune » les jours sans selle est ce qui la rend visible au médecin.")
                }

                Section {
                    Picker("Quantité sur la journée", selection: $urineOutput) {
                        Text("Non noté").tag(UrineOutput?.none)
                        ForEach(UrineOutput.allCases) { sortie in
                            Text(sortie.label).tag(Optional(sortie))
                        }
                    }

                    TextField("Détails (odeur, couleur, douleur…)", text: $urineNotes, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Urines")
                } footer: {
                    Text("Des urines rares signalent une déshydratation, que rien d'autre ne montre chez un enfant qui ne parle pas.")
                }

                Section("Notes générales (optionnel)") {
                    TextField("Tout autre élément du jour", text: $generalNotes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.bold()
                }
            }
            .task { loadExisting() }
        }
    }

    private var dateTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: dayStart).capitalized
    }

    private func formatNightDuration(_ minutes: Int) -> String {
        if minutes == 0 { return "Non renseignée" }
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }

    private func loadExisting() {
        let normalized = Calendar.current.startOfDay(for: dayStart)
        let descriptor = FetchDescriptor<DailyObservation>(
            predicate: #Predicate { $0.dayStart == normalized }
        )
        if let found = try? modelContext.fetch(descriptor).first {
            existing = found
            for slot in MealSlot.allCases {
                mealRatings[slot] = found.mealRating(for: slot)
                mealNotes[slot] = found.mealNotes(for: slot)
            }
            hydrationRating = found.hydrationRating
            hydrationNotes = found.hydrationNotes
            nightSleepRating = found.nightSleepRating
            nightSleepDurationMinutes = found.nightSleepDurationMinutes
            nightSleepNotes = found.nightSleepNotes
            napDurationMinutes = found.napDurationMinutes
            napNotes = found.napNotes
            stoolCount = found.stoolCount
            stoolAspect = found.stoolAspect
            stoolNotes = found.stoolNotes
            urineOutput = found.urineOutput
            urineNotes = found.urineNotes
            generalNotes = found.generalNotes
        }
    }

    private func save() {
        let normalized = Calendar.current.startOfDay(for: dayStart)
        if let existing {
            for slot in MealSlot.allCases {
                existing.setMealRating(mealRatings[slot] ?? nil, for: slot)
                existing.setMealNotes(mealNotes[slot] ?? "", for: slot)
            }
            existing.hydrationRating = hydrationRating
            existing.hydrationNotes = hydrationNotes
            existing.nightSleepRating = nightSleepRating
            existing.nightSleepDurationMinutes = nightSleepDurationMinutes
            existing.nightSleepNotes = nightSleepNotes
            existing.napDurationMinutes = napDurationMinutes
            existing.napNotes = napNotes
            existing.stoolCount = stoolCount
            existing.stoolAspect = stoolAspect
            existing.stoolNotes = stoolNotes
            existing.urineOutput = urineOutput
            existing.urineNotes = urineNotes
            existing.generalNotes = generalNotes
        } else {
            let obs = DailyObservation(
                dayStart: normalized,
                breakfastRating: mealRatings[.breakfast] ?? nil,
                breakfastNotes: mealNotes[.breakfast] ?? "",
                lunchRating: mealRatings[.lunch] ?? nil,
                lunchNotes: mealNotes[.lunch] ?? "",
                snackRating: mealRatings[.snack] ?? nil,
                snackNotes: mealNotes[.snack] ?? "",
                dinnerRating: mealRatings[.dinner] ?? nil,
                dinnerNotes: mealNotes[.dinner] ?? "",
                hydrationRating: hydrationRating,
                hydrationNotes: hydrationNotes,
                nightSleepRating: nightSleepRating,
                nightSleepDurationMinutes: nightSleepDurationMinutes,
                nightSleepNotes: nightSleepNotes,
                napDurationMinutes: napDurationMinutes,
                napNotes: napNotes,
                stoolCount: stoolCount,
                stoolAspect: stoolAspect,
                stoolNotes: stoolNotes,
                urineOutput: urineOutput,
                urineNotes: urineNotes,
                generalNotes: generalNotes,
                childProfileId: profiles.first?.id
            )
            modelContext.insert(obs)
        }
        try? modelContext.saveTouching()
        sync.scheduleSync(context: modelContext)
        dismiss()
    }
}

// MARK: - Per-meal row

private struct MealRow: View {
    let slot: MealSlot
    @Binding var rating: QualityRating?
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: slot.icon)
                    .foregroundStyle(.afsrPurpleAdaptive)
                Text(slot.label)
                    .font(AFSRFont.headline(15))
            }
            QualityPicker(rating: $rating, label: "Qualité / appétit")
            TextField("Notes (refus, repas particulier…)", text: $notes, axis: .vertical)
                .lineLimit(1...3)
        }
        .padding(.vertical, 4)
    }
}

private struct QualityPicker: View {
    @Binding var rating: QualityRating?
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(AFSRFont.caption()).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(QualityRating.allCases) { r in
                    Button {
                        rating = (rating == r) ? nil : r
                    } label: {
                        Text(r.symbol)
                            .font(AFSRFont.headline(15))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(rating == r
                                ? Color.afsrPurpleAdaptive
                                : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(rating == r ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(r.label)")
                }
            }
            if let r = rating {
                Text(r.label)
                    .font(AFSRFont.caption())
                    .foregroundStyle(.afsrPurpleAdaptive)
            }
        }
        .padding(.vertical, 4)
    }
}
