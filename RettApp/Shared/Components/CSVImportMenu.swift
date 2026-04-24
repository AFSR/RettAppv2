import SwiftUI
import UniformTypeIdentifiers

/// Menu réutilisable "Importer/Template" pour les vues historiques.
/// - Bouton "Télécharger le modèle CSV" : écrit un fichier temporaire + ShareSheet
/// - Bouton "Importer un fichier CSV" : fileImporter, puis callback avec le contenu
struct CSVImportMenu: View {
    let buildTemplate: () throws -> URL
    let onImportedContent: (String) -> Void

    @State private var showFilePicker = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Button {
                do {
                    shareURL = try buildTemplate()
                    showShare = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            } label: {
                Label("Télécharger le modèle CSV", systemImage: "doc.badge.arrow.up")
            }
            Button {
                showFilePicker = true
            } label: {
                Label("Importer un fichier CSV", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
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

    /// Accepte CSV et texte brut (les fichiers Excel sauvegardés en CSV UTF-8 sont
    /// déclarés comme `.commaSeparatedText` ou `.plainText` selon l'OS).
    private static var allowedTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText, .text]
        if let xls = UTType("org.openxmlformats.spreadsheetml.sheet") {
            types.append(xls)
        }
        return types
    }
}
