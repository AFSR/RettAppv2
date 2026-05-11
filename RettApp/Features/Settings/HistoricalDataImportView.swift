import SwiftUI
import SwiftData

/// Sous-page Réglages → Données → Importer des données historiques.
/// Regroupe les imports CSV de tous les types de données pour repeupler
/// la base à partir d'un suivi externe (tableur, ancien outil, dossier
/// médical exporté, etc.).
struct HistoricalDataImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]

    @State private var summary: SummaryAlert?

    private var profile: ChildProfile? { profiles.first }

    var body: some View {
        Form {
            introSection

            importSection(
                title: "Crises d'épilepsie",
                icon: "waveform.path.ecg",
                description: "Date/heure de début et fin, type, déclencheur, notes.",
                templateBuilder: { try SeizureImporter.writeTemplate() },
                importer: { content in
                    let r = SeizureImporter.importCSV(contents: content,
                                                      childProfile: profile,
                                                      context: modelContext)
                    return SummaryAlert(title: "Import des crises",
                                        body: "\(r.imported) crise(s) importée(s), \(r.skipped) ligne(s) ignorée(s).",
                                        details: r.errors.joined(separator: "\n"))
                }
            )

            importSection(
                title: "Humeurs",
                icon: "face.smiling",
                description: "Horodatage, niveau d'humeur (1-5), notes.",
                templateBuilder: { try MoodImporter.writeTemplate() },
                importer: { content in
                    let r = MoodImporter.importCSV(contents: content,
                                                   childProfile: profile,
                                                   context: modelContext)
                    return SummaryAlert(title: "Import des humeurs",
                                        body: "\(r.imported) humeur(s) importée(s), \(r.skipped) ligne(s) ignorée(s).",
                                        details: r.errors.joined(separator: "\n"))
                }
            )

            importSection(
                title: "Observations quotidiennes",
                icon: "fork.knife",
                description: "Repas, hydratation, sommeil, sieste — un jour par ligne.",
                templateBuilder: { try ObservationImporter.writeTemplate() },
                importer: { content in
                    let r = ObservationImporter.importCSV(contents: content,
                                                          childProfile: profile,
                                                          context: modelContext)
                    return SummaryAlert(title: "Import des observations",
                                        body: "\(r.imported) journée(s) importée(s), \(r.skipped) ligne(s) ignorée(s).",
                                        details: r.errors.joined(separator: "\n"))
                }
            )

            importSection(
                title: "Plan médicamenteux",
                icon: "pills.fill",
                description: "Définit les médicaments réguliers ou ponctuels (nom, dose, horaires).",
                templateBuilder: { try MedicationImporter.writeTemplate() },
                importer: { content in
                    let r = MedicationImporter.importCSV(contents: content,
                                                         childProfile: profile,
                                                         context: modelContext)
                    return SummaryAlert(title: "Import des médicaments",
                                        body: "\(r.imported) médicament(s) importé(s), \(r.skipped) ligne(s) ignorée(s).",
                                        details: r.errors.joined(separator: "\n"))
                }
            )
        }
        .navigationTitle("Importer un historique")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $summary) { s in
            Alert(
                title: Text(s.title),
                message: Text([s.body, s.details].filter { !$0.isEmpty }.joined(separator: "\n\n")),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Pré-remplir RettApp avec un historique externe", systemImage: "tray.and.arrow.down.fill")
                    .font(AFSRFont.headline(15))
                    .foregroundStyle(.afsrPurpleAdaptive)
                Text("Pour chaque type de données, téléchargez le modèle CSV, complétez-le dans Excel ou Numbers, puis importez le fichier rempli. Les données existantes sont préservées (les nouvelles s'ajoutent).")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func importSection(
        title: String,
        icon: String,
        description: String,
        templateBuilder: @escaping () throws -> URL,
        importer: @escaping (String) -> SummaryAlert
    ) -> some View {
        Section {
            HStack {
                Label(title, systemImage: icon)
                    .font(AFSRFont.headline(14))
                Spacer()
                CSVImportMenu(
                    buildTemplate: templateBuilder,
                    onImportedContent: { content in
                        summary = importer(content)
                    }
                )
            }
            Text(description)
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    struct SummaryAlert: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let details: String
    }
}

#Preview {
    NavigationStack { HistoricalDataImportView() }
        .modelContainer(PreviewData.emptyContainer)
}
