import SwiftUI
import SwiftData

/// Corbeille : ce qui a été supprimé ces trente derniers jours, et de quoi le
/// remettre en place.
///
/// Restaurer repasse par le chemin d'import, donc l'élément est réinséré,
/// horodaté et remis en file vers CloudKit : l'autre parent le récupère comme
/// n'importe quelle modification.
struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudKitSyncService.self) private var sync

    @State private var items: [TrashStore.Item] = []
    @State private var toRestore: TrashStore.Item?
    @State private var toForget: TrashStore.Item?
    @State private var message: String?

    var body: some View {
        List {
            if items.isEmpty {
                Section {
                    Text("Rien n'a été supprimé ces trente derniers jours.")
                        .font(AFSRFont.body(15))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } else {
                Section {
                    ForEach(items) { item in
                        row(item)
                    }
                } header: {
                    Text("Supprimé récemment")
                } footer: {
                    Text("Chaque élément reste récupérable trente jours, puis disparaît définitivement. Restaurer le remet aussi chez l'autre parent.")
                }
            }
        }
        .navigationTitle("Corbeille")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: TrashStore.didChangeNotification)) { _ in
            reload()
        }
        .confirmationDialog(
            "Restaurer cet élément ?",
            isPresented: Binding(get: { toRestore != nil }, set: { if !$0 { toRestore = nil } }),
            presenting: toRestore
        ) { item in
            Button("Restaurer") { restore(item) }
            Button("Annuler", role: .cancel) { toRestore = nil }
        } message: { item in
            Text(item.summary)
        }
        .confirmationDialog(
            "Supprimer définitivement ?",
            isPresented: Binding(get: { toForget != nil }, set: { if !$0 { toForget = nil } }),
            presenting: toForget
        ) { item in
            Button("Supprimer définitivement", role: .destructive) {
                TrashStore.forget(id: item.id)
                toForget = nil
            }
            Button("Annuler", role: .cancel) { toForget = nil }
        } message: { _ in
            Text("Cette action ne peut pas être annulée.")
        }
        .alert("Corbeille", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func row(_ item: TrashStore.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.summary)
                .font(AFSRFont.body(15))
            HStack(spacing: 6) {
                Text("Supprimé le \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                Text("·")
                Text(remainingLabel(item))
            }
            .font(AFSRFont.caption())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                toForget = item
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
            Button {
                toRestore = item
            } label: {
                Label("Restaurer", systemImage: "arrow.uturn.backward")
            }
            .tint(.afsrPurpleAdaptive)
        }
        .contentShape(Rectangle())
        .onTapGesture { toRestore = item }
    }

    private func remainingLabel(_ item: TrashStore.Item) -> String {
        let jours = Calendar.current.dateComponents(
            [.day], from: Date(), to: item.expiresAt
        ).day ?? 0
        if jours <= 0 { return "expire aujourd'hui" }
        return jours == 1 ? "expire demain" : "expire dans \(jours) jours"
    }

    private func reload() {
        items = TrashStore.items()
    }

    private func restore(_ item: TrashStore.Item) {
        toRestore = nil
        Task { @MainActor in
            let result = await TrashStore.restore(item, context: modelContext)
            reload()
            if result.errors.isEmpty {
                message = "« \(item.summary) » a été restauré."
                sync.scheduleSync(context: modelContext, priority: .urgent)
            } else {
                message = result.errors.joined(separator: "\n")
            }
        }
    }
}

#Preview {
    NavigationStack { TrashView() }
        .modelContainer(PreviewData.container)
        .environment(CloudKitSyncService())
}
