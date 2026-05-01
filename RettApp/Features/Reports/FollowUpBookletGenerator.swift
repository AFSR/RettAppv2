import Foundation
import UIKit

/// Génère un PDF A4 imprimable destiné aux **équipes encadrant l'enfant** (école,
/// IME, IMP, centre de loisirs, halte-garderie). Le personnel coche / remplit à la
/// main, puis les parents ressaisissent les données dans l'app le soir.
///
/// L'utilisateur sélectionne lui-même les sections à inclure via `Options`.
enum FollowUpBookletGenerator {

    struct Options {
        var coverChildName: String          // prénom à imprimer
        var coverPeriodLabel: String        // ex. "Semaine du 27 mai au 2 juin"
        var includeMedicationGrid: Bool     // grille des prises
        var includeSeizureGrid: Bool        // grille des crises
        var includeMoodGrid: Bool           // humeur / état général
        var includeMealsGrid: Bool          // repas
        var includeSleepGrid: Bool          // sommeil
        var includeFreeNotes: Bool          // case "observations libres"
        var medications: [Medication]       // pour pré-remplir la grille meds
        var dayCount: Int                   // 5 ou 7
    }

    static let bookletDirectoryName = "Booklets"

    static func generate(_ options: Options) throws -> URL {
        let pageWidth: CGFloat = 595.0
        let pageHeight: CGFloat = 842.0
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
            var y: CGFloat = 40

            drawCover(in: context, y: &y, options: options, pageWidth: pageWidth)

            if options.includeMedicationGrid && !options.medications.filter({ $0.isActive }).isEmpty {
                ensurePageSpace(needed: 240, in: context, y: &y, pageHeight: pageHeight)
                drawMedicationGrid(in: context, y: &y, options: options, pageWidth: pageWidth)
            }
            if options.includeSeizureGrid {
                ensurePageSpace(needed: 240, in: context, y: &y, pageHeight: pageHeight)
                drawSeizureGrid(in: context, y: &y, options: options, pageWidth: pageWidth)
            }
            if options.includeMoodGrid {
                ensurePageSpace(needed: 200, in: context, y: &y, pageHeight: pageHeight)
                drawMoodGrid(in: context, y: &y, options: options, pageWidth: pageWidth)
            }
            if options.includeMealsGrid {
                ensurePageSpace(needed: 200, in: context, y: &y, pageHeight: pageHeight)
                drawMealsGrid(in: context, y: &y, options: options, pageWidth: pageWidth)
            }
            if options.includeSleepGrid {
                ensurePageSpace(needed: 200, in: context, y: &y, pageHeight: pageHeight)
                drawSleepGrid(in: context, y: &y, options: options, pageWidth: pageWidth)
            }
            if options.includeFreeNotes {
                ensurePageSpace(needed: 240, in: context, y: &y, pageHeight: pageHeight)
                drawFreeNotes(in: context, y: &y, options: options, pageWidth: pageWidth)
            }

            drawFooter(pageWidth: pageWidth, pageHeight: pageHeight)
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

    private static func ensurePageSpace(needed: CGFloat, in context: UIGraphicsPDFRendererContext, y: inout CGFloat, pageHeight: CGFloat) {
        if y + needed > pageHeight - 60 {
            context.beginPage()
            y = 40
        }
    }

    private static func drawCover(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, pageWidth: CGFloat) {
        let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
        let subFont = UIFont.systemFont(ofSize: 12, weight: .regular)
        let nameFont = UIFont.systemFont(ofSize: 16, weight: .semibold)

        "Cahier de suivi quotidien".draw(at: CGPoint(x: 40, y: y), withAttributes: [
            .font: titleFont, .foregroundColor: UIColor.black
        ])
        y += titleFont.lineHeight + 4

        "À remplir par l'équipe encadrante au fil de la journée".draw(at: CGPoint(x: 40, y: y), withAttributes: [
            .font: subFont, .foregroundColor: UIColor.darkGray
        ])
        y += subFont.lineHeight + 14

        // Trait
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 40, y: y))
        path.addLine(to: CGPoint(x: pageWidth - 40, y: y))
        UIColor.black.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        y += 16

        // Carré identité
        let cardRect = CGRect(x: 40, y: y, width: pageWidth - 80, height: 100)
        UIColor(white: 0.96, alpha: 1).setFill()
        UIBezierPath(roundedRect: cardRect, cornerRadius: 8).fill()

        "Enfant :".draw(at: CGPoint(x: 56, y: y + 14), withAttributes: [
            .font: subFont, .foregroundColor: UIColor.darkGray
        ])
        options.coverChildName.draw(at: CGPoint(x: 110, y: y + 12), withAttributes: [
            .font: nameFont, .foregroundColor: UIColor.black
        ])

        "Période :".draw(at: CGPoint(x: 56, y: y + 44), withAttributes: [
            .font: subFont, .foregroundColor: UIColor.darkGray
        ])
        options.coverPeriodLabel.draw(at: CGPoint(x: 110, y: y + 42), withAttributes: [
            .font: nameFont, .foregroundColor: UIColor.black
        ])

        "Personne référente / encadrant : _______________________________".draw(
            at: CGPoint(x: 56, y: y + 74),
            withAttributes: [.font: subFont, .foregroundColor: UIColor.darkGray]
        )

        y += 116
    }

    private static func dayHeaders(count: Int) -> [String] {
        // Lun. à Ven. (5) ou Lun. à Dim. (7)
        let all = ["Lun.", "Mar.", "Mer.", "Jeu.", "Ven.", "Sam.", "Dim."]
        return Array(all.prefix(min(7, max(5, count))))
    }

    private static func drawMedicationGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, pageWidth: CGFloat) {
        drawSectionTitle("Prises de médicaments", y: &y)
        drawSectionHelp("Cocher la case quand le médicament a été donné. Heure réelle si différente de l'heure prévue.", y: &y)

        let actives = options.medications.filter { $0.isActive }
        var rows: [String] = []
        for m in actives {
            for h in m.scheduledHours {
                rows.append("\(m.name) — \(m.doseLabel) à \(h.formatted)")
            }
        }
        if rows.isEmpty { rows = ["(Médicament 1 — heure)", "(Médicament 2 — heure)"] }

        drawCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y, pageWidth: pageWidth, leftColumnWidth: 220)
    }

    private static func drawSeizureGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, pageWidth: CGFloat) {
        drawSectionTitle("Crises d'épilepsie observées", y: &y)
        drawSectionHelp("Indiquer le nombre de crises et leur durée approximative dans la case correspondante. Détail à reporter à l'oral aux parents.", y: &y)

        let rows = ["Matin (avant midi)", "Midi (12h–14h)", "Après-midi", "Goûter / fin journée", "Total durée (min)"]
        drawWriteGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y, pageWidth: pageWidth, leftColumnWidth: 200, rowHeight: 30)
    }

    private static func drawMoodGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, pageWidth: CGFloat) {
        drawSectionTitle("État général / humeur", y: &y)
        drawSectionHelp("Cocher la case correspondant à l'état dominant observé sur la journée.", y: &y)

        let rows = ["😀 Bien / serein", "😐 Calme / neutre", "😟 Agité / pleure", "😴 Très fatigué"]
        drawCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y, pageWidth: pageWidth, leftColumnWidth: 180)
    }

    private static func drawMealsGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, pageWidth: CGFloat) {
        drawSectionTitle("Repas et hydratation", y: &y)
        let rows = ["Petit-déj.", "Midi", "Goûter", "Hydratation suffisante"]
        drawCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y, pageWidth: pageWidth, leftColumnWidth: 180)
    }

    private static func drawSleepGrid(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, pageWidth: CGFloat) {
        drawSectionTitle("Sommeil / siestes", y: &y)
        let rows = ["Sieste matin", "Sieste après-midi", "Sommeil agité"]
        drawCheckGrid(rows: rows, dayHeaders: dayHeaders(count: options.dayCount), y: &y, pageWidth: pageWidth, leftColumnWidth: 180)
    }

    private static func drawFreeNotes(in context: UIGraphicsPDFRendererContext, y: inout CGFloat, options: Options, pageWidth: CGFloat) {
        drawSectionTitle("Observations libres", y: &y)
        // 8 lignes de saisie libre
        let lineFont = UIFont.systemFont(ofSize: 9)
        for _ in 0..<8 {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 40, y: y + 18))
            path.addLine(to: CGPoint(x: pageWidth - 40, y: y + 18))
            UIColor.lightGray.setStroke()
            path.lineWidth = 0.3
            path.stroke()
            y += 22
        }
        _ = lineFont
        y += 8
    }

    private static func drawFooter(pageWidth: CGFloat, pageHeight: CGFloat) {
        let footerFont = UIFont.systemFont(ofSize: 8, weight: .light)
        let line1 = "Cahier généré par RettApp — outil de suivi pour aidants. Ce document n'est pas un dispositif médical."
        line1.draw(at: CGPoint(x: 40, y: pageHeight - 30), withAttributes: [
            .font: footerFont, .foregroundColor: UIColor.darkGray
        ])
    }

    // MARK: - Drawing primitives

    private static func drawSectionTitle(_ title: String, y: inout CGFloat) {
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        title.draw(at: CGPoint(x: 40, y: y), withAttributes: [
            .font: font, .foregroundColor: UIColor.black
        ])
        y += font.lineHeight + 2
    }

    private static func drawSectionHelp(_ text: String, y: inout CGFloat) {
        let font = UIFont.italicSystemFont(ofSize: 9)
        text.draw(at: CGPoint(x: 40, y: y), withAttributes: [
            .font: font, .foregroundColor: UIColor.darkGray
        ])
        y += font.lineHeight + 6
    }

    /// Grille avec une colonne de libellé à gauche, puis N colonnes de jour avec une CASE À COCHER vide.
    private static func drawCheckGrid(rows: [String], dayHeaders: [String], y: inout CGFloat, pageWidth: CGFloat, leftColumnWidth: CGFloat, rowHeight: CGFloat = 26) {
        let totalWidth = pageWidth - 80
        let dayColumnWidth = (totalWidth - leftColumnWidth) / CGFloat(dayHeaders.count)
        let headerFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 10)

        // En-tête
        let headerHeight: CGFloat = 22
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: 40, y: y, width: totalWidth, height: headerHeight)).fill()
        for (i, h) in dayHeaders.enumerated() {
            let x = 40 + leftColumnWidth + CGFloat(i) * dayColumnWidth
            let para = NSMutableParagraphStyle(); para.alignment = .center
            (h as NSString).draw(in: CGRect(x: x, y: y + 5, width: dayColumnWidth, height: headerHeight),
                                 withAttributes: [.font: headerFont, .foregroundColor: UIColor.black, .paragraphStyle: para])
        }
        y += headerHeight

        // Lignes
        for row in rows {
            // Bordure de ligne
            UIColor(white: 0.85, alpha: 1).setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: 40, y: y + rowHeight))
            line.addLine(to: CGPoint(x: 40 + totalWidth, y: y + rowHeight))
            line.lineWidth = 0.3
            line.stroke()

            row.draw(in: CGRect(x: 44, y: y + 7, width: leftColumnWidth - 8, height: rowHeight),
                     withAttributes: [.font: cellFont, .foregroundColor: UIColor.darkGray])

            // Cases à cocher
            for i in 0..<dayHeaders.count {
                let x = 40 + leftColumnWidth + CGFloat(i) * dayColumnWidth + (dayColumnWidth - 14) / 2
                let box = CGRect(x: x, y: y + (rowHeight - 14) / 2, width: 14, height: 14)
                UIColor.black.setStroke()
                let p = UIBezierPath(rect: box); p.lineWidth = 0.6; p.stroke()
            }
            y += rowHeight
        }
        y += 12
    }

    /// Grille avec une colonne de libellé à gauche, puis N colonnes vides (pour écrire un texte).
    private static func drawWriteGrid(rows: [String], dayHeaders: [String], y: inout CGFloat, pageWidth: CGFloat, leftColumnWidth: CGFloat, rowHeight: CGFloat) {
        let totalWidth = pageWidth - 80
        let dayColumnWidth = (totalWidth - leftColumnWidth) / CGFloat(dayHeaders.count)
        let headerFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 10)

        let headerHeight: CGFloat = 22
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: 40, y: y, width: totalWidth, height: headerHeight)).fill()
        for (i, h) in dayHeaders.enumerated() {
            let x = 40 + leftColumnWidth + CGFloat(i) * dayColumnWidth
            let para = NSMutableParagraphStyle(); para.alignment = .center
            (h as NSString).draw(in: CGRect(x: x, y: y + 5, width: dayColumnWidth, height: headerHeight),
                                 withAttributes: [.font: headerFont, .foregroundColor: UIColor.black, .paragraphStyle: para])
        }
        y += headerHeight

        for row in rows {
            UIColor(white: 0.85, alpha: 1).setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: 40, y: y + rowHeight))
            line.addLine(to: CGPoint(x: 40 + totalWidth, y: y + rowHeight))
            line.lineWidth = 0.3
            line.stroke()

            row.draw(in: CGRect(x: 44, y: y + 8, width: leftColumnWidth - 8, height: rowHeight),
                     withAttributes: [.font: cellFont, .foregroundColor: UIColor.darkGray])

            // Verticales de séparation entre jours
            for i in 0...dayHeaders.count {
                let x = 40 + leftColumnWidth + CGFloat(i) * dayColumnWidth
                UIColor(white: 0.85, alpha: 1).setStroke()
                let v = UIBezierPath()
                v.move(to: CGPoint(x: x, y: y))
                v.addLine(to: CGPoint(x: x, y: y + rowHeight))
                v.lineWidth = 0.3
                v.stroke()
            }
            y += rowHeight
        }
        y += 12
    }
}
