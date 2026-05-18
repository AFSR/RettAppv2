import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sous-page Réglages → Données → Importer des données historiques.
///
/// Pattern d'import : **un seul `.fileImporter`** au niveau de la vue
/// parent, routé via `pendingImport: PendingImport?` pour identifier qui
/// a demandé. iOS 17 a un bug SwiftUI où plusieurs `.fileImporter` dans
/// la même hiérarchie deviennent inertes (seul le dernier attaché
/// présente effectivement). On consolide pour éviter ce piège.
struct HistoricalDataImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]

    @State private var summary: SummaryAlert?
    @State private var pendingImport: PendingImport?
    @State private var combinedShareURL: URL?
    @State private var showCombinedShare = false
    @State private var combinedExportError: String?
    @State private var templateShareURL: URL?
    @State private var showTemplateShare = false
    @State private var templateError: String?

    /// Identifie quel handler doit traiter le fichier sélectionné.
    enum PendingImport: Identifiable {
        case combinedBackup
        case seizures
        case moods
        case observations
        case medications
        case medicationLogs

        var id: String { String(describing: self) }

        var allowedTypes: [UTType] {
            switch self {
            case .combinedBackup:
                return [.json]
            default:
                var types: [UTType] = [.commaSeparatedText, .plainText, .text]
                if let xls = UTType("org.openxmlformats.spreadsheetml.sheet") {
                    types.append(xls)
                }
                return types
            }
        }
    }

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
                pendingType: .seizures
            )

            importSection(
                title: "Humeurs",
                icon: "face.smiling",
                description: "Horodatage, niveau d'humeur (1-5), notes.",
                templateBuilder: { try MoodImporter.writeTemplate() },
                pendingType: .moods
            )

            importSection(
                title: "Observations quotidiennes",
                icon: "fork.knife",
                description: "Repas, hydratation, sommeil, sieste — un jour par ligne.",
                templateBuilder: { try ObservationImporter.writeTemplate() },
                pendingType: .observations
            )

            importSection(
                title: "Plan médicamenteux",
                icon: "pills.fill",
                description: "Une ligne par médicament. Colonnes : nom, dose, unité (mg/ml/tablet), horaires (ex. 08:00|20:00), type (regular ou adhoc), actif (1/0). Colonne facultative effective_from au format yyyy-MM-dd pour ajouter une révision historique du plan.",
                templateBuilder: { try MedicationImporter.writeTemplate() },
                pendingType: .medications
            )

            importSection(
                title: "Prises de médicaments",
                icon: "checkmark.circle.fill",
                description: "Historique des prises journalières (heure planifiée, heure réelle, pris ou non, dose, raison pour les ponctuelles). Une ligne par prise.",
                templateBuilder: { try MedicationLogImporter.writeTemplate() },
                pendingType: .medicationLogs
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
        // UN SEUL fileImporter pour toute la page — consolidé pour éviter
        // le bug iOS 17 où plusieurs .fileImporter rendaient le picker
        // silencieusement inerte.
        .fileImporter(
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            ),
            allowedContentTypes: pendingImport?.allowedTypes ?? [.commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFilePickResult(result)
        }
        .sheet(isPresented: $showCombinedShare) {
            if let url = combinedShareURL { ShareSheet(items: [url]) }
        }
        .sheet(isPresented: $showTemplateShare) {
            if let url = templateShareURL { ShareSheet(items: [url]) }
        }
        .alert("Export impossible",
               isPresented: Binding(get: { combinedExportError != nil },
                                    set: { if !$0 { combinedExportError = nil } })) {
            Button("OK") { combinedExportError = nil }
        } message: {
            Text(combinedExportError ?? "")
        }
        .alert("Erreur",
               isPresented: Binding(get: { templateError != nil },
                                    set: { if !$0 { templateError = nil } })) {
            Button("OK") { templateError = nil }
        } message: {
            Text(templateError ?? "")
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
                pendingImport = .combinedBackup
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
        pendingType: PendingImport
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

            Button {
                downloadTemplate(templateBuilder)
            } label: {
                Label("Télécharger le modèle CSV", systemImage: "doc.badge.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                pendingImport = pendingType
            } label: {
                Label("Importer un fichier CSV rempli", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Routing du picker unique

    private func handleFilePickResult(_ result: Result<[URL], Error>) {
        let importer = pendingImport
        pendingImport = nil
        switch result {
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                summary = SummaryAlert(
                    title: "Import impossible",
                    body: "Le fichier n'a pas pu être ouvert.",
                    details: error.localizedDescription
                )
            }
            return
        case .success(let urls):
            guard let url = urls.first, let importer else { return }
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if importer == .combinedBackup {
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
                } else {
                    let content = String(decoding: data, as: UTF8.self)
                    summary = runCSVImport(importer: importer, content: content)
                }
            } catch {
                summary = SummaryAlert(
                    title: "Lecture impossible",
                    body: "Le fichier n'a pas pu être lu.",
                    details: error.localizedDescription
                )
            }
        }
    }

    private func runCSVImport(importer: PendingImport, content: String) -> SummaryAlert {
        switch importer {
        case .seizures:
            let r = SeizureImporter.importCSV(contents: content, childProfile: profile, context: modelContext)
            return SummaryAlert(title: "Import des crises",
                                body: "\(r.imported) crise(s) importée(s), \(r.skipped) ligne(s) ignorée(s).",
                                details: r.errors.joined(separator: "\n"))
        case .moods:
            let r = MoodImporter.importCSV(contents: content, childProfile: profile, context: modelContext)
            return SummaryAlert(title: "Import des humeurs",
                                body: "\(r.imported) humeur(s) importée(s), \(r.skipped) ligne(s) ignorée(s).",
                                details: r.errors.joined(separator: "\n"))
        case .observations:
            let r = ObservationImporter.importCSV(contents: content, childProfile: profile, context: modelContext)
            return SummaryAlert(title: "Import des observations",
                                body: "\(r.imported) journée(s) importée(s), \(r.skipped) ligne(s) ignorée(s).",
                                details: r.errors.joined(separator: "\n"))
        case .medications:
            let r = MedicationImporter.importCSV(contents: content, childProfile: profile, context: modelContext)
            return SummaryAlert(title: "Import des médicaments",
                                body: "\(r.imported) médicament(s) / révision(s) importé(s), \(r.skipped) ligne(s) ignorée(s).",
                                details: r.errors.joined(separator: "\n"))
        case .medicationLogs:
            let r = MedicationLogImporter.importCSV(contents: content, childProfile: profile, context: modelContext)
            return SummaryAlert(title: "Import des prises",
                                body: "\(r.imported) prise(s) importée(s), \(r.skipped) ligne(s) ignorée(s).",
                                details: r.errors.joined(separator: "\n"))
        case .combinedBackup:
            return SummaryAlert(title: "Erreur", body: "Type d'import incorrect.", details: "")
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

    private func downloadTemplate(_ builder: () throws -> URL) {
        do {
            templateShareURL = try builder()
            showTemplateShare = true
        } catch {
            templateError = error.localizedDescription
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
