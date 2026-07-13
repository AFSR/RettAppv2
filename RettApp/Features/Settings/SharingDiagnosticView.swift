import SwiftUI
import SwiftData

/// Page de diagnostic technique de la couche de partage CloudKit.
/// Objectif : quand la sync coince, l'utilisateur peut screenshotter cet
/// écran et l'envoyer au support pour qu'on voie exactement ce que voit
/// son device (rôle, zones privée et partagée, share URL, subscriptions…).
///
/// C'est du texte brut monospace — pas de layout élaboré, on veut la
/// vérité en clair.
struct SharingDiagnosticView: View {
    @Environment(CloudKitSyncService.self) private var sync

    @State private var snapshot: CloudKitSyncService.DiagnosticSnapshot?
    @State private var isRefreshing: Bool = false

    var body: some View {
        List {
            if let snap = snapshot {
                snapshotContent(snap)
            } else if isRefreshing {
                Section {
                    HStack {
                        ProgressView()
                        Text("Analyse en cours…").padding(.leading, 8)
                    }
                }
            } else {
                Section {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("Lancer le diagnostic", systemImage: "stethoscope")
                    }
                } footer: {
                    Text("Un ping CloudKit qui affiche l'état exact du partage sur cet appareil : rôle, zones existantes, subscriptions, dernière erreur. À joindre en capture d'écran si vous nous contactez.")
                }
            }
        }
        .navigationTitle("Diagnostic sync")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if snapshot != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
        }
        .task {
            if snapshot == nil { await refresh() }
        }
    }

    @ViewBuilder
    private func snapshotContent(_ snap: CloudKitSyncService.DiagnosticSnapshot) -> some View {
        Section("Compte") {
            row("Statut iCloud", snap.accountStatus)
            row("Rôle courant", snap.role)
            row("Subscriptions enregistrées", snap.subscriptionsRegistered ? "oui" : "non")
        }
        Section("Zone privée (base iCloud personnelle)") {
            row("Zone présente ?", snap.privateZoneExists ? "oui" : "non")
            row("Share attaché ?", snap.privateZoneShareExists ? "oui" : "non")
            if let url = snap.privateZoneShareURL {
                row("URL du share", url, mono: true)
            }
        }
        Section("Zones partagées (base iCloud d'un autre parent)") {
            row("Nombre de zones", "\(snap.sharedZonesCount)")
            if snap.sharedZones.isEmpty {
                Text("Aucune zone partagée détectée.")
                    .font(AFSRFont.caption()).foregroundStyle(.secondary)
            } else {
                ForEach(snap.sharedZones, id: \.self) { z in
                    Text(z).font(.system(.caption, design: .monospaced))
                }
            }
            row("Share détecté sur ces zones ?", snap.sharedZoneShareExists ? "oui" : "non")
        }
        Section("Sync (état courant)") {
            row("Écritures en attente", "\(snap.pendingWriteCount)")
            if let ts = snap.lastSyncedAt {
                row("Dernier sync", ts, mono: true)
            } else {
                row("Dernier sync", "jamais")
            }
            if let err = snap.lastErrorMessage {
                row("Dernière erreur", err)
            } else {
                row("Dernière erreur", "aucune")
            }
            if let url = snap.currentShareURL {
                row("URL currentShare", url, mono: true)
            }
        }
        Section {
            Button {
                UIPasteboard.general.string = renderPlainText(snap)
            } label: {
                Label("Copier tout le rapport", systemImage: "doc.on.doc")
            }
        } footer: {
            Text("Copie le contenu en texte pour le coller dans un email de support.")
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(mono ? .system(.footnote, design: .monospaced) : .footnote)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        snapshot = await sync.diagnosticSnapshot()
    }

    private func renderPlainText(_ s: CloudKitSyncService.DiagnosticSnapshot) -> String {
        """
        === RettApp — Diagnostic sync ===
        Compte iCloud       : \(s.accountStatus)
        Rôle                : \(s.role)
        Subscriptions       : \(s.subscriptionsRegistered ? "oui" : "non")

        Zone privée         : \(s.privateZoneExists ? "présente" : "absente")
        Share sur zone privée: \(s.privateZoneShareExists ? "oui" : "non")
        URL share privée    : \(s.privateZoneShareURL ?? "-")

        Zones partagées     : \(s.sharedZonesCount)
        \(s.sharedZones.map { "  - \($0)" }.joined(separator: "\n"))
        Share sur zone partagée: \(s.sharedZoneShareExists ? "oui" : "non")

        Écritures en attente: \(s.pendingWriteCount)
        Dernier sync        : \(s.lastSyncedAt ?? "jamais")
        Dernière erreur     : \(s.lastErrorMessage ?? "aucune")
        URL currentShare    : \(s.currentShareURL ?? "-")
        """
    }
}
