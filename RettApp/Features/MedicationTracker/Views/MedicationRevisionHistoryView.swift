import SwiftUI
import SwiftData

/// Timeline read-only des révisions d'un médicament. Affiche chaque snapshot
/// daté (effectiveFrom) avec le nom, la dose principale, le nombre de prises,
/// l'état actif/inactif et l'état des notifications. Sert au bilan
/// rétrospectif (« quel était le plan il y a 3 mois ? ») et à l'audit
/// médical des changements de dosage.
struct MedicationRevisionHistoryView: View {
    let medicationId: UUID
    let medicationName: String

    @Query private var revisions: [MedicationRevision]

    init(medicationId: UUID, medicationName: String) {
        self.medicationId = medicationId
        self.medicationName = medicationName
        // @Query filtré côté SwiftData — plus efficace que filter() en
        // mémoire, surtout quand le nombre de révisions grandit.
        let medID = medicationId
        _revisions = Query(
            filter: #Predicate<MedicationRevision> { $0.medicationId == medID },
            sort: [SortDescriptor(\.effectiveFrom, order: .reverse)]
        )
    }

    var body: some View {
        List {
            if revisions.isEmpty {
                emptyState
            } else {
                ForEach(Array(revisions.enumerated()), id: \.element.id) { idx, rev in
                    revisionRow(rev, isCurrent: idx == 0)
                }
            }
        }
        .navigationTitle("Historique")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Aucune révision enregistrée")
                .font(AFSRFont.headline(15))
            Text("Une révision est créée à chaque modification du médicament. Modifiez le dosage, les horaires ou l'état pour voir apparaître la première entrée.")
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func revisionRow(_ rev: MedicationRevision, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rev.effectiveFrom, format: .dateTime.day().month().year().hour().minute())
                    .font(AFSRFont.headline(14))
                Spacer()
                if isCurrent {
                    Text("Version actuelle")
                        .font(AFSRFont.caption())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.afsrSuccess.opacity(0.15), in: Capsule())
                        .foregroundStyle(.afsrSuccess)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "pills.fill")
                    .foregroundStyle(.afsrPurpleAdaptive)
                    .font(.system(size: 13))
                Text(rev.name).font(AFSRFont.body(14))
            }

            HStack(spacing: 12) {
                Label(doseLabel(for: rev), systemImage: "scalemass")
                if rev.kind == .regular {
                    Label("\(rev.intakes.count) prise\(rev.intakes.count > 1 ? "s" : "")",
                          systemImage: "clock")
                }
                if !rev.isActive {
                    Label("Inactif", systemImage: "pause.circle")
                        .foregroundStyle(.afsrWarning)
                }
                if rev.kind == .regular && !rev.notifyEnabled {
                    Label("Sans rappel", systemImage: "bell.slash")
                }
            }
            .font(AFSRFont.caption())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func doseLabel(for rev: MedicationRevision) -> String {
        let value = rev.doseAmount
        let formatted: String = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
        return "\(formatted) \(rev.doseUnit.label)"
    }
}
