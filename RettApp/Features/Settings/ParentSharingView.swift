import SwiftUI
import SwiftData
import CloudKit

/// Sous-page Réglages → Partage entre parents.
/// Statut iCloud, création/gestion de l'invitation, sync manuelle bidirectionnelle.
struct ParentSharingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudKitSyncService.self) private var sync
    @Query private var profiles: [ChildProfile]

    @State private var sharingURL: URL?
    @State private var presentNativeShareController = false
    @State private var presentLinkShareSheet = false
    @State private var workingError: String?

    var body: some View {
        Form {
            accountSection
            shareStatusSection
            actionsSection
            infoSection
        }
        .navigationTitle("Partage entre parents")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await sync.refreshAccountStatus()
            await sync.refreshShareStatus()
        }
        .sheet(isPresented: $presentNativeShareController) {
            if let share = sync.currentShare {
                CloudSharingSheet(
                    share: share,
                    container: CKContainer(identifier: CloudKitSyncService.containerID),
                    onSaveCompleted: {
                        Task { await sync.refreshShareStatus() }
                    },
                    onStopSharing: {
                        Task { await sync.refreshShareStatus() }
                    }
                )
            }
        }
        .sheet(isPresented: $presentLinkShareSheet) {
            if let url = sharingURL { ShareSheet(items: [url]) }
        }
        .alert("Erreur de synchronisation", isPresented: Binding(
            get: { workingError != nil },
            set: { if !$0 { workingError = nil } }
        ), presenting: workingError) { _ in
            Button("OK") { workingError = nil }
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            HStack {
                Image(systemName: "icloud.fill")
                    .foregroundStyle(.afsrPurpleAdaptive)
                Text("Compte iCloud")
                Spacer()
                Text(accountLabel)
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Compte")
        } footer: {
            if sync.accountStatus != .available {
                Text("Activez iCloud dans Réglages iOS → [votre nom] → iCloud, puis revenez sur cette page.")
            } else {
                Text("Le partage utilise iCloud comme canal sécurisé entre les deux appareils.")
            }
        }
    }

    private var accountLabel: String {
        switch sync.accountStatus {
        case .unknown:     return "Vérification…"
        case .available:   return "Connecté"
        case .noAccount:   return "Non connecté"
        case .restricted:  return "Restreint"
        case .unavailable: return "Indisponible"
        }
    }

    private var shareStatusSection: some View {
        Section {
            HStack {
                Image(systemName: roleIcon)
                    .foregroundStyle(roleColor)
                VStack(alignment: .leading) {
                    Text(roleTitle).font(AFSRFont.body(15))
                    if !roleSubtitle.isEmpty {
                        Text(roleSubtitle)
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let last = sync.lastSyncedAt {
                HStack {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .foregroundStyle(.secondary)
                    Text("Dernière synchronisation")
                    Spacer()
                    Text(last, format: .relative(presentation: .numeric))
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Statut")
        }
    }

    private var roleIcon: String {
        switch sync.role {
        case .none: return "person.crop.circle.badge.questionmark"
        case .owner: return "person.crop.circle.fill.badge.checkmark"
        case .participant: return "person.2.fill"
        }
    }
    private var roleColor: Color {
        switch sync.role {
        case .none: return .secondary
        case .owner: return .afsrSuccess
        case .participant: return .afsrPurpleAdaptive
        }
    }
    private var roleTitle: String {
        switch sync.role {
        case .none: return "Aucun partage actif"
        case .owner:
            if sync.participantCount > 0 {
                return "Partagé avec \(sync.participantCount) parent\(sync.participantCount > 1 ? "s" : "")"
            }
            return "Invitation prête à envoyer"
        case .participant: return "Vous avez accepté l'invitation d'un autre parent"
        }
    }
    private var roleSubtitle: String {
        switch sync.role {
        case .none: return "Créez une invitation pour synchroniser le suivi avec un autre parent."
        case .owner: return "Vous êtes le propriétaire des données partagées."
        case .participant: return "Les modifications sont visibles des deux côtés."
        }
    }

    private var actionsSection: some View {
        Section {
            switch sync.role {
            case .none:
                Button {
                    Task { await createInvite() }
                } label: {
                    Label("Créer une invitation", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(sync.accountStatus != .available || sync.syncState == .syncing)
            case .owner:
                Button {
                    presentNativeShareController = true
                } label: {
                    Label("Gérer les participants", systemImage: "person.2")
                }
                if let share = sync.currentShare, let url = share.url {
                    Button {
                        sharingURL = url
                        presentLinkShareSheet = true
                    } label: {
                        Label("Renvoyer le lien d'invitation", systemImage: "link")
                    }
                }
            case .participant:
                EmptyView()
            }
            Button {
                Task { await syncNow() }
            } label: {
                HStack {
                    if sync.syncState == .syncing { ProgressView().controlSize(.small) }
                    Label(sync.syncState == .syncing ? "Synchronisation…" : "Synchroniser maintenant",
                          systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(sync.accountStatus != .available || sync.syncState == .syncing)
        } header: {
            Text("Actions")
        } footer: {
            Text("La synchronisation pousse vos données locales puis tire les changements de l'autre parent. À déclencher après chaque session importante de saisie.")
        }
    }

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Données chiffrées par iCloud (TLS + chiffrement au repos).", systemImage: "lock.shield.fill")
                Label("Aucun serveur AFSR ou tiers n'est impliqué.", systemImage: "checkmark.shield.fill")
                Label("L'invité peut révoquer son accès à tout moment depuis ses Réglages iCloud.", systemImage: "person.crop.circle.badge.xmark")
            }
            .font(AFSRFont.caption())
            .foregroundStyle(.secondary)
        } header: {
            Text("Sécurité")
        }
    }

    // MARK: - Actions

    private func createInvite() async {
        do {
            // 1. Pousse les données existantes pour que l'invité voie tout au moment d'accepter
            try await sync.replicateAll(from: modelContext)
            // 2. Crée le CKShare et obtient l'URL d'invitation
            let url = try await sync.setupSharing(childProfile: profiles.first)
            sharingURL = url
            // 3. Présente le UICloudSharingController natif (gère destinataires, perms, etc.)
            presentNativeShareController = true
        } catch {
            workingError = error.localizedDescription
        }
    }

    private func syncNow() async {
        do {
            try await sync.replicateAll(from: modelContext)
            try await sync.pullChanges(into: modelContext)
        } catch {
            workingError = error.localizedDescription
        }
    }
}
