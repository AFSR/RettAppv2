import SwiftUI
import SwiftData
import UIKit

/// Workflow d'import d'une journée du cahier de suivi papier.
///
/// Étapes :
///   1. Présentation : explication + bouton « Prendre une photo »
///   2. Scan : VNDocumentCameraViewController présenté en plein écran
///      (`.fullScreenCover`) — c'est la seule présentation correcte pour ce VC.
///      Une présentation embarquée inline ne déclenchait pas la session caméra
///      ⇒ « rien ne se passe » côté utilisateur (V1).
///   3. OCR : feedback de progression page par page (« Lecture de la page 1/2… »)
///   4. Review : formulaire pré-rempli côte à côte avec la photo pour
///      vérification visuelle. Le parser s'aligne sur les codes du nouveau
///      cahier (R/P/M/B/T pour les repas, 0/1/2-3/4+ pour les crises, etc.).
///   5. Save : crée ou met à jour la `DailyObservation` du jour ciblé.
struct BookletImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query private var observations: [DailyObservation]

    enum Phase {
        case intro
        case ocr           // OCR en cours — affiche un loader avec progression
        case review        // formulaire à valider
    }

    @State private var phase: Phase = .intro
    @State private var showScanner = false
    @State private var ocrProgress: String = ""
    @State private var scanError: String?
    @State private var scannedImages: [UIImage] = []
    @State private var ocrText: String = ""
    @State private var extracted = BookletParser.Extracted()
    @State private var dayDate: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Importer une journée")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                    if phase == .review {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Enregistrer") { saveAndDismiss() }.bold()
                        }
                    }
                }
        }
        // VNDocumentCameraVC en plein écran : c'est la seule présentation correcte.
        .fullScreenCover(isPresented: $showScanner) {
            BookletScannerView { result in
                showScanner = false
                handleScanResult(result)
            }
            .ignoresSafeArea()
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
        switch phase {
        case .intro:   introView
        case .ocr:     ocrLoadingView
        case .review:  reviewForm
        }
    }

    // MARK: - Intro

    private var introView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.afsrPurpleAdaptive)
                    .padding(.top, 24)
                Text("Scanner une page du cahier")
                    .font(AFSRFont.title(20))
                Text("Prenez une photo de la page papier remplie par l'école ou le centre. RettApp détectera la date, les repas, le sommeil, l'hydratation et les remarques pour pré-remplir le journal du jour.")
                    .font(AFSRFont.body(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showScanner = true
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

                VStack(alignment: .leading, spacing: 6) {
                    Label("Posez la page à plat sur une surface bien éclairée.", systemImage: "lightbulb")
                    Label("L'iPhone détecte les bords automatiquement.", systemImage: "rectangle.dashed")
                    Label("Comme le cahier utilise des cases à cocher, la lecture sera approximative — vérifiez le formulaire avant d'enregistrer.", systemImage: "checkmark.circle")
                }
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .padding(.top, 4)

                Spacer()
            }
        }
    }

    // MARK: - OCR loading

    private var ocrLoadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text(ocrProgress.isEmpty ? "Analyse en cours…" : ocrProgress)
                .font(AFSRFont.body(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            // Aperçu des miniatures déjà capturées pour rassurer l'utilisateur
            // que la prise de photo a bien été enregistrée.
            if !scannedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(scannedImages.enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 70, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 110)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Review form

    private var reviewForm: some View {
        Form {
            // Aperçu de la page scannée pour comparer pendant la saisie.
            if !scannedImages.isEmpty {
                Section("Page scannée (référence)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(scannedImages.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
                }
            }

            Section {
                DatePicker("Date du jour", selection: $dayDate, displayedComponents: .date)
            } header: {
                Text("Journée concernée")
            } footer: {
                Text("Si une fiche existe déjà pour ce jour, les champs renseignés ci-dessous remplaceront les valeurs précédentes.")
            }

            Section("Repas") {
                ratingRow("Petit-déjeuner", $extracted.breakfastRating)
                ratingRow("Déjeuner", $extracted.lunchRating)
                ratingRow("Goûter", $extracted.snackRating)
                ratingRow("Dîner", $extracted.dinnerRating)
            }

            Section("Hydratation") {
                ratingRow("Hydratation", $extracted.hydrationRating)
            }

            Section("Sommeil") {
                ratingRow("Nuit (qualité)", $extracted.nightSleepRating)
                durationRow("Durée nuit", minutes: $extracted.nightSleepDurationMinutes)
                durationRow("Durée sieste", minutes: $extracted.napDurationMinutes)
            }

            Section("Notes générales (optionnel)") {
                TextField("Tout ajout libre que vous souhaitez consigner", text: $extracted.generalNotes, axis: .vertical)
                    .lineLimit(1...4)
            }

            if !ocrText.isEmpty {
                Section {
                    DisclosureGroup("Texte OCR brut (vérification)") {
                        Text(ocrText)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ratingRow(_ label: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(label).font(AFSRFont.body(14))
            Spacer()
            Picker("", selection: value) {
                Text("—").tag(0)
                Text("R").tag(1)
                Text("P").tag(2)
                Text("M").tag(3)
                Text("B").tag(4)
                Text("T").tag(5)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
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

    // MARK: - Scan result

    private func handleScanResult(_ result: BookletScannerView.Result) {
        switch result {
        case .success(let images):
            scannedImages = images
            phase = .ocr
            ocrProgress = "Préparation…"
            Task { await runOCR(images: images) }
        case .cancelled:
            // L'utilisateur a fermé le scanner sans prendre de photo — on
            // reste sur l'intro pour qu'il puisse réessayer.
            phase = .intro
        case .failed(let err):
            scanError = err.localizedDescription
            phase = .intro
        }
    }

    // MARK: - OCR pipeline

    @MainActor
    private func runOCR(images: [UIImage]) async {
        var combined: [String] = []
        for (idx, image) in images.enumerated() {
            ocrProgress = "Lecture de la page \(idx + 1)/\(images.count)…"
            do {
                let txt = try await BookletOCR.recognizeText(from: image)
                if !txt.isEmpty { combined.append(txt) }
            } catch {
                scanError = "L'OCR a échoué : \(error.localizedDescription)"
                phase = .intro
                return
            }
        }
        ocrProgress = "Analyse du contenu…"
        let allText = combined.joined(separator: "\n\n")
        ocrText = allText
        let parsed = BookletParser.parse(allText)
        extracted = parsed
        if let parsedDate = parsed.dayDate {
            dayDate = parsedDate
        }
        phase = .review
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

        if extracted.breakfastRating > 0 { target.breakfastRatingRaw = extracted.breakfastRating }
        if extracted.lunchRating > 0 { target.lunchRatingRaw = extracted.lunchRating }
        if extracted.snackRating > 0 { target.snackRatingRaw = extracted.snackRating }
        if extracted.dinnerRating > 0 { target.dinnerRatingRaw = extracted.dinnerRating }
        if extracted.hydrationRating > 0 { target.hydrationRatingRaw = extracted.hydrationRating }
        if extracted.nightSleepRating > 0 { target.nightSleepRatingRaw = extracted.nightSleepRating }
        if extracted.nightSleepDurationMinutes > 0 { target.nightSleepDurationMinutes = extracted.nightSleepDurationMinutes }
        if extracted.napDurationMinutes > 0 { target.napDurationMinutes = extracted.napDurationMinutes }
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
