import SwiftUI
import SwiftData

/// Saisie rapide d'une humeur ponctuelle.
struct MoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]

    @State private var level: MoodLevel = .neutral
    @State private var timestamp: Date = Date()
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Humeur observée") {
                    HStack(spacing: 12) {
                        ForEach(MoodLevel.allCases) { lvl in
                            Button {
                                level = lvl
                            } label: {
                                VStack(spacing: 4) {
                                    Text(lvl.emoji)
                                        .font(.system(size: 36))
                                    Text(lvl.label)
                                        .font(AFSRFont.caption())
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(level == lvl
                                    ? Color.afsrPurpleAdaptive.opacity(0.2)
                                    : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Heure") {
                    DatePicker("Heure", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Notes (optionnel)") {
                    TextField("Ex. agitée après la sieste, sourit beaucoup…", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Humeur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.bold()
                }
            }
        }
    }

    private func save() {
        let entry = MoodEntry(
            timestamp: timestamp,
            level: level,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            childProfileId: profiles.first?.id
        )
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}
