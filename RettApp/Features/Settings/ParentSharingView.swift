import SwiftUI
import SwiftData
import CloudKit

/// Sous-page Réglages → Partage entre parents.
/// L'invitation se fait **en présentiel via AirDrop** uniquement, par sécurité —
/// les deux iPhones doivent être à proximité au moment du partage.
struct ParentSharingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudKitSyncService.self) private var sync
    @Query private var profiles: [ChildProfile]

    @State private var sharingURL: URL?
    @State private var presentAirDropSheet = false
    @State private var presentInviteCard = false
    @State private var presentStopConfirm = false
    @State private var workingError: String?

    var body: some View {
        Form {
            accountSection
            shareStatusSection
            participantsSection
            actionsSection
            infoSection
        }
        .navigationTitle("Partage entre parents")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await sync.refreshAccountStatus()
            // Demande la permission de découvrir les autres participants par
            // e-mail / nom Apple ID (best effort — l'iOS gère la feuille système).
            await sync.requestParticipantsDiscoverability()
            await sync.refreshShareStatus()
        }
        .sheet(isPresented: $presentInviteCard) {
            if let url = sharingURL {
                InvitationCardView(
                    url: url,
                    childName: profiles.first?.fullName ?? "votre enfant",
                    onAirDrop: { presentAirDropSheet = true }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $presentAirDropSheet) {
            if let url = sharingURL {
                ProximityShareSheet(url: url, onComplete: {
                    presentAirDropSheet = false
                    Task { await sync.refreshShareStatus() }
                })
            }
        }
        .confirmationDialog(
            sync.role == .participant ? "Quitter le partage ?" : "Arrêter le partage ?",
            isPresented: $presentStopConfirm
        ) {
            Button(sync.role == .participant ? "Quitter" : "Arrêter", role: .destructive) {
                Task { await stopSharing() }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            if sync.role == .participant {
                Text("Vous n'aurez plus accès aux données partagées par l'autre parent. Vous pourrez à nouveau accepter une invitation depuis ce parent à tout moment.")
            } else {
                Text("L'autre parent ne pourra plus accéder ni modifier les données. Vous pourrez créer une nouvelle invitation à tout moment.")
            }
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

    @ViewBuilder
    private var participantsSection: some View {
        if sync.role == .none {
            EmptyView()
        } else {
            Section {
                if sync.participants.isEmpty {
                    HStack {
                        Image(systemName: "hourglass")
                            .foregroundStyle(.secondary)
                        Text("Récupération de la liste des participants…")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(sync.participants) { p in
                        ParticipantRow(participant: p)
                    }
                }
            } header: {
                Text("Parents avec accès")
            } footer: {
                Text("Les e-mails sont communiqués par CloudKit selon les Réglages iCloud du parent. Si seul « Apple ID anonyme » s'affiche, demandez-lui d'activer Réglages iOS → [son nom] → Contacts → Permettre aux autres de me trouver par e-mail.")
            }
        }
    }

    private var actionsSection: some View {
        Section {
            switch sync.role {
            case .none:
                Button {
                    Task { await createInvite() }
                } label: {
                    Label("Créer une invitation (AirDrop)", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(sync.accountStatus != .available || sync.syncState == .syncing)
            case .owner:
                Button {
                    Task { await regenerateInviteSheet() }
                } label: {
                    Label("Réenvoyer l'invitation par AirDrop", systemImage: "dot.radiowaves.left.and.right")
                }
                Button(role: .destructive) {
                    presentStopConfirm = true
                } label: {
                    Label("Arrêter le partage", systemImage: "xmark.circle")
                }
            case .participant:
                Button(role: .destructive) {
                    presentStopConfirm = true
                } label: {
                    Label("Quitter le partage", systemImage: "rectangle.portrait.and.arrow.forward")
                }
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
                Label {
                    Text("**Présentiel obligatoire** : l'invitation se transmet uniquement via AirDrop, donc en présence physique des deux appareils.")
                } icon: {
                    Image(systemName: "person.2.wave.2.fill").foregroundStyle(.afsrPurpleAdaptive)
                }
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
            // 1. Pousse l'existant pour que l'invité voie tout au moment d'accepter
            try await sync.replicateAll(from: modelContext)
            // 2. Crée le CKShare et obtient l'URL
            let url = try await sync.setupSharing(childProfile: profiles.first)
            sharingURL = url
            presentInviteCard = true
        } catch {
            workingError = error.localizedDescription
        }
    }

    private func regenerateInviteSheet() async {
        if let url = sync.currentShare?.url {
            sharingURL = url
            presentInviteCard = true
        } else {
            // pas de share local → en récupérer un
            await createInvite()
        }
    }

    private func stopSharing() async {
        do {
            switch sync.role {
            case .owner:       try await sync.stopSharing()
            case .participant: try await sync.leaveShare()
            case .none:        break
            }
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

// MARK: - Carte d'invitation (rappel proximité)

private struct InvitationCardView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let childName: String
    let onAirDrop: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.afsrPurpleAdaptive)
                        .padding(.top, 16)

                    VStack(spacing: 8) {
                        Text("Invitation prête")
                            .font(AFSRFont.title(24))
                        Text("Pour le suivi de \(childName)")
                            .font(AFSRFont.body(15))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        StepRow(number: "1", text: "Approchez les deux iPhones (à moins de 10 m).")
                        StepRow(number: "2", text: "Sur l'autre iPhone, AirDrop doit être activé (Centre de contrôle → AirDrop → Tout le monde 10 min ou Mes contacts).")
                        StepRow(number: "3", text: "Touchez « Envoyer par AirDrop » ci-dessous.")
                        StepRow(number: "4", text: "Sélectionnez l'autre iPhone dans la liste AirDrop qui s'affiche.")
                        StepRow(number: "5", text: "L'autre parent accepte l'invitation, l'appli RettApp s'ouvre et synchronise.")
                    }
                    .padding()
                    .background(Color.afsrPurpleAdaptive.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    Button {
                        onAirDrop()
                    } label: {
                        Label("Envoyer par AirDrop", systemImage: "dot.radiowaves.left.and.right")
                            .font(AFSRFont.headline(17))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AFSRTokens.minTapTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.afsrPurpleAdaptive)
                    .padding(.horizontal)

                    VStack(spacing: 4) {
                        Text("Pour des raisons de sécurité, l'invitation ne peut pas être envoyée par Messages, Mail ou un autre canal à distance.")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer(minLength: 16)
                }
            }
            .navigationTitle("Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

private struct ParticipantRow: View {
    let participant: ParticipantInfo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: participant.isOwner ? "crown.fill" : "person.fill")
                .foregroundStyle(participant.isOwner ? .afsrPurpleAdaptive : .secondary)
                .frame(width: 24, height: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(participant.bestLabel)
                        .font(AFSRFont.body(15))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if participant.isCurrentUser {
                        Text("(vous)")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                if let email = participant.email,
                   !email.isEmpty,
                   participant.displayName != nil {
                    Text(email)
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    Text(participant.isOwner ? "Propriétaire" : participant.permissionLabel)
                    Text("·")
                    Text(participant.acceptanceLabel)
                }
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct StepRow: View {
    let number: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(AFSRFont.headline(13))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.afsrPurpleAdaptive, in: Circle())
            Text(text)
                .font(AFSRFont.body(14))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
