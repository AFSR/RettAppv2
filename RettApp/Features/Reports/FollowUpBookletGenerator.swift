import Foundation
import UIKit

/// Génère un PDF **A4 portrait, dense, mono-page, 100 % cases à cocher**
/// destiné à être imprimé et confié à l'équipe encadrante.
///
/// Tous les champs à remplir sont des cases pré-définies (fréquence,
/// intensité, qualité, quantité). Aucune saisie de texte libre — facilite
/// le remplissage rapide à la main, la prise de photo et le ré-encodage.
///
/// Format : A4 portrait (595 × 842 pt). Police compacte (8-9 pt), hauteurs
/// de ligne adaptatives via `LayoutPlan` pour rester sur une seule page.
enum FollowUpBookletGenerator {

    struct Options {
        var coverChildName: String
        var coverPeriodLabel: String
        /// Date du lundi de la semaine couverte (utilisée pour générer le QR
        /// d'ancrage du scan + le bandeau date prominent).
        var weekStart: Date
        var includeMedicationGrid: Bool
        var includeSeizureGrid: Bool
        var includeMoodGrid: Bool
        var includeMealsGrid: Bool
        var includeSleepGrid: Bool
        var includeSymptomsGrid: Bool
        var includeFreeNotes: Bool       // « événements particuliers » sous forme de cases
        var medications: [Medication]
        var allDosesSelected: Bool
        var selectedDoses: Set<DoseKey>
        var selectedMealSlots: Set<MealSlot>
        var selectedSymptoms: Set<RettSymptom>
        var dayCount: Int
    }

    static let bookletDirectoryName = "Booklets"

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 24
    private static let footerReserve: CGFloat = 18

    // Légendes des options pré-définies (codes courts → libellés)
    private static let mealQualityCodes  = ["R", "P", "M", "B", "T"]
    private static let mealQualityLegend = "R/P/M/B/T = Refusé · Peu · Moyen · Bien · Très bien"
    private static let hydrationCodes    = ["F", "M", "B", "E"]
    private static let hydrationLegend   = "F/M/B/E = Faible · Moyenne · Bonne · Excellente"
    private static let seizureFreqCodes  = ["0", "1", "2-3", "4+"]
    private static let seizureFreqLegend = "Nombre de crises observées dans la journée"
    private static let sleepDurCodes     = ["<6", "6-8", "8-10", ">10"]
    private static let sleepDurLegend    = "Durée du sommeil de nuit, en heures"
    private static let sleepQualCodes    = ["B", "M", "D"]
    private static let sleepQualLegend   = "B/M/D = Bonne · Moyenne · Difficile"
    private static let napCodes          = ["Non", "<30", "30-60", ">60"]
    private static let napLegend         = "Sieste, en minutes"
    private static let nightWakeCodes    = ["0", "1-2", "3+"]
    private static let nightWakeLegend   = "Nombre de réveils nocturnes"

    static func generate(_ options: Options) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "RettApp",
            kCGPDFContextTitle as String: "Cahier de suivi - \(options.coverChildName)"
        ] as [String: Any]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let url = try makeBookletURL(child: options.coverChildName, generatedAt: Date())

        try renderer.writePDF(to: url) { context in
            context.beginPage()
            var y: CGFloat = margin

            drawHeader(in: context, y: &y, options: options)

            let plan = layoutPlan(for: options, availableHeight: pageHeight - y - footerReserve)

            if options.includeMedicationGrid {
                drawMedicationGrid(in: context, y: &y, options: options, rowHeight: plan.medicationRowHeight)
            }
            if options.includeSeizureGrid {
                drawSeizureGrid(in: context, y: &y, options: options, rowHeight: plan.seizureRowHeight)
            }
            if options.includeMoodGrid {
                drawMoodGrid(in: context, y: &y, options: options, rowHeight: plan.moodRowHeight)
            }
            if options.includeMealsGrid {
                drawMealsGrid(in: context, y: &y, options: options, rowHeight: plan.mealsRowHeight)
            }
            if options.includeSleepGrid {
                drawSleepGrid(in: context, y: &y, options: options, rowHeight: plan.sleepRowHeight)
            }
            if options.includeSymptomsGrid && !options.selectedSymptoms.isEmpty {
                drawSymptomsGrid(in: context, y: &y, options: options, rowHeight: plan.symptomsRowHeight)
            }
            if options.includeFreeNotes {
                drawEventsGrid(in: context, y: &y, options: options, rowHeight: plan.eventsRowHeight)
            }

            drawFooter()
        }

        return url
    }

    // MARK: - Layout planner (auto-fit single page)

    private struct LayoutPlan {
        var medicationRowHeight: CGFloat
        var seizureRowHeight: CGFloat
        var moodRowHeight: CGFloat
        var mealsRowHeight: CGFloat
        var sleepRowHeight: CGFloat
        var symptomsRowHeight: CGFloat
        var eventsRowHeight: CGFloat
    }

    private static func layoutPlan(for options: Options, availableHeight: CGFloat) -> LayoutPlan {
        // Compte des lignes par section
        let medRows = doseRowCount(options: options)
        let seizureRows = SeizureType.allCases.count
        let moodRows = 5
        let mealsRows = options.selectedMealSlots.count + 1   // + hydratation
        let sleepRows = 5
        let symptomRows = options.selectedSymptoms.count
        let eventsRows = 6

        // Surcoût fixe par section : titre (10) + sous-titre légende (8) + en-tête tableau (12)
        let sectionOverhead: CGFloat = 32
        var fixedOverhead: CGFloat = 0
        if options.includeMedicationGrid && medRows > 0 { fixedOverhead += sectionOverhead }
        if options.includeSeizureGrid { fixedOverhead += sectionOverhead }
        if options.includeMoodGrid { fixedOverhead += sectionOverhead }
        if options.includeMealsGrid && mealsRows > 1 { fixedOverhead += sectionOverhead }
        if options.includeSleepGrid { fixedOverhead += sectionOverhead }
        if options.includeSymptomsGrid && symptomRows > 0 { fixedOverhead += sectionOverhead + 10 }  // + bandeau M/A
        if options.includeFreeNotes { fixedOverhead += sectionOverhead }

        let totalRows = (options.includeMedicationGrid ? medRows : 0)
            + (options.includeSeizureGrid ? seizureRows : 0)
            + (options.includeMoodGrid ? moodRows : 0)
            + (options.includeMealsGrid ? mealsRows : 0)
            + (options.includeSleepGrid ? sleepRows : 0)
            + (options.includeSymptomsGrid ? symptomRows : 0)
            + (options.includeFreeNotes ? eventsRows : 0)

        let rowSpace = max(0, availableHeight - fixedOverhead)
        let perRow: CGFloat
        if totalRows > 0 {
            let raw = rowSpace / CGFloat(totalRows)
            perRow = max(11, min(16, raw))
        } else {
            perRow = 14
        }

        return LayoutPlan(
            medicationRowHeight: perRow,
            seizureRowHeight: perRow,
            moodRowHeight: perRow,
            mealsRowHeight: perRow,
            sleepRowHeight: perRow,
            symptomsRowHeight: perRow,
            eventsRowHeight: perRow
        )
    }

    private static func doseRowCount(options: Options) -> Int {
        let actives = options.medications.filter { $0.isActive }
        var count = 0
        for med in actives {
            for intake in med.intakes {
                let key = DoseKey(medicationID: med.id, hour: intake.hour, minute: intake.minute)
                if options.allDosesSelected || options.selectedDoses.contains(key) { count += 1 }
            }
        }
        return count
    }

    // MARK: - Archive

    static func bookletDirectory() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = docs.appendingPathComponent(bookletDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func archivedBooklets() -> [URL] {
        guard let dir = try? bookletDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.creationDateKey]
              ) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted {
                ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                    >
                ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
            }
    }

    static func deleteBooklet(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    private static func makeBookletURL(child: String, generatedAt: Date) throws -> URL {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = fmt.string(from: generatedAt)
        let safeName = child.folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: " ", with: "_")
        let filename = "RettApp_Cahier_\(safeName)_\(stamp).pdf"
        return try bookletDirectory().appendingPathComponent(filename)
    }

    // MARK: - Header (1 ligne dense)

    private static func drawHeader(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options) {
        // QR code en haut à droite (sert d'ancrage au scan + transporte le schéma)
        let schema = BookletSchema.from(options: options, weekStart: options.weekStart)
        let qrSize: CGFloat = BookletLayoutEngine.qrSize
        let qrOrigin = BookletLayoutEngine.qrOrigin
        if let qrImage = BookletQR.image(for: schema, sizeInPoints: qrSize) {
            qrImage.draw(in: CGRect(x: qrOrigin.x, y: qrOrigin.y,
                                    width: qrSize, height: qrSize))
        }

        // Bloc date prominent juste à gauche du QR
        let dateBlockX = margin
        let dateBlockY = qrOrigin.y
        let dateBlockWidth = qrOrigin.x - dateBlockX - 12
        let dateBlockHeight: CGFloat = qrSize

        // Fond léger pourpre pour bien matérialiser la date
        UIColor.systemPurple.withAlphaComponent(0.10).setFill()
        UIBezierPath(roundedRect: CGRect(x: dateBlockX, y: dateBlockY,
                                          width: dateBlockWidth, height: dateBlockHeight),
                     cornerRadius: 6).fill()

        let titleFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let dateFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        let metaFont = UIFont.systemFont(ofSize: 9, weight: .regular)

        // Ligne 1 : "Cahier de suivi quotidien"
        "Cahier de suivi quotidien".draw(
            at: CGPoint(x: dateBlockX + 8, y: dateBlockY + 6),
            withAttributes: [.font: titleFont, .foregroundColor: UIColor.black]
        )

        // Ligne 2 : période en grand pour bien matérialiser la date
        options.coverPeriodLabel.draw(
            at: CGPoint(x: dateBlockX + 8, y: dateBlockY + 22),
            withAttributes: [.font: dateFont, .foregroundColor: UIColor.systemPurple]
        )

        // Ligne 3 : nom de l'enfant
        ("Enfant : " + options.coverChildName).draw(
            at: CGPoint(x: dateBlockX + 8, y: dateBlockY + 46),
            withAttributes: [.font: metaFont, .foregroundColor: UIColor.darkGray]
        )

        // Avance le curseur y sous l'en-tête
        y = dateBlockY + dateBlockHeight + 4
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        UIColor.black.setStroke(); path.lineWidth = 0.5; path.stroke()
        y += 6
    }

    private static func dayHeaders(count: Int) -> [String] {
        let all = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        return Array(all.prefix(min(7, max(5, count))))
    }

    // MARK: - Sections

    private static func drawMedicationGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        let actives = options.medications.filter { $0.isActive }
        var rows: [String] = []
        for med in actives {
            for intake in med.intakes {
                let key = DoseKey(medicationID: med.id, hour: intake.hour, minute: intake.minute)
                if options.allDosesSelected || options.selectedDoses.contains(key) {
                    let doseLabel = MedicationIntake.doseLabel(intake.dose, unit: med.doseUnit)
                    let suffix = intake.isEveryDay ? "" : " (\(intake.weekdaySummary))"
                    rows.append("\(med.name) — \(doseLabel) à \(intake.formattedTime)\(suffix)")
                }
            }
        }
        guard !rows.isEmpty else { return }

        drawSectionTitle("Prises de médicaments", legend: "Cocher quand le médicament a été donné", y: &y)
        drawSingleCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount),
                            y: &y, leftColumnWidth: 220, rowHeight: rowHeight)
    }

    private static func drawSeizureGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        drawSectionTitle("Crises d'épilepsie observées", legend: seizureFreqLegend, y: &y)
        let rows = SeizureType.allCases.map { $0.label }
        drawMultiCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount),
                           options: seizureFreqCodes, y: &y, leftColumnWidth: 180, rowHeight: rowHeight)
    }

    private static func drawMoodGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        drawSectionTitle("Humeur dominante", legend: "Cocher l'état dominant observé", y: &y)
        let rows = ["😀 Très bien", "🙂 Bien", "😐 Neutre", "😟 Inquiétant / agité", "😢 Très difficile"]
        drawSingleCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount),
                            y: &y, leftColumnWidth: 180, rowHeight: rowHeight)
    }

    private static func drawMealsGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        let chosen = [MealSlot.breakfast, .lunch, .snack, .dinner].filter { options.selectedMealSlots.contains($0) }
        guard !chosen.isEmpty else { return }
        drawSectionTitle("Repas — quantité avalée", legend: mealQualityLegend, y: &y)
        let rows: [String] = chosen.map { $0.label }
        drawMultiCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount),
                           options: mealQualityCodes, y: &y, leftColumnWidth: 150, rowHeight: rowHeight)

        // Hydratation : séparée, échelle différente
        drawSectionTitle("Hydratation", legend: hydrationLegend, y: &y)
        drawMultiCheckGrid(rows: ["Apport liquidien"], dayHeaders: dayHeaders(count: options.dayCount),
                           options: hydrationCodes, y: &y, leftColumnWidth: 150, rowHeight: rowHeight)
    }

    private static func drawSleepGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        drawSectionTitle("Sommeil", legend: "Voir légendes ci-dessous", y: &y)

        // Durée nuit (4 options)
        drawMultiCheckGrid(rows: ["Sommeil de nuit (h) — \(sleepDurLegend)"], dayHeaders: dayHeaders(count: options.dayCount),
                           options: sleepDurCodes, y: &y, leftColumnWidth: 220, rowHeight: rowHeight)
        // Qualité (3 options)
        drawMultiCheckGrid(rows: ["Qualité du sommeil — \(sleepQualLegend)"], dayHeaders: dayHeaders(count: options.dayCount),
                           options: sleepQualCodes, y: &y, leftColumnWidth: 220, rowHeight: rowHeight)
        // Sieste matin
        drawMultiCheckGrid(rows: ["Sieste matin — \(napLegend)"], dayHeaders: dayHeaders(count: options.dayCount),
                           options: napCodes, y: &y, leftColumnWidth: 220, rowHeight: rowHeight)
        // Sieste après-midi
        drawMultiCheckGrid(rows: ["Sieste après-midi — \(napLegend)"], dayHeaders: dayHeaders(count: options.dayCount),
                           options: napCodes, y: &y, leftColumnWidth: 220, rowHeight: rowHeight)
        // Réveils
        drawMultiCheckGrid(rows: ["Réveils nocturnes — \(nightWakeLegend)"], dayHeaders: dayHeaders(count: options.dayCount),
                           options: nightWakeCodes, y: &y, leftColumnWidth: 220, rowHeight: rowHeight)
    }

    /// Symptômes Rett : 2 cases par jour (matin / après-midi).
    private static func drawSymptomsGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        drawSectionTitle("Symptômes Rett", legend: "M = matin · A = après-midi", y: &y)

        let symptoms = RettSymptom.allCases.filter { options.selectedSymptoms.contains($0) }
        let days = dayHeaders(count: options.dayCount)
        let totalWidth = pageWidth - 2 * margin
        let leftWidth: CGFloat = 170
        let halfDayWidth = (totalWidth - leftWidth) / CGFloat(days.count * 2)

        let dayHeaderFont = UIFont.systemFont(ofSize: 8.5, weight: .semibold)
        let halfHeaderFont = UIFont.systemFont(ofSize: 7, weight: .regular)
        let cellFont = UIFont.systemFont(ofSize: 8)
        // Constantes alignées sur le scanner via BookletLayoutEngine
        let dayHeaderHeight = BookletLayoutEngine.symptomDayHeaderHeight
        let halfHeaderHeight = BookletLayoutEngine.symptomHalfHeaderHeight

        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: totalWidth, height: dayHeaderHeight)).fill()
        for (i, h) in days.enumerated() {
            let x = margin + leftWidth + CGFloat(i) * halfDayWidth * 2
            let para = NSMutableParagraphStyle(); para.alignment = .center
            (h as NSString).draw(in: CGRect(x: x, y: y + 1, width: halfDayWidth * 2, height: dayHeaderHeight),
                                 withAttributes: [.font: dayHeaderFont, .foregroundColor: UIColor.black, .paragraphStyle: para])
        }
        y += dayHeaderHeight

        UIColor(white: 0.96, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: totalWidth, height: halfHeaderHeight)).fill()
        for i in 0..<days.count {
            let xM = margin + leftWidth + CGFloat(i * 2) * halfDayWidth
            let xA = xM + halfDayWidth
            let para = NSMutableParagraphStyle(); para.alignment = .center
            ("M" as NSString).draw(in: CGRect(x: xM, y: y, width: halfDayWidth, height: halfHeaderHeight),
                                   withAttributes: [.font: halfHeaderFont, .foregroundColor: UIColor.darkGray, .paragraphStyle: para])
            ("A" as NSString).draw(in: CGRect(x: xA, y: y, width: halfDayWidth, height: halfHeaderHeight),
                                   withAttributes: [.font: halfHeaderFont, .foregroundColor: UIColor.darkGray, .paragraphStyle: para])
        }
        y += halfHeaderHeight

        for s in symptoms {
            UIColor(white: 0.85, alpha: 1).setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: y + rowHeight))
            line.addLine(to: CGPoint(x: margin + totalWidth, y: y + rowHeight))
            line.lineWidth = 0.3
            line.stroke()

            s.label.draw(in: CGRect(x: margin + 3, y: y + max(0, (rowHeight - 9) / 2), width: leftWidth - 6, height: rowHeight),
                         withAttributes: [.font: cellFont, .foregroundColor: UIColor.darkGray])

            let boxSize = min(rowHeight - 4, CGFloat(9))
            for i in 0..<(days.count * 2) {
                let x = margin + leftWidth + CGFloat(i) * halfDayWidth + (halfDayWidth - boxSize) / 2
                let box = CGRect(x: x, y: y + (rowHeight - boxSize) / 2, width: boxSize, height: boxSize)
                UIColor.black.setStroke()
                let p = UIBezierPath(rect: box); p.lineWidth = 0.4; p.stroke()
            }
            for i in 0...days.count {
                let x = margin + leftWidth + CGFloat(i * 2) * halfDayWidth
                UIColor(white: 0.7, alpha: 1).setStroke()
                let v = UIBezierPath()
                v.move(to: CGPoint(x: x, y: y))
                v.addLine(to: CGPoint(x: x, y: y + rowHeight))
                v.lineWidth = 0.3
                v.stroke()
            }
            y += rowHeight
        }
        y += BookletLayoutEngine.sectionGap
    }

    /// Événements particuliers — remplace les notes libres : 1 case par jour
    /// pour 6 catégories d'événements pré-définies.
    private static func drawEventsGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        drawSectionTitle("Événements particuliers", legend: "Cocher si l'événement s'est produit ce jour-là", y: &y)
        let rows = [
            "Pleurs / cris inexpliqués",
            "Agitation marquée",
            "Selles inhabituelles",
            "Vomissements / régurgitations",
            "Comportement nouveau",
            "Autre événement notable"
        ]
        drawSingleCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount),
                            y: &y, leftColumnWidth: 220, rowHeight: rowHeight)
    }

    private static func drawFooter() {
        let footerFont = UIFont.systemFont(ofSize: 6.5, weight: .light)
        let line = "Cahier généré par RettApp — outil de suivi pour aidants. Pas un dispositif médical."
        line.draw(at: CGPoint(x: margin, y: pageHeight - 14), withAttributes: [
            .font: footerFont, .foregroundColor: UIColor.darkGray
        ])
    }

    // MARK: - Drawing primitives

    private static func drawSectionTitle(_ title: String, legend: String?, y: inout CGFloat) {
        let titleFont = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
        let legendFont = UIFont.italicSystemFont(ofSize: 7.5)
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: titleFont, .foregroundColor: UIColor.black
        ])
        if let legend, !legend.isEmpty {
            let titleSize = (title as NSString).size(withAttributes: [.font: titleFont])
            (legend as NSString).draw(
                at: CGPoint(x: margin + titleSize.width + 6, y: y + 2),
                withAttributes: [.font: legendFont, .foregroundColor: UIColor.darkGray]
            )
        }
        // Avance forfaitaire identique côté scanner (pas de dépendance lineHeight)
        y += BookletLayoutEngine.sectionTitleAdvance
    }

    /// Une case à cocher par cellule-jour. Utilisé pour Médicaments, Humeur, Événements.
    private static func drawSingleCheckGrid(rows: [String], dayHeaders: [String], y: inout CGFloat, leftColumnWidth: CGFloat, rowHeight: CGFloat) {
        let totalWidth = pageWidth - 2 * margin
        let dayColumnWidth = (totalWidth - leftColumnWidth) / CGFloat(dayHeaders.count)
        let headerFont = UIFont.systemFont(ofSize: 8.5, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 8)

        let headerHeight = BookletLayoutEngine.singleCheckHeaderHeight
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: totalWidth, height: headerHeight)).fill()
        for (i, h) in dayHeaders.enumerated() {
            let x = margin + leftColumnWidth + CGFloat(i) * dayColumnWidth
            let para = NSMutableParagraphStyle(); para.alignment = .center
            (h as NSString).draw(in: CGRect(x: x, y: y + 1, width: dayColumnWidth, height: headerHeight),
                                 withAttributes: [.font: headerFont, .foregroundColor: UIColor.black, .paragraphStyle: para])
        }
        y += headerHeight

        for row in rows {
            UIColor(white: 0.85, alpha: 1).setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: y + rowHeight))
            line.addLine(to: CGPoint(x: margin + totalWidth, y: y + rowHeight))
            line.lineWidth = 0.3; line.stroke()

            let label = truncateForCell(row, width: leftColumnWidth - 6, font: cellFont)
            label.draw(in: CGRect(x: margin + 3, y: y + max(0, (rowHeight - 9) / 2), width: leftColumnWidth - 6, height: rowHeight),
                       withAttributes: [.font: cellFont, .foregroundColor: UIColor.darkGray])

            let boxSize: CGFloat = min(rowHeight - 4, 10)
            for i in 0..<dayHeaders.count {
                let x = margin + leftColumnWidth + CGFloat(i) * dayColumnWidth + (dayColumnWidth - boxSize) / 2
                let box = CGRect(x: x, y: y + (rowHeight - boxSize) / 2, width: boxSize, height: boxSize)
                UIColor.black.setStroke()
                let p = UIBezierPath(rect: box); p.lineWidth = 0.4; p.stroke()
            }
            y += rowHeight
        }
        y += BookletLayoutEngine.sectionGap
    }

    /// Plusieurs cases par cellule-jour, chacune étiquetée par un code court.
    /// Le code est rappelé dans une bandeau d'en-tête sous le nom du jour.
    /// Utilisé pour Crises (0/1/2-3/4+), Repas (R/P/M/B/T), Sommeil…
    private static func drawMultiCheckGrid(rows: [String], dayHeaders: [String], options optionCodes: [String], y: inout CGFloat, leftColumnWidth: CGFloat, rowHeight: CGFloat) {
        let totalWidth = pageWidth - 2 * margin
        let dayColumnWidth = (totalWidth - leftColumnWidth) / CGFloat(dayHeaders.count)
        let dayHeaderFont = UIFont.systemFont(ofSize: 8.5, weight: .semibold)
        let optionLetterFont = UIFont.systemFont(ofSize: 6.5, weight: .regular)
        let cellFont = UIFont.systemFont(ofSize: 8)

        // Bandeau jour
        let dayHeaderHeight = BookletLayoutEngine.multiDayHeaderHeight
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: totalWidth, height: dayHeaderHeight)).fill()
        for (i, h) in dayHeaders.enumerated() {
            let x = margin + leftColumnWidth + CGFloat(i) * dayColumnWidth
            let para = NSMutableParagraphStyle(); para.alignment = .center
            (h as NSString).draw(in: CGRect(x: x, y: y + 1, width: dayColumnWidth, height: dayHeaderHeight),
                                 withAttributes: [.font: dayHeaderFont, .foregroundColor: UIColor.black, .paragraphStyle: para])
        }
        y += dayHeaderHeight

        // Bandeau codes-options (sous chaque jour)
        let codeHeaderHeight = BookletLayoutEngine.multiCodeHeaderHeight
        UIColor(white: 0.96, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: totalWidth, height: codeHeaderHeight)).fill()
        let optionWidth = dayColumnWidth / CGFloat(optionCodes.count)
        for i in 0..<dayHeaders.count {
            for (j, code) in optionCodes.enumerated() {
                let x = margin + leftColumnWidth + CGFloat(i) * dayColumnWidth + CGFloat(j) * optionWidth
                let para = NSMutableParagraphStyle(); para.alignment = .center
                (code as NSString).draw(in: CGRect(x: x, y: y, width: optionWidth, height: codeHeaderHeight),
                                        withAttributes: [.font: optionLetterFont, .foregroundColor: UIColor.darkGray, .paragraphStyle: para])
            }
        }
        y += codeHeaderHeight

        // Lignes
        for row in rows {
            UIColor(white: 0.85, alpha: 1).setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: y + rowHeight))
            line.addLine(to: CGPoint(x: margin + totalWidth, y: y + rowHeight))
            line.lineWidth = 0.3; line.stroke()

            let label = truncateForCell(row, width: leftColumnWidth - 6, font: cellFont)
            label.draw(in: CGRect(x: margin + 3, y: y + max(0, (rowHeight - 9) / 2), width: leftColumnWidth - 6, height: rowHeight),
                       withAttributes: [.font: cellFont, .foregroundColor: UIColor.darkGray])

            let boxSize: CGFloat = min(rowHeight - 4, min(optionWidth - 2, 8))
            for i in 0..<dayHeaders.count {
                for j in 0..<optionCodes.count {
                    let x = margin + leftColumnWidth + CGFloat(i) * dayColumnWidth + CGFloat(j) * optionWidth + (optionWidth - boxSize) / 2
                    let box = CGRect(x: x, y: y + (rowHeight - boxSize) / 2, width: boxSize, height: boxSize)
                    UIColor.black.setStroke()
                    let p = UIBezierPath(rect: box); p.lineWidth = 0.35; p.stroke()
                }
                // Verticale de séparation entre jours
                let xSep = margin + leftColumnWidth + CGFloat(i) * dayColumnWidth
                UIColor(white: 0.75, alpha: 1).setStroke()
                let v = UIBezierPath()
                v.move(to: CGPoint(x: xSep, y: y))
                v.addLine(to: CGPoint(x: xSep, y: y + rowHeight))
                v.lineWidth = 0.4; v.stroke()
            }
            // dernière verticale
            let xLast = margin + leftColumnWidth + CGFloat(dayHeaders.count) * dayColumnWidth
            UIColor(white: 0.75, alpha: 1).setStroke()
            let vLast = UIBezierPath()
            vLast.move(to: CGPoint(x: xLast, y: y))
            vLast.addLine(to: CGPoint(x: xLast, y: y + rowHeight))
            vLast.lineWidth = 0.4; vLast.stroke()

            y += rowHeight
        }
        y += BookletLayoutEngine.sectionGap
    }

    private static func truncateForCell(_ s: String, width: CGFloat, font: UIFont) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if (s as NSString).size(withAttributes: attrs).width <= width { return s }
        var t = s
        while t.count > 1 && (t as NSString).appending("…").size(withAttributes: attrs).width > width {
            t.removeLast()
        }
        return t + "…"
    }
}
