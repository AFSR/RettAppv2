import SwiftUI
import SwiftData

/// Page de diagnostic technique de la couche de partage CloudKit.
///
/// Quand la synchronisation coince, la famille photographie cet écran et nous
/// l'envoie : rôle, zones privée et partagée, abonnements, dernière erreur.
///
/// ⚠️ **Aucun lien de partage ne doit paraître ici, ni dans le rapport copié.**
/// L'URL d'un `CKShare` est la clé d'accès, pas une référence : notre partage
/// est en `publicPermission = .readWrite`, donc quiconque l'ouvre rejoint le
/// partage et lit tout le suivi médical de l'enfant. Elle a été affichée ici
/// en clair et sélectionnable, et le bouton « Copier » la mettait dans un
/// courriel de support — on demandait aux familles de confier à l'AFSR une clé
/// de leur dossier, par le canal que la règle « AirDrop seulement » existe
/// pour fermer.
///
/// Ce qui reste est l'état : un partage existe-t-il, le serveur a-t-il émis son
/// lien. C'est tout ce que le diagnostic avait à dire ; l'adresse elle-même
/// n'a jamais servi à personne ici.
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
                    Text("Un ping CloudKit qui affiche l'état du partage sur cet appareil : rôle, zones existantes, abonnements, dernière erreur. À joindre en capture d'écran si vous nous contactez — il ne contient aucun lien d'accès à vos données.")
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
            // L'état, jamais l'adresse. Un partage sans lien émis est un cas
            // réel — la copie locale récupérée à la place de l'enregistrement
            // serveur — et c'est ce que cette ligne sert à voir.
            row("Lien d'invitation émis ?", snap.privateZoneShareHasURL ? "oui" : "non")
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
            row("Dernière erreur", Self.sansLien(snap.lastErrorMessage) ?? "aucune")
            row("Lien du partage courant émis ?", snap.currentShareHasURL ? "oui" : "non")
        }
        Section {
            Button {
                UIPasteboard.general.string = renderPlainText(snap)
            } label: {
                Label("Copier tout le rapport", systemImage: "doc.on.doc")
            }
        } footer: {
            Text("Copie l'état de la synchronisation, à coller dans un courriel de support. Aucun lien de partage n'y figure : un lien d'invitation donne accès au suivi, il ne s'envoie que par AirDrop, en main propre.")
        }
    }

    /// Retire d'un message d'erreur tout ce qui ressemble à une adresse web.
    ///
    /// Le message vient de CloudKit et part tel quel dans le rapport de
    /// support. Rien ne garantit qu'il ne cite jamais l'URL du partage, et
    /// cette URL est une clé d'accès au dossier de l'enfant. Le diagnostic est
    /// le seul endroit où un texte libre du système sort de l'appareil : il
    /// est donc filtré, plutôt que de parier sur ce qu'Apple y met.
    static func sansLien(_ message: String?) -> String? {
        guard let message else { return nil }
        let filtre = message
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { mot -> Substring in
                let bas = mot.lowercased()
                return bas.contains("http") || bas.contains("icloud.com")
                    ? "[lien retiré]"
                    : mot
            }
            .joined(separator: " ")
        return filtre
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
        Lien émis           : \(s.privateZoneShareHasURL ? "oui" : "non")

        Zones partagées     : \(s.sharedZonesCount)
        \(s.sharedZones.map { "  - \($0)" }.joined(separator: "\n"))
        Share sur zone partagée: \(s.sharedZoneShareExists ? "oui" : "non")

        Écritures en attente: \(s.pendingWriteCount)
        Dernier sync        : \(s.lastSyncedAt ?? "jamais")
        Dernière erreur     : \(Self.sansLien(s.lastErrorMessage) ?? "aucune")
        Lien partage courant: \(s.currentShareHasURL ? "oui" : "non")
        """
    }
}
