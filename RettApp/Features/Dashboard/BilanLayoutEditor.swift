import SwiftUI

/// Feuille « Personnaliser le Bilan » : on coche ce qu'on veut voir, on
/// glisse pour changer l'ordre. Le mode édition reste actif en permanence
/// pour que les poignées de déplacement soient visibles sans geste caché.
struct BilanLayoutEditor: View {
    let store: BilanLayoutStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.entries) { entry in
                        Toggle(isOn: Binding(
                            get: { store.isVisible(entry.chart) },
                            set: { store.setVisible(entry.chart, $0) }
                        )) {
                            Label(entry.chart.title, systemImage: entry.chart.systemImage)
                        }
                        .tint(.afsrPurpleAdaptive)
                    }
                    .onMove { store.move(from: $0, to: $1) }
                } footer: {
                    Text("Glissez les lignes pour changer l'ordre. Seuls les graphiques cochés apparaissent dans le Bilan. Ce choix reste sur cet iPhone.")
                }

                Section {
                    Button("Rétablir l'affichage par défaut", role: .destructive) {
                        store.reset()
                    }
                    .disabled(store.isDefault)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Personnaliser le Bilan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
