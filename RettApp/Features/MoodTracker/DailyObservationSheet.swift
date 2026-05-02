import SwiftUI
import SwiftData

/// Saisie qualitative + quantitative quotidienne : repas, hydratation, sommeil de nuit, sieste.
struct DailyObservationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]

    let dayStart: Date

    @State private var existing: DailyObservation?

    @State private var mealRating: QualityRating?
    @State private var mealNotes: String = ""
    @State private var hydrationRating: QualityRating?
    @State private var hydrationNotes: String = ""
    @State private var nightSleepRating: QualityRating?
    @State private var nightSleepNotes: String = ""
    @State private var napDurationMinutes: Int = 0
    @State private var napNotes: String = ""
    @State private var generalNotes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Repas") {
                    QualityPicker(rating: $mealRating, label: "Appétit / qualité du repas")
                    TextField("Détails (refus de manger, repas particuliers…)", text: $mealNotes, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("Hydratation") {
                    QualityPicker(rating: $hydrationRating, label: "Quantité bue")
                    TextField("Détails (boissons, refus, déshydratation…)", text: $hydrationNotes, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section("Sommeil de nuit") {
                    QualityPicker(rating: $nightSleepRating, label: "Qualité")
                    TextField("Détails (réveils, agitation, durée approx.…)", text: $nightSleepNotes, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("Sieste") {
                    HStack {
                        Text("Durée")
                        Spacer()
                        Stepper(value: $napDurationMinutes, in: 0...300, step: 15) {
                            Text(napDurationMinutes == 0 ? "Pas de sieste" : "\(napDurationMinutes) min")
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Détails", text: $napNotes, axis: .vertical)
                        .lineLimit(1...3)
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

    private func loadExisting() {
        let normalized = Calendar.current.startOfDay(for: dayStart)
        let descriptor = FetchDescriptor<DailyObservation>(
            predicate: #Predicate { $0.dayStart == normalized }
        )
        if let found = try? modelContext.fetch(descriptor).first {
            existing = found
            mealRating = found.mealRating
            mealNotes = found.mealNotes
            hydrationRating = found.hydrationRating
            hydrationNotes = found.hydrationNotes
            nightSleepRating = found.nightSleepRating
            nightSleepNotes = found.nightSleepNotes
            napDurationMinutes = found.napDurationMinutes
            napNotes = found.napNotes
            generalNotes = found.generalNotes
        }
    }

    private func save() {
        let normalized = Calendar.current.startOfDay(for: dayStart)
        if let existing {
            existing.mealRating = mealRating
            existing.mealNotes = mealNotes
            existing.hydrationRating = hydrationRating
            existing.hydrationNotes = hydrationNotes
            existing.nightSleepRating = nightSleepRating
            existing.nightSleepNotes = nightSleepNotes
            existing.napDurationMinutes = napDurationMinutes
            existing.napNotes = napNotes
            existing.generalNotes = generalNotes
        } else {
            let obs = DailyObservation(
                dayStart: normalized,
                mealRating: mealRating, mealNotes: mealNotes,
                hydrationRating: hydrationRating, hydrationNotes: hydrationNotes,
                nightSleepRating: nightSleepRating, nightSleepNotes: nightSleepNotes,
                napDurationMinutes: napDurationMinutes, napNotes: napNotes,
                generalNotes: generalNotes,
                childProfileId: profiles.first?.id
            )
            modelContext.insert(obs)
        }
        try? modelContext.save()
        dismiss()
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
