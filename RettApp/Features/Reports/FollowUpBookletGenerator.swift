import Foundation
import UIKit

/// Génère un PDF **A4 paysage** imprimable destiné aux **équipes encadrant
/// l'enfant** (école, IME, IMP, centre). Le personnel coche / remplit à la
/// main, puis les parents ressaisissent les données dans l'app le soir.
///
/// L'orientation paysage (842 × 595 pt) permet d'aligner 7 colonnes-jours
/// + 1 colonne-libellé sans tasser la mise en page. Police de corps réduite
/// à 9 pt pour rester lisible tout en tenant la page.
enum FollowUpBookletGenerator {

    struct Options {
        var coverChildName: String
        var coverPeriodLabel: String
        var includeMedicationGrid: Bool
        var includeSeizureGrid: Bool
        var includeMoodGrid: Bool
        var includeMealsGrid: Bool
        var includeSleepGrid: Bool
        var includeSymptomsGrid: Bool          // symptômes Rett matin / après-midi
        var includeFreeNotes: Bool
        var medications: [Medication]
        /// IDs des médicaments à inclure (sous-ensemble de `medications`).
        /// Vide → tous les médicaments actifs sont inclus (back-compat).
        var selectedMedicationIDs: Set<UUID>
        /// Repas à suivre (un sous-ensemble de breakfast/lunch/snack/dinner).
        var selectedMealSlots: Set<MealSlot>
        /// Symptômes Rett à suivre (sous-ensemble de RettSymptom).
        var selectedSymptoms: Set<RettSymptom>
        var dayCount: Int                       // 5 ou 7
    }

    static let bookletDirectoryName = "Booklets"

    // Layout A4 paysage : 842 x 595 pt
    private static let pageWidth: CGFloat = 842
    private static let pageHeight: CGFloat = 595
    private static let margin: CGFloat = 32

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

            drawCover(in: context, y: &y, options: options)

            if options.includeMedicationGrid {
                ensurePageSpace(needed: 140, in: context, y: &y)
                drawMedicationGrid(in: context, y: &y, options: options)
            }
            if options.includeSeizureGrid {
                ensurePageSpace(needed: 160, in: context, y: &y)
                drawSeizureGrid(in: context, y: &y, options: options)
            }
            if options.includeMoodGrid {
                ensurePageSpace(needed: 130, in: context, y: &y)
                drawMoodGrid(in: context, y: &y, options: options)
            }
            if options.includeMealsGrid {
                ensurePageSpace(needed: 130, in: context, y: &y)
                drawMealsGrid(in: context, y: &y, options: options)
            }
            if options.includeSleepGrid {
                ensurePageSpace(needed: 130, in: context, y: &y)
                drawSleepGrid(in: context, y: &y, options: options)
            }
            if options.includeSymptomsGrid && !options.selectedSymptoms.isEmpty {
                ensurePageSpace(needed: 160, in: context, y: &y)
                drawSymptomsGrid(in: context, y: &y, options: options)
            }
            if options.includeFreeNotes {
                ensurePageSpace(needed: 120, in: context, y: &y)
                drawFreeNotes(in: context, y: &y, options: options)
            }

            drawFooter()
        }

        return url
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

    // MARK: - Drawing

    private static func ensurePageSpace(needed: CGFloat, in context: UIGraphicsPDFRendererContext, y: inout CGFloat) {
        if y + needed > pageHeight - 50 {
            drawFooter()
            context.beginPage()
            y = margin
        }
    }

    private static func drawCover(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options) {
        let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        let subFont = UIFont.systemFont(ofSize: 10, weight: .regular)
        let nameFont = UIFont.systemFont(ofSize: 13, weight: .semibold)

        "Cahier de suivi quotidien".draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: titleFont, .foregroundColor: UIColor.black
        ])

        // Bandeau identité à droite
        let cardWidth: CGFloat = 380
        let cardX = pageWidth - margin - cardWidth
        let cardRect = CGRect(x: cardX, y: y - 2, width: cardWidth, height: 50)
        UIColor(white: 0.96, alpha: 1).setFill()
        UIBezierPath(roundedRect: cardRect, cornerRadius: 6).fill()

        "Enfant :".draw(at: CGPoint(x: cardX + 12, y: y + 6), withAttributes: [
            .font: subFont, .foregroundColor: UIColor.darkGray
        ])
        options.coverChildName.draw(at: CGPoint(x: cardX + 60, y: y + 4), withAttributes: [
            .font: nameFont, .foregroundColor: UIColor.black
        ])
        "Période :".draw(at: CGPoint(x: cardX + 12, y: y + 28), withAttributes: [
            .font: subFont, .foregroundColor: UIColor.darkGray
        ])
        options.coverPeriodLabel.draw(at: CGPoint(x: cardX + 60, y: y + 26), withAttributes: [
            .font: nameFont, .foregroundColor: UIColor.black
        ])

        y += titleFont.lineHeight + 4
        "À remplir par l'équipe encadrante (école, IME, IMP, centre) au fil de la journée.".draw(
            at: CGPoint(x: margin, y: y),
            withAttributes: [.font: subFont, .foregroundColor: UIColor.darkGray]
        )
        y += subFont.lineHeight + 6

        // Trait
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        UIColor.black.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        y += 14
    }

    private static func dayHeaders(count: Int) -> [String] {
        let all = ["Lun.", "Mar.", "Mer.", "Jeu.", "Ven.", "Sam.", "Dim."]
        return Array(all.prefix(min(7, max(5, count))))
    }

    private static func drawMedicationGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options) {
        drawSectionTitle("Prises de médicaments", y: &y)
        drawSectionHelp("Cocher la case quand le médicament a été donné. Heure réelle si différente de l'heure prévue.", y: &y)

        // Filtre : médicaments actifs ∩ (selection si non vide)
        let actives = options.medications.filter { $0.isActive }
        let selected: [Medication] = options.selectedMedicationIDs.isEmpty
            ? actives
            : actives.filter { options.selectedMedicationIDs.contains($0.id) }

        var rows: [String] = []
        for m in selected {
            for h in m.scheduledHours {
                rows.append("\(m.name) — \(m.doseLabel) à \(h.formatted)")
            }
        }
        if rows.isEmpty {
            drawSectionHelp("(aucun médicament sélectionné)", y: &y)
            return
        }
        drawCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y, leftColumnWidth: 230)
    }

    private static func drawSeizureGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options) {
        drawSectionTitle("Crises d'épilepsie observées", y: &y)
        drawSectionHelp("Indiquer le nombre de crises observées par type sur la journée. Pour chaque crise, noter heure et durée approximative.", y: &y)

        let rows = SeizureType.allCases.map { "\($0.label)" } + ["Durée totale (min)"]
        drawWriteGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y, leftColumnWidth: 200, rowHeight: 22)
    }

    private static func drawMoodGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options) {
        drawSectionTitle("État général / humeur", y: &y)
        drawSectionHelp("Cocher la case correspondant à l'état dominant observé sur la journée.", y: &y)

        let rows = ["😀 Très bien", "🙂 Bien", "😐 Neutre", "😟 Inquiétant / agité", "😢 Très difficile"]
        drawCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y, leftColumnWidth: 200)
    }

    private static func drawMealsGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options) {
        drawSectionTitle("Repas et hydratation", y: &y)
        drawSectionHelp("Décrire qualitativement chaque repas (qualité, quantité, refus, aliments particuliers).", y: &y)
        // Sélection : un sous-ensemble de MealSlot + ligne hydratation
        let allSlots: [MealSlot] = [.breakfast, .lunch, .snack, .dinner]
        let chosen = allSlots.filter { options.selectedMealSlots.contains($0) }
        var rows: [String] = chosen.map { $0.label }
        rows.append("Hydratation (~ ml)")
        if rows.count == 1 {
            drawSectionHelp("(aucun repas sélectionné)", y: &y)
            return
        }
        drawWriteGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y, leftColumnWidth: 180, rowHeight: 22)
    }

    private static func drawSleepGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options) {
        drawSectionTitle("Sommeil et siestes", y: &y)
        drawSectionHelp("Indiquer durée + qualité (calme, agité, réveils…). Pour les siestes : durée approximative.", y: &y)
        let rows = ["Sommeil de nuit (durée)", "Qualité du sommeil", "Sieste matin", "Sieste après-midi", "Réveils nocturnes"]
        drawWriteGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y, leftColumnWidth: 200, rowHeight: 22)
    }

    /// Grille des symptômes Rett — granularité matin / après-midi pour chaque jour.
    /// Layout : 1 colonne libellé + N×2 colonnes (matin / aprèm) pour les jours.
    private static func drawSymptomsGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options) {
        drawSectionTitle("Symptômes Rett (matin / après-midi)", y: &y)
        drawSectionHelp("Cocher la case (M = matin, A = après-midi) lorsque le symptôme est observé pendant la demi-journée.", y: &y)

        let symptoms = RettSymptom.allCases.filter { options.selectedSymptoms.contains($0) }
        let days = dayHeaders(count: options.dayCount)
        let totalWidth = pageWidth - 2 * margin
        let leftWidth: CGFloat = 200
        let halfDayWidth = (totalWidth - leftWidth) / CGFloat(days.count * 2)

        let dayHeaderFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let halfHeaderFont = UIFont.systemFont(ofSize: 8, weight: .regular)
        let cellFont = UIFont.systemFont(ofSize: 9)
        let dayHeaderHeight: CGFloat = 16
        let halfHeaderHeight: CGFloat = 14
        let rowHeight: CGFloat = 18

        // Bandeau jours
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: totalWidth, height: dayHeaderHeight)).fill()
        for (i, h) in days.enumerated() {
            let x = margin + leftWidth + CGFloat(i) * halfDayWidth * 2
            let para = NSMutableParagraphStyle(); para.alignment = .center
            (h as NSString).draw(in: CGRect(x: x, y: y + 2, width: halfDayWidth * 2, height: dayHeaderHeight),
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
            ("M" as NSString).draw(in: CGRect(x: xM, y: y + 1, width: halfDayWidth, height: halfHeaderHeight),
                                   withAttributes: [.font: halfHeaderFont, .foregroundColor: UIColor.darkGray, .paragraphStyle: para])
            ("A" as NSString).draw(in: CGRect(x: xA, y: y + 1, width: halfDayWidth, height: halfHeaderHeight),
                                   withAttributes: [.font: halfHeaderFont, .foregroundColor: UIColor.darkGray, .paragraphStyle: para])
        }
        y += halfHeaderHeight

        // Lignes
        for s in symptoms {
            UIColor(white: 0.85, alpha: 1).setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: y + rowHeight))
            line.addLine(to: CGPoint(x: margin + totalWidth, y: y + rowHeight))
            line.lineWidth = 0.3
            line.stroke()

            s.label.draw(in: CGRect(x: margin + 4, y: y + 4, width: leftWidth - 8, height: rowHeight),
                         withAttributes: [.font: cellFont, .foregroundColor: UIColor.darkGray])

            // Cases : 2 par jour
            for i in 0..<(days.count * 2) {
                let x = margin + leftWidth + CGFloat(i) * halfDayWidth + (halfDayWidth - 12) / 2
                let box = CGRect(x: x, y: y + (rowHeight - 12) / 2, width: 12, height: 12)
                UIColor.black.setStroke()
                let p = UIBezierPath(rect: box); p.lineWidth = 0.5; p.stroke()
            }
            // Verticales doubles entre jours
            for i in 0...days.count {
                let x = margin + leftWidth + CGFloat(i * 2) * halfDayWidth
                UIColor(white: 0.7, alpha: 1).setStroke()
                let v = UIBezierPath()
                v.move(to: CGPoint(x: x, y: y))
                v.addLine(to: CGPoint(x: x, y: y + rowHeight))
                v.lineWidth = 0.4
                v.stroke()
            }
            y += rowHeight
        }
        y += 8
    }

    private static func drawFreeNotes(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options) {
        drawSectionTitle("Observations libres", y: &y)
        for _ in 0..<6 {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y + 14))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: y + 14))
            UIColor.lightGray.setStroke()
            path.lineWidth = 0.3
            path.stroke()
            y += 18
        }
        y += 6
    }

    private static func drawFooter() {
        let footerFont = UIFont.systemFont(ofSize: 7.5, weight: .light)
        let line1 = "Cahier généré par RettApp — outil de suivi pour aidants. Ce document n'est pas un dispositif médical."
        line1.draw(at: CGPoint(x: margin, y: pageHeight - 22), withAttributes: [
            .font: footerFont, .foregroundColor: UIColor.darkGray
        ])
    }

    // MARK: - Drawing primitives

    private static func drawSectionTitle(_ title: String, y: inout CGFloat) {
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: font, .foregroundColor: UIColor.black
        ])
        y += font.lineHeight + 1
    }

    private static func drawSectionHelp(_ text: String, y: inout CGFloat) {
        let font = UIFont.italicSystemFont(ofSize: 8.5)
        text.draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: font, .foregroundColor: UIColor.darkGray
        ])
        y += font.lineHeight + 4
    }

    private static func drawCheckGrid(rows: [String], dayHeaders: [String], y: inout CGFloat, leftColumnWidth: CGFloat, rowHeight: CGFloat = 20) {
        let totalWidth = pageWidth - 2 * margin
        let dayColumnWidth = (totalWidth - leftColumnWidth) / CGFloat(dayHeaders.count)
        let headerFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 9)

        let headerHeight: CGFloat = 18
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: totalWidth, height: headerHeight)).fill()
        for (i, h) in dayHeaders.enumerated() {
            let x = margin + leftColumnWidth + CGFloat(i) * dayColumnWidth
            let para = NSMutableParagraphStyle(); para.alignment = .center
            (h as NSString).draw(in: CGRect(x: x, y: y + 3, width: dayColumnWidth, height: headerHeight),
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

            row.draw(in: CGRect(x: margin + 4, y: y + 5, width: leftColumnWidth - 8, height: rowHeight),
                     withAttributes: [.font: cellFont, .foregroundColor: UIColor.darkGray])

            for i in 0..<dayHeaders.count {
                let x = margin + leftColumnWidth + CGFloat(i) * dayColumnWidth + (dayColumnWidth - 12) / 2
                let box = CGRect(x: x, y: y + (rowHeight - 12) / 2, width: 12, height: 12)
                UIColor.black.setStroke()
                let p = UIBezierPath(rect: box); p.lineWidth = 0.5; p.stroke()
            }
            y += rowHeight
        }
        y += 8
    }

    private static func drawWriteGrid(rows: [String], dayHeaders: [String], y: inout CGFloat, leftColumnWidth: CGFloat, rowHeight: CGFloat) {
        let totalWidth = pageWidth - 2 * margin
        let dayColumnWidth = (totalWidth - leftColumnWidth) / CGFloat(dayHeaders.count)
        let headerFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 9)

        let headerHeight: CGFloat = 18
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: totalWidth, height: headerHeight)).fill()
        for (i, h) in dayHeaders.enumerated() {
            let x = margin + leftColumnWidth + CGFloat(i) * dayColumnWidth
            let para = NSMutableParagraphStyle(); para.alignment = .center
            (h as NSString).draw(in: CGRect(x: x, y: y + 3, width: dayColumnWidth, height: headerHeight),
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

            row.draw(in: CGRect(x: margin + 4, y: y + 5, width: leftColumnWidth - 8, height: rowHeight),
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
        y += 8
    }
}
