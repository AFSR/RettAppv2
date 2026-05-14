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

    @State private var presentShareSheet = false
    @State private var presentStopConfirm = false
    @State private var participantToRemove: ParticipantInfo?
    @State private var workingError: String?
    @State private var presentResetConfirm = false
    @State private var isResetting = false

    var body: some View {
        Form {
            accountSection
            shareStatusSection
            participantsSection
            if !sync.recentRemoteActivity.isEmpty {
                activityTimelineSection
            }
            actionsSection
            if sync.role != .none {
                troubleshootSection
            }
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
        .sheet(isPresented: $presentShareSheet) {
            CloudShareSheet(
                prepareShare: {
                    do {
                        let result = try await sync.prepareShareForController(
                            childProfile: profiles.first,
                            context: modelContext
                        )
                        return .success(result)
                    } catch {
                        return .failure(error)
                    }
                },
                title: "Suivi RettApp — \(profiles.first?.fullName ?? "enfant")",
                onSaved: { _ in
                    Task { await sync.refreshShareStatus() }
                },
                onStopped: {
                    Task { await sync.refreshShareStatus() }
                },
                onFailed: { error in
                    workingError = error.localizedDescription
                }
            )
            .ignoresSafeArea()
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
        .confirmationDialog(
            "Retirer l'accès à \(participantToRemove?.bestLabel ?? "") ?",
            isPresented: Binding(
                get: { participantToRemove != nil },
                set: { if !$0 { participantToRemove = nil } }
            ),
            presenting: participantToRemove
        ) { p in
            Button("Retirer l'accès", role: .destructive) {
                Task { await removeParticipant(p) }
            }
            Button("Annuler", role: .cancel) { participantToRemove = nil }
        } message: { p in
            Text("\(p.bestLabel) ne pourra plus accéder ni modifier les données. Cette action est immédiate. Vous pourrez réinviter ce parent à tout moment.")
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
        case .none:
            return "Aucun partage actif"
        case .owner:
            let accepted = sync.participants.filter { !$0.isOwner && $0.acceptanceStatus == .accepted }.count
            let pending = sync.participants.filter { !$0.isOwner && $0.acceptanceStatus == .pending }.count
            if accepted > 0 {
                return "Partagé avec \(accepted) parent\(accepted > 1 ? "s" : "")"
            }
            if pending > 0 {
                return "Invitation envoyée — en attente d'acceptation"
            }
            return "Invitation prête à envoyer"
        case .participant:
            if let name = sync.ownerDisplayNameFromShare, !name.isEmpty {
                return "Partagé par \(name)"
            }
            return "Vous avez accepté l'invitation d'un autre parent"
        }
    }
    private var roleSubtitle: String {
        switch sync.role {
        case .none:
            return "Créez une invitation pour synchroniser le suivi avec un autre parent."
        case .owner:
            return "Vous êtes le propriétaire des données partagées."
        case .participant:
            return "Les modifications faites par les deux parents sont automatiquement synchronisées."
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
                            .swipeActions(edge: .trailing) {
                                if sync.role == .owner && !p.isOwner {
                                    Button(role: .destructive) {
                                        participantToRemove = p
                                    } label: {
                                        Label("Retirer l'accès", systemImage: "person.crop.circle.badge.minus")
                                    }
                                }
                            }
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
                    presentShareSheet = true
                } label: {
                    Label("Inviter un autre parent", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(sync.accountStatus != .available || sync.syncState == .syncing)
            case .owner:
                Button {
                    presentShareSheet = true
                } label: {
                    Label("Gérer le partage / inviter un autre parent", systemImage: "person.2.badge.gearshape")
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
            Text("L'invitation utilise la feuille de partage iOS native : AirDrop apparaît automatiquement quand les deux iPhones sont à proximité, et le destinataire reçoit une notification d'acceptation. La synchronisation se fait automatiquement à l'ouverture de l'app et après chaque saisie importante.")
        }
    }

    private var activityTimelineSection: some View {
        Section {
            ForEach(sync.recentRemoteActivity.prefix(10)) { activity in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: activity.entity.icon)
                        .foregroundStyle(.afsrPurpleAdaptive)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activityLabel(activity))
                            .font(AFSRFont.body(14))
                        Text(activity.timestamp, format: .relative(presentation: .numeric))
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Activité distante récente")
        } footer: {
            Text("Changements rapatriés depuis l'autre parent lors des dernières synchronisations.")
        }
    }

    private func activityLabel(_ activity: RemoteActivity) -> String {
        let owner = sync.ownerDisplayNameFromShare?.isEmpty == false
            ? sync.ownerDisplayNameFromShare!
            : "L'autre parent"
        let entityLabel = activity.count > 1 ? activity.entity.pluralLabel : activity.entity.label
        let verb = activity.count > 1 ? "a ajouté" : "a ajouté"
        return "\(owner) \(verb) \(activity.count) \(entityLabel)"
    }

    private var troubleshootSection: some View {
        Section {
            Button(role: .destructive) {
                presentResetConfirm = true
            } label: {
                HStack {
                    if isResetting { ProgressView().controlSize(.small) }
                    Label(isResetting ? "Réinitialisation…" : "Réinitialiser la synchronisation",
                          systemImage: "arrow.counterclockwise.circle")
                }
            }
            .disabled(isResetting || sync.syncState == .syncing)
        } header: {
            Text("Dépannage")
        } footer: {
            Text("À utiliser uniquement si la synchronisation semble bloquée. Cette action efface les marqueurs internes côté appareil (tokens de changement, abonnements push) puis pousse vos données locales et retire l'intégralité du contenu partagé depuis iCloud. Vos données restent intactes ; le partage et l'autre parent ne sont pas affectés.")
        }
        .confirmationDialog(
            "Réinitialiser la synchronisation ?",
            isPresented: $presentResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Réinitialiser", role: .destructive) {
                Task { await resetSync() }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("L'opération peut prendre quelques dizaines de secondes selon le volume de données.")
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

    private func removeParticipant(_ p: ParticipantInfo) async {
        do {
            try await sync.removeParticipant(p)
            participantToRemove = nil
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

    private func resetSync() async {
        isResetting = true
        defer { isResetting = false }
        do {
            try await sync.resetSyncState(context: modelContext)
        } catch {
            workingError = error.localizedDescription
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

