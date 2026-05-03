import SwiftUI
import SwiftData
import UIKit

/// Workflow rapide pour importer une journée du cahier de suivi papier dans
/// l'app — alternative à la ressaisie manuelle dans le Journal.
///
/// Étapes :
///   1. L'utilisateur prend une photo de la page (VNDocumentCameraViewController)
///   2. OCR avec Vision (`BookletOCR`)
///   3. Parsing heuristique (`BookletParser`) pour pré-remplir un formulaire
///   4. L'utilisateur vérifie / complète et valide
///   5. Création ou mise à jour de la `DailyObservation` du jour ciblé
struct BookletImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query private var observations: [DailyObservation]

    @State private var step: Step = .start
    @State private var scanError: String?
    @State private var ocrText: String = ""
    @State private var processing = false
    @State private var extracted = BookletParser.Extracted()
    @State private var dayDate: Date = Calendar.current.startOfDay(for: Date())

    enum Step {
        case start          // accueil + bouton scanner
        case scanning       // VNDocumentCameraVC affichée
        case processing     // OCR en cours
        case review         // formulaire pré-rempli à valider
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Importer une journée")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                    if step == .review {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Enregistrer") { saveAndDismiss() }.bold()
                        }
                    }
                }
        }
        .alert("Scan impossible", isPresented: Binding(
            get: { scanError != nil },
            set: { if !$0 { scanError = nil } }
        ), presenting: scanError) { _ in
            Button("OK") { scanError = nil }
        } message: { e in
            Text(e)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .start:           startView
        case .scanning:        scannerSheet
        case .processing:      processingView
        case .review:          reviewForm
        }
    }

    // MARK: - Steps

    private var startView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.afsrPurpleAdaptive)
                    .padding(.top, 24)
                Text("Scanner une page du cahier")
                    .font(AFSRFont.title(20))
                Text("Prenez une photo de la page papier remplie par l'école ou le centre. RettApp lira automatiquement les repas, le sommeil, l'hydratation et les remarques pour pré-remplir le journal du jour.")
                    .font(AFSRFont.body(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    step = .scanning
                } label: {
                    Label("Prendre une photo", systemImage: "camera.fill")
                        .font(AFSRFont.headline(15))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.afsrPurpleAdaptive)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Text("Astuce : posez la page à plat sur une surface bien éclairée. L'iPhone ajuste les bords automatiquement.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 4)

                Spacer()
            }
        }
    }

    private var scannerSheet: some View {
        BookletScannerView { result in
            switch result {
            case .success(let images):
                step = .processing
                Task { await runOCR(images: images) }
            case .cancelled:
                step = .start
            case .failed(let err):
                scanError = err.localizedDescription
                step = .start
            }
        }
        .ignoresSafeArea()
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Lecture de la page…")
                .font(AFSRFont.body(15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reviewForm: some View {
        Form {
            Section {
                DatePicker("Date du jour", selection: $dayDate, displayedComponents: .date)
            } header: {
                Text("Journée concernée")
            } footer: {
                Text("Si une fiche existe déjà pour ce jour, les champs renseignés ci-dessous remplaceront les valeurs précédentes.")
            }

            Section("Repas") {
                ratingRow("Petit-déjeuner", $extracted.breakfastRating, notes: $extracted.breakfastNotes)
                ratingRow("Déjeuner", $extracted.lunchRating, notes: $extracted.lunchNotes)
                ratingRow("Goûter", $extracted.snackRating, notes: $extracted.snackNotes)
                ratingRow("Dîner", $extracted.dinnerRating, notes: $extracted.dinnerNotes)
            }

            Section("Hydratation") {
                ratingRow("Hydratation", $extracted.hydrationRating, notes: $extracted.hydrationNotes)
            }

            Section("Sommeil") {
                ratingRow("Nuit (qualité)", $extracted.nightSleepRating, notes: $extracted.nightSleepNotes)
                durationRow("Durée nuit", minutes: $extracted.nightSleepDurationMinutes)
                durationRow("Durée sieste", minutes: $extracted.napDurationMinutes)
                if !extracted.napNotes.isEmpty {
                    TextField("Notes sieste", text: $extracted.napNotes, axis: .vertical)
                        .lineLimit(1...3)
                }
            }

            Section("Remarques") {
                TextField("Notes générales", text: $extracted.generalNotes, axis: .vertical)
                    .lineLimit(2...8)
            }

            if !ocrText.isEmpty {
                Section("Texte OCR brut (pour vérification)") {
                    Text(ocrText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func ratingRow(_ label: String, _ value: Binding<Int>, notes: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(AFSRFont.body(14))
                Spacer()
                Stepper(value: value, in: 0...5) {
                    Text(value.wrappedValue == 0 ? "—" : "\(value.wrappedValue)/5")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 140)
            }
            TextField("Notes (optionnel)", text: notes, axis: .vertical)
                .font(AFSRFont.caption())
                .lineLimit(1...3)
        }
    }

    @ViewBuilder
    private func durationRow(_ label: String, minutes: Binding<Int>) -> some View {
        HStack {
            Text(label).font(AFSRFont.body(14))
            Spacer()
            Stepper(value: minutes, in: 0...720, step: 15) {
                Text(formatMinutes(minutes.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 160)
        }
    }

    // MARK: - Pipeline

    private func runOCR(images: [UIImage]) async {
        var combined: [String] = []
        for image in images {
            do {
                let txt = try await BookletOCR.recognizeText(from: image)
                if !txt.isEmpty { combined.append(txt) }
            } catch {
                scanError = "L'OCR a échoué : \(error.localizedDescription)"
                step = .start
                return
            }
        }
        let allText = combined.joined(separator: "\n\n")
        ocrText = allText
        let parsed = BookletParser.parse(allText)
        extracted = parsed
        if let parsedDate = parsed.dayDate {
            dayDate = parsedDate
        }
        step = .review
    }

    private func saveAndDismiss() {
        let day = Calendar.current.startOfDay(for: dayDate)
        let existing = observations.first { Calendar.current.isDate($0.dayStart, inSameDayAs: day) }
        let target: DailyObservation
        if let existing {
            target = existing
        } else {
            target = DailyObservation(
                dayStart: day,
                childProfileId: profiles.first?.id
            )
            modelContext.insert(target)
        }

        // On n'écrase une valeur existante que si on a quelque chose de neuf.
        if extracted.breakfastRating > 0 { target.breakfastRatingRaw = extracted.breakfastRating }
        if !extracted.breakfastNotes.isEmpty { target.breakfastNotes = extracted.breakfastNotes }
        if extracted.lunchRating > 0 { target.lunchRatingRaw = extracted.lunchRating }
        if !extracted.lunchNotes.isEmpty { target.lunchNotes = extracted.lunchNotes }
        if extracted.snackRating > 0 { target.snackRatingRaw = extracted.snackRating }
        if !extracted.snackNotes.isEmpty { target.snackNotes = extracted.snackNotes }
        if extracted.dinnerRating > 0 { target.dinnerRatingRaw = extracted.dinnerRating }
        if !extracted.dinnerNotes.isEmpty { target.dinnerNotes = extracted.dinnerNotes }
        if extracted.hydrationRating > 0 { target.hydrationRatingRaw = extracted.hydrationRating }
        if !extracted.hydrationNotes.isEmpty { target.hydrationNotes = extracted.hydrationNotes }
        if extracted.nightSleepRating > 0 { target.nightSleepRatingRaw = extracted.nightSleepRating }
        if extracted.nightSleepDurationMinutes > 0 { target.nightSleepDurationMinutes = extracted.nightSleepDurationMinutes }
        if !extracted.nightSleepNotes.isEmpty { target.nightSleepNotes = extracted.nightSleepNotes }
        if extracted.napDurationMinutes > 0 { target.napDurationMinutes = extracted.napDurationMinutes }
        if !extracted.napNotes.isEmpty { target.napNotes = extracted.napNotes }
        if !extracted.generalNotes.isEmpty {
            if !target.generalNotes.isEmpty { target.generalNotes += "\n" }
            target.generalNotes += extracted.generalNotes
        }
        try? modelContext.save()
        dismiss()
    }

    private func formatMinutes(_ m: Int) -> String {
        if m == 0 { return "—" }
        let h = m / 60
        let r = m % 60
        if h == 0 { return "\(r) min" }
        if r == 0 { return "\(h) h" }
        return "\(h) h \(r) min"
    }
}
