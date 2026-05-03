import Foundation
import UIKit

/// Génère un PDF **A4 portrait, dense, mono-page** destiné à être imprimé et
/// confié à l'équipe encadrante (école, IME, IMP, centre).
///
/// Contraintes de mise en page :
///   - Format : A4 portrait (595 × 842 pt)
///   - Une seule page : on dimensionne tous les éléments en fonction du
///     contenu activé (sections, nb de prises, nb de symptômes…) pour rester
///     en deçà de la limite verticale.
///   - Police compacte (corps 8 pt, en-têtes 9 pt) tout en restant lisible
///     en impression A4 noir & blanc.
enum FollowUpBookletGenerator {

    struct Options {
        var coverChildName: String
        var coverPeriodLabel: String
        var includeMedicationGrid: Bool
        var includeSeizureGrid: Bool
        var includeMoodGrid: Bool
        var includeMealsGrid: Bool
        var includeSleepGrid: Bool
        var includeSymptomsGrid: Bool
        var includeFreeNotes: Bool
        var medications: [Medication]
        /// Si true, toutes les prises planifiées des médicaments actifs sont
        /// incluses ; sinon on filtre via selectedDoses.
        var allDosesSelected: Bool
        /// Sous-ensemble (médicament + horaire) à inclure.
        var selectedDoses: Set<DoseKey>
        var selectedMealSlots: Set<MealSlot>
        var selectedSymptoms: Set<RettSymptom>
        var dayCount: Int
    }

    static let bookletDirectoryName = "Booklets"

    // Layout A4 portrait : 595 x 842 pt
    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 24
    private static let footerReserve: CGFloat = 18

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

            // Calcul des sections + lignes prévues, puis on utilise les
            // hauteurs adaptatives pour respecter une page unique.
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
                drawFreeNotes(y: &y, lineCount: plan.freeNotesLines)
            }

            drawFooter()
        }

        return url
    }

    // MARK: - Layout planner (auto-fit single page)

    /// Hauteurs de lignes adaptatives par section, calculées pour que tout
    /// rentre sur une page A4 portrait. Si le contenu déborde même au minimum,
    /// on retient les hauteurs minimales (l'utilisateur a alors trop de
    /// sections — la mise en page reste tassée mais lisible).
    private struct LayoutPlan {
        var medicationRowHeight: CGFloat
        var seizureRowHeight: CGFloat
        var moodRowHeight: CGFloat
        var mealsRowHeight: CGFloat
        var sleepRowHeight: CGFloat
        var symptomsRowHeight: CGFloat
        var freeNotesLines: Int
    }

    private static func layoutPlan(for options: Options, availableHeight: CGFloat) -> LayoutPlan {
        // Compte des lignes par section
        let medRows = doseRowCount(options: options)
        let seizureRows = SeizureType.allCases.count + 1
        let moodRows = 5
        let mealsRows = options.selectedMealSlots.count + 1   // + ligne hydratation
        let sleepRows = 5
        let symptomRows = options.selectedSymptoms.count

        // Surcoût fixe par section (titre + en-tête de tableau)
        let sectionOverhead: CGFloat = 28
        var fixedOverhead: CGFloat = 0
        if options.includeMedicationGrid && medRows > 0 { fixedOverhead += sectionOverhead }
        if options.includeSeizureGrid { fixedOverhead += sectionOverhead }
        if options.includeMoodGrid { fixedOverhead += sectionOverhead }
        if options.includeMealsGrid && mealsRows > 1 { fixedOverhead += sectionOverhead }
        if options.includeSleepGrid { fixedOverhead += sectionOverhead }
        // Symptômes : titre + 2 bandes d'en-tête (jour + M/A)
        if options.includeSymptomsGrid && symptomRows > 0 { fixedOverhead += sectionOverhead + 12 }
        // Notes libres : titre seulement
        if options.includeFreeNotes { fixedOverhead += 16 }

        // Lignes totales à caser
        let totalRows = (options.includeMedicationGrid ? medRows : 0)
            + (options.includeSeizureGrid ? seizureRows : 0)
            + (options.includeMoodGrid ? moodRows : 0)
            + (options.includeMealsGrid ? mealsRows : 0)
            + (options.includeSleepGrid ? sleepRows : 0)
            + (options.includeSymptomsGrid ? symptomRows : 0)

        // Espace restant pour les lignes
        let rowSpace = max(0, availableHeight - fixedOverhead)

        // Espace minimal réservé aux notes libres
        let freeNotesSpace: CGFloat = options.includeFreeNotes ? 60 : 0
        let availableForRows = max(0, rowSpace - freeNotesSpace)

        // Hauteur unifiée par ligne : aussi grande que possible (max 18, min 11)
        let perRow: CGFloat
        if totalRows > 0 {
            let raw = availableForRows / CGFloat(totalRows)
            perRow = max(11, min(18, raw))
        } else {
            perRow = 16
        }

        // Notes libres : on calcule combien de lignes on peut tenir dans le
        // freeNotesSpace + reliquat éventuel.
        let usedByRows = perRow * CGFloat(totalRows)
        let leftover = max(0, availableForRows - usedByRows)
        let notesAvailable = freeNotesSpace + leftover
        let lineHeight: CGFloat = 14
        let notesLines = max(2, min(8, Int(notesAvailable / lineHeight)))

        return LayoutPlan(
            medicationRowHeight: perRow,
            seizureRowHeight: perRow,
            moodRowHeight: perRow,
            mealsRowHeight: perRow,
            sleepRowHeight: perRow,
            symptomsRowHeight: perRow,
            freeNotesLines: notesLines
        )
    }

    private static func doseRowCount(options: Options) -> Int {
        let actives = options.medications.filter { $0.isActive }
        var count = 0
        for med in actives {
            for h in med.scheduledHours {
                let key = DoseKey(medicationID: med.id, hour: h.hour, minute: h.minute)
                if options.allDosesSelected || options.selectedDoses.contains(key) {
                    count += 1
                }
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
        let titleFont = UIFont.systemFont(ofSize: 13, weight: .bold)
        let metaFont = UIFont.systemFont(ofSize: 9, weight: .regular)

        "Cahier de suivi quotidien".draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: titleFont, .foregroundColor: UIColor.black
        ])

        let metaText = "\(options.coverChildName) — \(options.coverPeriodLabel)"
        let metaSize = (metaText as NSString).size(withAttributes: [.font: metaFont])
        (metaText as NSString).draw(
            at: CGPoint(x: pageWidth - margin - metaSize.width, y: y + 3),
            withAttributes: [.font: metaFont, .foregroundColor: UIColor.darkGray]
        )
        y += titleFont.lineHeight + 2

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
            for h in med.scheduledHours {
                let key = DoseKey(medicationID: med.id, hour: h.hour, minute: h.minute)
                let included = options.allDosesSelected || options.selectedDoses.contains(key)
                guard included else { continue }
                rows.append("\(med.name) — \(med.doseLabel) à \(h.formatted)")
            }
        }
        guard !rows.isEmpty else { return }

        drawSectionTitle("Prises de médicaments (cocher quand donné)", y: &y)
        drawCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y,
                      leftColumnWidth: 220, rowHeight: rowHeight)
    }

    private static func drawSeizureGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        drawSectionTitle("Crises (nb / type / durée totale)", y: &y)
        let rows = SeizureType.allCases.map { "\($0.label)" } + ["Durée totale (min)"]
        drawWriteGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y,
                      leftColumnWidth: 180, rowHeight: rowHeight)
    }

    private static func drawMoodGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        drawSectionTitle("Humeur dominante", y: &y)
        let rows = ["😀 Très bien", "🙂 Bien", "😐 Neutre", "😟 Inquiétant / agité", "😢 Très difficile"]
        drawCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y,
                      leftColumnWidth: 170, rowHeight: rowHeight)
    }

    private static func drawMealsGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        let chosen = [MealSlot.breakfast, .lunch, .snack, .dinner].filter { options.selectedMealSlots.contains($0) }
        var rows: [String] = chosen.map { $0.label }
        rows.append("Hydratation (~ ml)")
        guard rows.count > 1 else { return }
        drawSectionTitle("Repas et hydratation (qualité, quantité, refus…)", y: &y)
        drawWriteGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y,
                      leftColumnWidth: 150, rowHeight: rowHeight)
    }

    private static func drawSleepGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        drawSectionTitle("Sommeil et siestes (durée + qualité)", y: &y)
        let rows = ["Sommeil de nuit (h)", "Qualité du sommeil", "Sieste matin (min)", "Sieste après-midi (min)", "Réveils nocturnes"]
        drawWriteGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y,
                      leftColumnWidth: 180, rowHeight: rowHeight)
    }

    /// Symptômes Rett — 2 cases par jour (matin / après-midi).
    private static func drawSymptomsGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, rowHeight: CGFloat) {
        drawSectionTitle("Symptômes Rett (M = matin · A = après-midi)", y: &y)

        let symptoms = RettSymptom.allCases.filter { options.selectedSymptoms.contains($0) }
        let days = dayHeaders(count: options.dayCount)
        let totalWidth = pageWidth - 2 * margin
        let leftWidth: CGFloat = 170
        let halfDayWidth = (totalWidth - leftWidth) / CGFloat(days.count * 2)

        let dayHeaderFont = UIFont.systemFont(ofSize: 8.5, weight: .semibold)
        let halfHeaderFont = UIFont.systemFont(ofSize: 7, weight: .regular)
        let cellFont = UIFont.systemFont(ofSize: 8)
        let dayHeaderHeight: CGFloat = 12
        let halfHeaderHeight: CGFloat = 10

        // Bandeau jours
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: totalWidth, height: dayHeaderHeight)).fill()
        for (i, h) in days.enumerated() {
            let x = margin + leftWidth + CGFloat(i) * halfDayWidth * 2
            let para = NSMutableParagraphStyle(); para.alignment = .center
            (h as NSString).draw(in: CGRect(x: x, y: y + 1, width: halfDayWidth * 2, height: dayHeaderHeight),
                                 withAttributes: [.font: dayHeaderFont, .foregroundColor: UIColor.black, .paragraphStyle: para])
        }
        y += dayHeaderHeight

        // Bandeau M / A
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

            let boxSize = min(rowHeight - 4, CGFloat(10))
            for i in 0..<(days.count * 2) {
                let x = margin + leftWidth + CGFloat(i) * halfDayWidth + (halfDayWidth - boxSize) / 2
                let box = CGRect(x: x, y: y + (rowHeight - boxSize) / 2, width: boxSize, height: boxSize)
                UIColor.black.setStroke()
                let p = UIBezierPath(rect: box); p.lineWidth = 0.4; p.stroke()
            }
            // Verticales doubles entre jours
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
        y += 4
    }

    private static func drawFreeNotes(y: inout CGFloat, lineCount: Int) {
        drawSectionTitle("Observations libres", y: &y)
        for _ in 0..<lineCount {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y + 12))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: y + 12))
            UIColor.lightGray.setStroke()
            path.lineWidth = 0.3
            path.stroke()
            y += 14
        }
        y += 2
    }

    private static func drawFooter() {
        let footerFont = UIFont.systemFont(ofSize: 6.5, weight: .light)
        let line = "Cahier généré par RettApp — outil de suivi pour aidants. Pas un dispositif médical."
        line.draw(at: CGPoint(x: margin, y: pageHeight - 14), withAttributes: [
            .font: footerFont, .foregroundColor: UIColor.darkGray
        ])
    }

    // MARK: - Drawing primitives

    private static func drawSectionTitle(_ title: String, y: inout CGFloat) {
        let font = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: font, .foregroundColor: UIColor.black
        ])
        y += font.lineHeight + 1
    }

    private static func drawCheckGrid(rows: [String], dayHeaders: [String], y: inout CGFloat, leftColumnWidth: CGFloat, rowHeight: CGFloat) {
        let totalWidth = pageWidth - 2 * margin
        let dayColumnWidth = (totalWidth - leftColumnWidth) / CGFloat(dayHeaders.count)
        let headerFont = UIFont.systemFont(ofSize: 8.5, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 8)

        let headerHeight: CGFloat = 12
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
            line.lineWidth = 0.3
            line.stroke()

            // Tronque le libellé si trop long pour la colonne (rare en A4)
            let truncated = truncateForCell(row, width: leftColumnWidth - 6, font: cellFont)
            truncated.draw(in: CGRect(x: margin + 3, y: y + max(0, (rowHeight - 9) / 2), width: leftColumnWidth - 6, height: rowHeight),
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
        y += 4
    }

    private static func drawWriteGrid(rows: [String], dayHeaders: [String], y: inout CGFloat, leftColumnWidth: CGFloat, rowHeight: CGFloat) {
        let totalWidth = pageWidth - 2 * margin
        let dayColumnWidth = (totalWidth - leftColumnWidth) / CGFloat(dayHeaders.count)
        let headerFont = UIFont.systemFont(ofSize: 8.5, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 8)

        let headerHeight: CGFloat = 12
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
            line.lineWidth = 0.3
            line.stroke()

            let truncated = truncateForCell(row, width: leftColumnWidth - 6, font: cellFont)
            truncated.draw(in: CGRect(x: margin + 3, y: y + max(0, (rowHeight - 9) / 2), width: leftColumnWidth - 6, height: rowHeight),
                           withAttributes: [.font: cellFont, .foregroundColor: UIColor.darkGray])

            for i in 0...dayHeaders.count {
                let x = margin + leftColumnWidth + CGFloat(i) * dayColumnWidth
                UIColor(white: 0.85, alpha: 1).setStroke()
                let v = UIBezierPath()
                v.move(to: CGPoint(x: x, y: y))
                v.addLine(to: CGPoint(x: x, y: y + rowHeight))
                v.lineWidth = 0.3
                v.stroke()
            }
            y += rowHeight
        }
        y += 4
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
