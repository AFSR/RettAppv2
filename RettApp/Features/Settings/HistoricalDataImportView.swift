import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sous-page Réglages → Données → Importer des données historiques.
///
/// Pattern d'import : **un seul `.fileImporter`** au niveau de la vue
/// parent. Deux états distincts pour piloter le picker :
/// - `showPicker: Bool` → binding du `.fileImporter`
/// - `pickerType: PendingImport?` → quel handler doit traiter le fichier
///
/// Les deux sont séparés volontairement parce qu'en iOS 17 SwiftUI
/// réinitialise le binding `isPresented` du picker AVANT d'appeler le
/// completion handler. Si on encodait le type dans le binding lui-même,
/// on perdrait l'info au moment de router le résultat. `pickerType`
/// survit au callback et n'est remis à zéro qu'à l'intérieur.
///
/// Idem côté `.fileImporter` empilés : avoir plusieurs `.fileImporter` au
/// sein d'une même hiérarchie SwiftUI les rend silencieusement inertes —
/// d'où l'unique modifier au niveau de la `Form`.
struct HistoricalDataImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]

    @State private var summary: SummaryAlert?
    /// Type d'import en cours — persiste à travers le callback du picker.
    /// Découpé volontairement de `showPicker` (Bool) parce qu'en iOS 17
    /// SwiftUI réinitialise le binding `isPresented` AVANT d'appeler le
    /// completion handler. Si on stockait le type dans le binding lui-même,
    /// on l'aurait perdu au moment de router le résultat.
    @State private var pickerType: PendingImport?
    @State private var showPicker: Bool = false
    /// État unique pour la feuille de partage (export JSON OU téléchargement
    /// de modèle CSV). Deux `.sheet(isPresented:)` distincts se gênaient
    /// mutuellement en iOS 17 ; un seul `.sheet(item:)` indexé par cette
    /// valeur est fiable.
    @State private var shareItem: ShareItem?
    @State private var exportError: String?

    /// Wrapper Identifiable pour le sheet de partage. L'`id` est l'URL —
    /// SwiftUI rebuild le sheet à chaque nouvelle URL, donc on peut
    /// enchaîner deux exports différents sans relancer la vue.
    struct ShareItem: Identifiable {
        let url: URL
        var id: URL { url }
    }

    /// Identifie quel handler doit traiter le fichier sélectionné.
    enum PendingImport: Identifiable {
        case combinedBackup
        case seizures
        case moods
        case observations
        case medications
        case medicationLogs

        var id: String { String(describing: self) }

    }

    /// Types autorisés couvrant à la fois CSV et JSON. On utilise une seule
    /// liste statique passée au `.fileImporter` parce qu'iOS 17 lit
    /// `allowedContentTypes` à l'installation du modifier, pas à la
    /// présentation — un calcul dynamique basé sur `pickerType` n'aurait
    /// pas pris effet.
    private static let allAllowedTypes: [UTType] = {
        var types: [UTType] = [.json, .commaSeparatedText, .plainText, .text]
        if let xls = UTType("org.openxmlformats.spreadsheetml.sheet") {
            types.append(xls)
        }
        return types
    }()

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
        // UN SEUL fileImporter pour toute la page (les multiples
        // .fileImporter empilés sont silencieusement inertes en iOS 17),
        // avec un Bool de présentation séparé du `pickerType` qui doit
        // survivre au callback.
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: Self.allAllowedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFilePickResult(result)
        }
        // Sheet unique pour partager un fichier (JSON ou CSV template).
        // `.sheet(item:)` est plus fiable que deux `.sheet(isPresented:)`
        // empilés — iOS 17 sait clairement quoi présenter via l'identifiant.
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Export impossible",
               isPresented: Binding(get: { exportError != nil },
                                    set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
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
                pickerType = .combinedBackup
                showPicker = true
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
                pickerType = pendingType
                showPicker = true
            } label: {
                Label("Importer un fichier CSV rempli", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Routing du picker unique

    private func handleFilePickResult(_ result: Result<[URL], Error>) {
        // `pickerType` survit volontairement au binding `showPicker`
        // (réinitialisé par SwiftUI avant le callback). On capture
        // localement puis on remet à zéro pour la prochaine ouverture.
        let importer = pickerType
        pickerType = nil
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
            shareItem = ShareItem(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func downloadTemplate(_ builder: () throws -> URL) {
        do {
            let url = try builder()
            shareItem = ShareItem(url: url)
        } catch {
            exportError = error.localizedDescription
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
