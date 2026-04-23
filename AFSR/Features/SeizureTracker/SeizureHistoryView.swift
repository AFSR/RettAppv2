import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SeizureHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SeizureEvent.startTime, order: .reverse) private var seizures: [SeizureEvent]

    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var toDelete: SeizureEvent?

    var body: some View {
        Group {
            if seizures.isEmpty {
                EmptyStateView(
                    title: "Aucune crise",
                    message: "Les crises enregistrées apparaîtront ici.",
                    systemImage: "waveform.path.ecg"
                )
            } else {
                List {
                    Section {
                        ForEach(seizures) { event in
                            SeizureRow(event: event)
                        }
                        .onDelete(perform: confirmDelete)
                    }
                }
            }
        }
        .navigationTitle("Historique")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fermer") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportCSV()
                } label: {
                    Label("Exporter CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(seizures.isEmpty)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .confirmationDialog(
            "Supprimer cette crise ?",
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
            presenting: toDelete
        ) { event in
            Button("Supprimer", role: .destructive) {
                modelContext.delete(event)
                try? modelContext.save()
                toDelete = nil
            }
            Button("Annuler", role: .cancel) { toDelete = nil }
        } message: { _ in
            Text("Cette action est irréversible.")
        }
    }

    private func confirmDelete(_ offsets: IndexSet) {
        guard let first = offsets.first else { return }
        toDelete = seizures[first]
    }

    private func exportCSV() {
        let formatter = ISO8601DateFormatter()
        var lines = ["id,start,end,duration_seconds,type,trigger,trigger_notes,notes"]
        for e in seizures {
            let fields = [
                e.id.uuidString,
                formatter.string(from: e.startTime),
                formatter.string(from: e.endTime),
                "\(e.durationSeconds)",
                e.seizureType.rawValue,
                e.trigger.rawValue,
                csvEscape(e.triggerNotes),
                csvEscape(e.notes)
            ]
            lines.append(fields.joined(separator: ","))
        }
        let csv = lines.joined(separator: "\n")
        let filename = "rettapp-crises-\(Int(Date().timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? csv.data(using: .utf8)?.write(to: url)
        exportURL = url
        showShareSheet = true
    }

    private func csvEscape(_ s: String) -> String {
        let needsQuotes = s.contains(",") || s.contains("\n") || s.contains("\"")
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }
}

private struct SeizureRow: View {
    let event: SeizureEvent
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(hex: event.seizureType.color))
                .frame(width: 12, height: 12)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.startTime, format: .dateTime.day().month().year().hour().minute())
                    .font(AFSRFont.body(16))
                HStack(spacing: 8) {
                    Text(event.formattedDuration)
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                    Text(event.seizureType.label)
                        .font(AFSRFont.caption())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: event.seizureType.color).opacity(0.2), in: Capsule())
                    if event.trigger != .none {
                        Text(event.trigger.label)
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                if !event.notes.isEmpty {
                    Text(event.notes)
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack { SeizureHistoryView() }
        .modelContainer(PreviewData.container)
}
