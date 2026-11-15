import SwiftUI
import SwiftData
import UIKit
import os.log

/// Workflow d'import du cahier de suivi.
///
/// Pipeline :
///   1. Intro + bouton « Prendre une photo »
///   2. Scan via VNDocumentCameraViewController (plein écran)
///   3. Détection du QR code embarqué dans la page → décode le `BookletSchema`
///      (date de début de semaine, médicaments, repas, symptômes inclus).
///   4. Pour chaque case à cocher du layout (calculé par `BookletLayoutEngine`),
///      on échantillonne l'intensité de l'image à la position attendue (via
///      `BookletPixelSampler`). Cases sombres = cochées par l'utilisateur.
///   5. Review UI organisée par JOUR — l'utilisateur valide/corrige chaque
///      case en ayant la photo de la page sous les yeux.
///   6. Insertion via `BookletInsertionService` qui crée les `MedicationLog`,
///      `MoodEntry`, `DailyObservation`, `SymptomEvent` pour les bons jours.
struct BookletImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    enum Phase {
        case intro
        case processing
        case review
        case unsupportedScan
        case choixCahier
    }

    /// Pourquoi le scan n'a pas abouti.
    ///
    /// Les trois cas appellent des gestes différents — refaire la photo,
    /// changer de page, ou cadrer la page entière — et l'app les présentait
    /// tous comme « QR code introuvable », y compris lorsque le QR avait été
    /// parfaitement lu. On envoyait donc la famille refaire une photo qui ne
    /// pouvait pas mieux marcher.
    enum EchecScan {
        case introuvable
        case contenuEtranger
        case pageIncomplete

        var titre: String {
            switch self {
            case .introuvable:     return "QR code introuvable"
            case .contenuEtranger: return "Page non reconnue"
            case .pageIncomplete:  return "Page incomplète"
            }
        }

        var explication: String {
            switch self {
            case .introuvable:
                return "Le QR code en haut à droite de la page n'a pas pu être lu. Cela peut arriver si la photo est floue, trop sombre, ou si la page provient d'une ancienne version du cahier (générée avant l'ajout du QR)."
            case .contenuEtranger:
                return "Un QR code a bien été lu, mais son contenu n'est pas celui d'un cahier de suivi RettApp. Vérifiez que la page vient bien du cahier imprimé depuis l'application."
            case .pageIncomplete:
                return "Le QR code a été lu, mais la page n'a pas pu être analysée. Photographiez-la entière, bien à plat et sans coin coupé."
            }
        }
    }

    @State private var phase: Phase = .intro
    @State private var echecScan: EchecScan = .introuvable
    /// Les cahiers que l'app a imprimés, relus au moment d'un échec. Vide tant
    /// que rien n'a été imprimé depuis la version qui les mémorise.
    @State private var cahiersImprimes: [PrintedBookletStore.Item] = []
    @State private var showScanner = false
    @State private var progress: String = ""
    @State private var scanError: String?
    @State private var scannedImage: UIImage?
    @State private var scanResult: BookletScanResult?
    @State private var insertionSummary: BookletInsertionService.Summary?
    @State private var selectedDayIndex: Int = 0

    private let log = Logger(subsystem: "fr.afsr.RettApp", category: "BookletScan")

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Importer le cahier")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Insérer") { saveAndDismiss() }
                            .bold()
                            .disabled(phase != .review || scanResult == nil)
                    }
                }
        }
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
        case .intro:           introView
        case .processing:      processingView
        case .review:          reviewView
        case .unsupportedScan: unsupportedScanView
        case .choixCahier:     choixCahierView
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
                Text("Scanner le cahier rempli")
                    .font(AFSRFont.title(20))
                Text("Photographiez la page A4 du cahier remplie par l'école ou le centre. RettApp lira le QR code en haut à droite pour identifier la semaine et toutes les cases à cocher.")
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
                    Label("Posez la page bien à plat, éclairage uniforme.", systemImage: "lightbulb")
                    Label("L'iPhone détecte les bords automatiquement.", systemImage: "rectangle.dashed")
                    Label("Le QR doit être net pour identifier la semaine et la disposition.", systemImage: "qrcode.viewfinder")
                    Label("Vous pourrez vérifier chaque case avant de l'insérer dans le journal.", systemImage: "checkmark.circle")
                }
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .padding(.top, 4)

                Spacer()
            }
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text(progress.isEmpty ? "Analyse en cours…" : progress)
                .font(AFSRFont.body(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let img = scannedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Unsupported scan

    private var unsupportedScanView: some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.afsrEmergency)
                .padding(.top, 24)
            Text(echecScan.titre)
                .font(AFSRFont.title(18))
            Text(echecScan.explication)
                .font(AFSRFont.body(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)

            if let img = scannedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                    .padding(.horizontal)
            }

            VStack(spacing: 8) {
                Button {
                    showScanner = true
                } label: {
                    Label("Prendre une nouvelle photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.afsrPurpleAdaptive)

                // Repli : l'app sait ce qu'elle a imprimé. Proposé seulement
                // s'il y a quelque chose à proposer — un bouton qui mènerait à
                // une liste vide serait pire que pas de bouton.
                if !cahiersImprimes.isEmpty {
                    Button {
                        phase = .choixCahier
                    } label: {
                        Label("Identifier le cahier sans le QR", systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.afsrPurpleAdaptive)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Annuler").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Repli : choisir le cahier dans l'historique

    private var choixCahierView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.afsrPurpleAdaptive)
                Text("Quel cahier avez-vous photographié ?")
                    .font(AFSRFont.title(18))
                    .multilineTextAlignment(.center)
                Text("RettApp garde la trace des cahiers qu'elle imprime. Choisissez celui qui correspond à la feuille : les cases seront lues à leur position théorique, et vous verrez tout ce qui a été lu avant d'enregistrer.")
                    .font(AFSRFont.body(13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            List(cahiersImprimes) { cahier in
                Button {
                    choisirCahier(cahier)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cahier.libelle)
                                .font(AFSRFont.body(15))
                            Text(cahier.detail)
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)

            Button {
                phase = .unsupportedScan
            } label: {
                Text("Revenir").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func choisirCahier(_ cahier: PrintedBookletStore.Item) {
        guard let image = scannedImage else { return }
        log.info("Repli sans QR — cahier du \(cahier.schema.start, privacy: .public)")
        phase = .processing
        analyse(image: image, schema: cahier.schema, ancrageQR: nil)
    }

    // MARK: - Review (par jour)

    private var reviewView: some View {
        VStack(spacing: 0) {
            if let result = scanResult {
                detectedDateBanner(result: result)
                daySelector(result: result)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let img = scannedImage {
                            DisclosureGroup("Photo de la page (référence)") {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                            }
                            .padding(.horizontal)
                        }
                        dayDetailView(result: result, dayIndex: selectedDayIndex)
                            .padding(.horizontal)
                        Spacer(minLength: 20)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 80)  // place pour la barre d'action en bas
                }
                // Barre d'action fixe en bas — fallback robuste si le bouton
                // toolbar n'est pas visible.
                actionBar(result: result)
            } else {
                Text("Scan vide — recommencez la prise de photo.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private func actionBar(result: BookletScanResult) -> some View {
        let totalChecked = result.checks.values.filter { $0 }.count
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button {
                    showScanner = true
                    phase = .intro
                } label: {
                    Label("Reprendre la photo", systemImage: "camera.rotate")
                        .font(AFSRFont.caption())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.afsrPurpleAdaptive)

                Button {
                    saveAndDismiss()
                } label: {
                    Label("Insérer dans le journal (\(totalChecked))",
                          systemImage: "checkmark.circle.fill")
                        .font(AFSRFont.headline(14))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.afsrPurpleAdaptive)
                .disabled(totalChecked == 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func detectedDateBanner(result: BookletScanResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .foregroundStyle(.afsrPurpleAdaptive)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 1) {
                Text("Semaine détectée")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
                if let start = result.schema.weekStartDate {
                    Text(weekRangeLabel(start: start, days: result.schema.days))
                        .font(AFSRFont.headline(14))
                }
            }
            Spacer()
            Text("\(result.checks.values.filter { $0 }.count) cases cochées")
                .font(AFSRFont.caption())
                .foregroundStyle(.afsrPurpleAdaptive)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.afsrPurpleAdaptive.opacity(0.10))
    }

    private func daySelector(result: BookletScanResult) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<result.schema.days, id: \.self) { d in
                    Button {
                        selectedDayIndex = d
                    } label: {
                        VStack(spacing: 2) {
                            Text(dayLabel(forIndex: d))
                                .font(AFSRFont.caption())
                            if let date = result.date(forDay: d) {
                                Text(date, format: .dateTime.day().month())
                                    .font(AFSRFont.headline(13))
                            }
                            let n = result.checks
                                .filter { $0.value && $0.key.dayIndex == d }
                                .count
                            Text(n > 0 ? "\(n) ✓" : "—")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            d == selectedDayIndex
                                ? Color.afsrPurpleAdaptive.opacity(0.20)
                                : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(d == selectedDayIndex ? .afsrPurpleAdaptive : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func dayDetailView(result: BookletScanResult, dayIndex: Int) -> some View {
        let cellsForDay = result.checks.keys
            .filter { $0.dayIndex == dayIndex }
            .sorted(by: cellOrder)

        VStack(alignment: .leading, spacing: 16) {
            // Groupement par section
            ForEach(BookletSchema.Section.allCasesOrdered, id: \.self) { section in
                let cells = cellsForDay.filter { $0.section == section }
                if !cells.isEmpty {
                    sectionGroup(section: section, cells: cells, result: result)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionGroup(
        section: BookletSchema.Section,
        cells: [BookletLayoutEngine.Cell],
        result: BookletScanResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: sectionIcon(section))
                    .foregroundStyle(.afsrPurpleAdaptive)
                Text(sectionTitle(section))
                    .font(AFSRFont.headline(15))
            }
            // Regroupement par row dans la section
            let byRow = Dictionary(grouping: cells, by: \.rowIndex)
                .sorted { $0.key < $1.key }
            ForEach(byRow, id: \.key) { rowIdx, rowCells in
                VStack(alignment: .leading, spacing: 4) {
                    if let label = rowLabel(section: section, rowIndex: rowIdx, schema: result.schema) {
                        Text(label)
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                    optionRow(section: section, rowIndex: rowIdx, cells: rowCells)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func optionRow(section: BookletSchema.Section, rowIndex: Int, cells: [BookletLayoutEngine.Cell]) -> some View {
        let labels = optionLabels(section: section, rowIndex: rowIndex)
        HStack(spacing: 6) {
            ForEach(cells.sorted(by: cellOrder), id: \.self) { cell in
                let isOn = scanResult?.checks[cell] ?? false
                let label = optionLabelFor(cell: cell, defaultLabels: labels)
                Button {
                    toggle(cell)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isOn ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isOn ? .afsrPurpleAdaptive : .secondary)
                        Text(label)
                            .font(AFSRFont.caption())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        isOn
                            ? Color.afsrPurpleAdaptive.opacity(0.15)
                            : Color(.tertiarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Pipeline

    private func handleScanResult(_ result: BookletScannerView.Result) {
        switch result {
        case .success(let images):
            log.info("Scanner returned \(images.count, privacy: .public) page(s)")
            guard let image = images.first else {
                log.error("No image in scan result")
                phase = .intro; return
            }
            scannedImage = image
            phase = .processing
            progress = "Recherche du QR code…"
            Task { await runPipeline(image: image) }
        case .cancelled:
            log.info("Scanner cancelled")
            phase = .intro
        case .failed(let err):
            log.error("Scanner failed: \(err.localizedDescription, privacy: .public)")
            scanError = err.localizedDescription
            phase = .intro
        }
    }

    @MainActor
    private func runPipeline(image: UIImage) async {
        log.info("Pipeline start — image size = \(image.size.width, privacy: .public)x\(image.size.height, privacy: .public)")
        switch await BookletQR.detect(in: image) {
        case .trouve(let detection):
            log.info("QR detected — schema days=\(detection.schema.days, privacy: .public) sections=\(detection.schema.incl, privacy: .public) meds=\(detection.schema.meds.count, privacy: .public)")
            analyse(image: image, schema: detection.schema, ancrageQR: detection.pixelBounds)
        case .contenuEtranger:
            log.error("QR lu, mais son contenu n'est pas un cahier RettApp")
            echouer(.contenuEtranger)
        case .illisible:
            log.error("QR detection FAILED — no readable QR in the image")
            echouer(.introuvable)
        }
    }

    /// Échec de lecture. On relit l'historique des cahiers imprimés **ici**,
    /// et non au lancement : c'est le seul moment où il sert, et le lire plus
    /// tôt donnerait une liste périmée si une impression a eu lieu entre-temps.
    @MainActor
    private func echouer(_ raison: EchecScan) {
        echecScan = raison
        cahiersImprimes = PrintedBookletStore.items()
        phase = .unsupportedScan
    }

    /// Lit les cases de la page, puis passe à la relecture.
    ///
    /// `ancrageQR` porte le cadre du QR retrouvé dans la photo. À `nil`, on est
    /// en repli : le schéma vient de l'historique d'impression, et la page sert
    /// de repère à elle-même.
    @MainActor
    private func analyse(image: UIImage, schema: BookletSchema, ancrageQR: CGRect?) {
        progress = "Analyse des cases à cocher…"

        let sampler: BookletPixelSampler?
        if let ancrageQR {
            sampler = BookletPixelSampler(
                image: image,
                qrPDFRect: CGRect(x: BookletLayoutEngine.qrOrigin.x,
                                  y: BookletLayoutEngine.qrOrigin.y,
                                  width: BookletLayoutEngine.qrSize,
                                  height: BookletLayoutEngine.qrSize),
                qrImageRect: ancrageQR
            )
        } else {
            sampler = BookletPixelSampler(pageImage: image)
        }
        guard let sampler else {
            log.error("BookletPixelSampler init failed")
            echouer(.pageIncomplete)
            return
        }
        log.info("Paper reference luma = \(sampler.paperReference, privacy: .public)")
        let cells = BookletLayoutEngine.cells(for: schema)
        log.info("Layout produced \(cells.count, privacy: .public) cells")
        var checks: [BookletLayoutEngine.Cell: Bool] = [:]
        var checkedCount = 0
        // Histogramme des ratios par bucket — permet de voir si la
        // distribution est bien bimodale (cases cochées <0.5, cases vides
        // >0.9) ou floue (continuité entre 0.6 et 0.9 → seuil mal calibré).
        var bucket_lt50 = 0   // ratio < 0.50  (très clair-encrage)
        var bucket_50_72 = 0  // 0.50 ≤ ratio < 0.72 (cochées mais légères)
        var bucket_72_85 = 0  // 0.72 ≤ ratio < 0.85 (zone d'incertitude)
        var bucket_85_95 = 0  // 0.85 ≤ ratio < 0.95 (probable papier)
        var bucket_ge95 = 0   // ratio ≥ 0.95 (papier blanc)
        for cell in cells {
            let r = sampler.isChecked(atPDFPoint: cell.center)
            checks[cell] = r.checked
            if r.checked { checkedCount += 1 }
            switch r.ratio {
            case ..<0.50:    bucket_lt50 += 1
            case ..<0.72:    bucket_50_72 += 1
            case ..<0.85:    bucket_72_85 += 1
            case ..<0.95:    bucket_85_95 += 1
            default:         bucket_ge95 += 1
            }
        }
        log.info("Sampler: \(checkedCount, privacy: .public)/\(cells.count, privacy: .public) cells checked")
        log.info("Histogramme ratios — <50%: \(bucket_lt50, privacy: .public) · 50-72%: \(bucket_50_72, privacy: .public) · 72-85%: \(bucket_72_85, privacy: .public) · 85-95%: \(bucket_85_95, privacy: .public) · ≥95%: \(bucket_ge95, privacy: .public)")
        scanResult = BookletScanResult(schema: schema, checks: checks)
        selectedDayIndex = 0
        phase = .review
        log.info("Phase = .review, scanResult set")
    }

    private func toggle(_ cell: BookletLayoutEngine.Cell) {
        guard var result = scanResult else { return }
        result.checks[cell] = !(result.checks[cell] ?? false)
        scanResult = result
    }

    private func saveAndDismiss() {
        guard let result = scanResult else {
            log.error("saveAndDismiss called with nil scanResult")
            return
        }
        let summary = BookletInsertionService.apply(
            result, in: modelContext,
            childProfile: profiles.first,
            existingMedications: medications
        )
        log.info("Inserted: \(summary.summaryText, privacy: .public) — total \(summary.totalChecks, privacy: .public) checks")
        insertionSummary = summary
        dismiss()
    }

    // MARK: - Labels

    private func sectionIcon(_ s: BookletSchema.Section) -> String {
        switch s {
        case .medication: return "pills.fill"
        case .seizure:    return "waveform.path.ecg"
        case .mood:       return "face.smiling"
        case .meals:      return "fork.knife"
        case .hydration:  return "drop.fill"
        case .sleep:      return "bed.double.fill"
        case .elimination: return "toilet.fill"
        case .symptoms:   return "stethoscope"
        case .events:     return "exclamationmark.bubble.fill"
        }
    }

    private func sectionTitle(_ s: BookletSchema.Section) -> String {
        switch s {
        case .medication: return "Médicaments"
        case .seizure:    return "Crises"
        case .mood:       return "Humeur"
        case .meals:      return "Repas"
        case .hydration:  return "Hydratation"
        case .sleep:      return "Sommeil"
        case .elimination: return "Selles et urines"
        case .symptoms:   return "Symptômes Rett"
        case .events:     return "Événements"
        }
    }

    private func rowLabel(section: BookletSchema.Section, rowIndex: Int, schema: BookletSchema) -> String? {
        switch section {
        case .medication: return rowIndex < schema.meds.count ? schema.meds[rowIndex] : nil
        case .seizure:    return SeizureType.allCases[safe: rowIndex]?.label
        case .mood:       return ["😀 Très bien", "🙂 Bien", "😐 Neutre", "😟 Inquiétant", "😢 Très difficile"][safe: rowIndex]
        case .meals:
            let letters = Array(schema.mealSlots)
            guard let l = letters[safe: rowIndex] else { return nil }
            return ["B": "Petit-déjeuner", "L": "Déjeuner", "S": "Goûter", "D": "Dîner"][String(l)]
        case .hydration:  return "Hydratation"
        case .sleep:      return ["Sommeil de nuit (durée)", "Qualité du sommeil", "Sieste matin", "Sieste après-midi", "Réveils nocturnes"][safe: rowIndex]
        case .elimination: return ["Selles, nombre", "Selles, aspect", "Urines"][safe: rowIndex]
        case .symptoms:
            guard let s = schema.symptoms[safe: rowIndex],
                  let sym = RettSymptom(rawValue: s) else { return nil }
            return sym.label
        case .events:
            return ["Pleurs / cris", "Agitation", "Selles inhabituelles", "Vomissements", "Comportement nouveau", "Autre"][safe: rowIndex]
        }
    }

    private func optionLabels(section: BookletSchema.Section, rowIndex: Int) -> [String] {
        switch section {
        case .medication, .mood, .events: return ["Donné/Coché"]
        case .seizure:    return ["0", "1", "2-3", "4+"]
        case .meals:      return ["Refusé", "Peu", "Moyen", "Bien", "Très bien"]
        case .hydration:  return ["Faible", "Moyenne", "Bonne", "Excellente"]
        case .sleep:
            switch rowIndex {
            case 0: return ["<6h", "6-8h", "8-10h", ">10h"]
            case 1: return ["Bonne", "Moyenne", "Difficile"]
            case 2, 3: return ["Non", "<30min", "30-60min", ">60min"]
            case 4: return ["0 réveil", "1-2", "3+"]
            default: return []
            }
        case .elimination:
            switch rowIndex {
            case 0: return ["Aucune", "1", "2", "3 et plus"]
            case 1: return ["Dures", "Normales", "Molles", "Liquides"]
            case 2: return ["Aucune", "Peu", "Normales", "Abondantes"]
            default: return []
            }
        case .symptoms:   return ["Matin", "Après-midi"]
        }
    }

    private func optionLabelFor(cell: BookletLayoutEngine.Cell, defaultLabels: [String]) -> String {
        if cell.section == .symptoms {
            return cell.half == .morning ? "M" : "A"
        }
        if defaultLabels.indices.contains(cell.optionIndex) {
            return defaultLabels[cell.optionIndex]
        }
        return "✓"
    }

    private func dayLabel(forIndex i: Int) -> String {
        ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"][safe: i] ?? "?"
    }

    private func cellOrder(_ a: BookletLayoutEngine.Cell, _ b: BookletLayoutEngine.Cell) -> Bool {
        if a.rowIndex != b.rowIndex { return a.rowIndex < b.rowIndex }
        if a.optionIndex != b.optionIndex { return a.optionIndex < b.optionIndex }
        let ah = a.half == .morning ? 0 : 1
        let bh = b.half == .morning ? 0 : 1
        return ah < bh
    }

    private func weekRangeLabel(start: Date, days: Int) -> String {
        let cal = Calendar.current
        let endDay = cal.date(byAdding: .day, value: days - 1, to: start) ?? start
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return "\(f.string(from: start)) → \(f.string(from: endDay))"
    }
}

// MARK: - Helpers

private extension BookletSchema.Section {
    static var allCasesOrdered: [BookletSchema.Section] {
        // Même ordre que la page imprimée : on relit l'écran de contrôle en
        // tenant le cahier à côté.
        [.medication, .seizure, .mood, .meals, .hydration, .sleep, .elimination, .symptoms, .events]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
