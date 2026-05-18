import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sous-page Réglages → Données → Importer des données historiques.
///
/// Deux familles d'imports :
/// - **Sauvegarde complète** (JSON) : un seul fichier, toutes les données
///   d'un coup. Format idéal pour migrer entre appareils, restaurer après
///   réinstallation, ou échanger avec un autre suivi exporté.
/// - **Imports par type** (CSV) : pour pré-remplir RettApp à partir d'un
///   tableur tenu en parallèle. Chaque type expose son **modèle CSV
///   téléchargeable** (boutons explicites) et son **bouton d'import** —
///   plus de menu caché.
struct HistoricalDataImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]

    @State private var summary: SummaryAlert?
    @State private var showCombinedFilePicker = false
    @State private var combinedShareURL: URL?
    @State private var showCombinedShare = false
    @State private var combinedExportError: String?

    private var profile: ChildProfile? { profiles.first }

    var body: some View {
        Form {
            introSection
            combinedBackupSection

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
                description: "Une ligne par médicament. Colonnes : nom, dose, unité (mg/ml/tablet), horaires (ex. 08:00|20:00), type (regular ou adhoc), actif (1/0). Colonne facultative effective_from au format yyyy-MM-dd pour ajouter une révision historique du plan (utile pour reconstituer les changements de dose passés).",
                templateBuilder: { try MedicationImporter.writeTemplate() },
                importer: { content in
                    let r = MedicationImporter.importCSV(contents: content,
                                                         childProfile: profile,
                                                         context: modelContext)
                    return SummaryAlert(title: "Import des médicaments",
                                        body: "\(r.imported) médicament(s) / révision(s) importé(s), \(r.skipped) ligne(s) ignorée(s).",
                                        details: r.errors.joined(separator: "\n"))
                }
            )

            importSection(
                title: "Prises de médicaments",
                icon: "checkmark.circle.fill",
                description: "Historique des prises journalières (heure planifiée, heure réelle, pris ou non, dose, raison pour les ponctuelles). Une ligne par prise.",
                templateBuilder: { try MedicationLogImporter.writeTemplate() },
                importer: { content in
                    let r = MedicationLogImporter.importCSV(contents: content,
                                                            childProfile: profile,
                                                            context: modelContext)
                    return SummaryAlert(title: "Import des prises",
                                        body: "\(r.imported) prise(s) importée(s), \(r.skipped) ligne(s) ignorée(s).",
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
        .fileImporter(
            isPresented: $showCombinedFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleCombinedImport(result: result)
        }
        .sheet(isPresented: $showCombinedShare) {
            if let url = combinedShareURL { ShareSheet(items: [url]) }
        }
        .alert("Export impossible",
               isPresented: Binding(get: { combinedExportError != nil },
                                    set: { if !$0 { combinedExportError = nil } })) {
            Button("OK") { combinedExportError = nil }
        } message: {
            Text(combinedExportError ?? "")
        }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Pré-remplir RettApp avec un historique externe", systemImage: "tray.and.arrow.down.fill")
                    .font(AFSRFont.headline(15))
                    .foregroundStyle(.afsrPurpleAdaptive)
                Text("Deux options : importer une sauvegarde complète d'un coup (JSON), ou pré-remplir un type de données à la fois via un modèle CSV à compléter dans Excel / Numbers. Les données existantes sont préservées — les nouvelles s'ajoutent ou mettent à jour les entrées au même identifiant.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var combinedBackupSection: some View {
        Section {
            Button {
                exportCombined()
            } label: {
                Label("Exporter toutes les données (JSON)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                showCombinedFilePicker = true
            } label: {
                Label("Importer une sauvegarde complète (JSON)", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Sauvegarde complète")
        } footer: {
            Text("Le fichier JSON contient médicaments, prises, crises, humeurs, observations, symptômes et historique des modifications du plan. Idéal pour transférer un suivi entre deux appareils ou restaurer après une réinstallation.")
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.afsrPurpleAdaptive)
                    .font(.system(size: 16))
                    .frame(width: 22)
                Text(title)
                    .font(AFSRFont.headline(15))
            }
            Text(description)
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            CSVImportButtons(
                buildTemplate: templateBuilder,
                onImportedContent: { content in
                    summary = importer(content)
                }
            )
        }
    }

    // MARK: - Combined backup actions

    private func exportCombined() {
        do {
            let url = try CombinedBackupService.export(context: modelContext)
            combinedShareURL = url
            showCombinedShare = true
        } catch {
            combinedExportError = error.localizedDescription
        }
    }

    private func handleCombinedImport(result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let r = CombinedBackupService.importBackup(contents: data, context: modelContext)
            var body = "Médicaments : \(r.medications)\n"
            body += "Prises : \(r.medicationLogs)\n"
            body += "Crises : \(r.seizures)\n"
            body += "Humeurs : \(r.moods)\n"
            body += "Observations : \(r.observations)\n"
            body += "Symptômes : \(r.symptoms)\n"
            body += "Révisions du plan : \(r.revisions)"
            summary = SummaryAlert(
                title: "Sauvegarde importée",
                body: body,
                details: r.errors.joined(separator: "\n")
            )
        } catch {
            summary = SummaryAlert(
                title: "Import impossible",
                body: "Le fichier n'a pas pu être lu.",
                details: error.localizedDescription
            )
        }
    }

    struct SummaryAlert: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let details: String
    }
}

/// Boutons explicites pour télécharger un modèle CSV + importer un fichier CSV.
/// Remplace le `CSVImportMenu` (caché derrière une icône `…`) dans les vues
/// où les actions doivent être immédiatement visibles.
struct CSVImportButtons: View {
    let buildTemplate: () throws -> URL
    let onImportedContent: (String) -> Void

    @State private var showFilePicker = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            Button {
                do {
                    shareURL = try buildTemplate()
                    showShare = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                Label("Télécharger le modèle CSV", systemImage: "doc.badge.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                showFilePicker = true
            } label: {
                Label("Importer un fichier CSV rempli", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let needsAccess = url.startAccessingSecurityScopedResource()
                defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let content = String(decoding: data, as: UTF8.self)
                    onImportedContent(content)
                } catch {
                    errorMessage = "Lecture impossible : \(error.localizedDescription)"
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ShareSheet(items: [url]) }
        }
        .alert("Erreur", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private static var allowedTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText, .text]
        if let xls = UTType("org.openxmlformats.spreadsheetml.sheet") {
            types.append(xls)
        }
        return types
    }
}

#Preview {
    NavigationStack { HistoricalDataImportView() }
        .modelContainer(PreviewData.emptyContainer)
}
