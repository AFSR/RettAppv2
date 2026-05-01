import Foundation
import UIKit
import PDFKit

/// Génère un rapport médical PDF imprimable pour le médecin traitant.
///
/// Format inspiré du **calendrier des crises** (seizure diary) recommandé par les
/// neurologues — c'est l'équivalent papier que les familles remplissent depuis des
/// années. Pas de norme HL7 stricte ici (le CDA-R2 serait du XML, pas du PDF), mais
/// la structure suit les bonnes pratiques cliniques :
///
/// 1. En-tête (titre + date génération)
/// 2. Identité du patient + période couverte
/// 3. Traitement médicamenteux en cours
/// 4. Synthèse statistique (KPIs : nombre, durée moyenne, types, déclencheurs)
/// 5. Tableau chronologique des crises (paginé si > 20)
/// 6. Observance médicamenteuse sur la période
/// 7. Observations parent
/// 8. Pied de page : disclaimer non-dispositif médical + date
enum MedicalReportGenerator {

    static let reportsDirectoryName = "Reports"

    struct Input {
        let child: ChildProfile?
        let periodStart: Date
        let periodEnd: Date
        let seizures: [SeizureEvent]    // déjà filtrées sur la période
        let medications: [Medication]
        let logs: [MedicationLog]       // déjà filtrées sur la période
        let parentNotes: String
    }

    static func generate(_ input: Input) throws -> URL {
        let pageWidth: CGFloat = 595.0   // A4 portrait, 72 dpi
        let pageHeight: CGFloat = 842.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "RettApp",
            kCGPDFContextAuthor as String: "Association Française du Syndrome de Rett",
            kCGPDFContextTitle as String: "Rapport de suivi - \(input.child?.firstName ?? "Enfant")"
        ] as [String: Any]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let url = try makeReportURL(child: input.child, generatedAt: Date())

        let layout = Layout(pageRect: pageRect)

        try renderer.writePDF(to: url) { context in
            var ctx = DrawContext(cgContext: context.cgContext, layout: layout)
            ctx.beginPage(context: context)

            drawHeader(input: input, ctx: &ctx, context: context)
            drawIdentity(input: input, ctx: &ctx, context: context)
            drawMedicationPlan(input: input, ctx: &ctx, context: context)
            drawStatistics(input: input, ctx: &ctx, context: context)
            drawSeizureTable(input: input, ctx: &ctx, context: context)
            drawAdherence(input: input, ctx: &ctx, context: context)
            drawParentNotes(input: input, ctx: &ctx, context: context)
            drawFooter(input: input, ctx: &ctx, context: context)
        }

        return url
    }

    /// URL du dossier des rapports archivés.
    static func reportsDirectory() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = docs.appendingPathComponent(reportsDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Liste les rapports archivés, triés du plus récent au plus ancien.
    static func archivedReports() -> [URL] {
        guard let dir = try? reportsDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.creationDateKey]
              )
        else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted {
                ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                    >
                ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
            }
    }

    static func deleteReport(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Naming

    private static func makeReportURL(child: ChildProfile?, generatedAt: Date) throws -> URL {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = fmt.string(from: generatedAt)
        let name = (child?.firstName ?? "Enfant").folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: " ", with: "_")
        let filename = "RettApp_Rapport_\(name)_\(stamp).pdf"
        return try reportsDirectory().appendingPathComponent(filename)
    }

    // MARK: - Layout & drawing helpers

    private struct Layout {
        let pageRect: CGRect
        let margin: CGFloat = 40
        var contentRect: CGRect { pageRect.insetBy(dx: margin, dy: margin) }
    }

    private struct DrawContext {
        let cgContext: CGContext
        let layout: Layout
        var y: CGFloat = 0     // curseur vertical depuis le haut de la page
        var pageNumber: Int = 0
    }

    private static func beginPageIfNeeded(neededHeight: CGFloat, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        let bottom = ctx.layout.pageRect.height - ctx.layout.margin - 30 // espace pied de page
        if ctx.y + neededHeight > bottom {
            ctx.beginPage(context: context)
        }
    }

    // MARK: - Sections

    private static func drawHeader(input: Input, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        let title = "Rapport de suivi médical"
        let subtitle = "Association Française du Syndrome de Rett — RettApp"
        let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
        let subFont = UIFont.systemFont(ofSize: 11, weight: .light)

        title.draw(at: CGPoint(x: ctx.layout.margin, y: ctx.y), withAttributes: [
            .font: titleFont, .foregroundColor: UIColor.black
        ])
        ctx.y += titleFont.lineHeight + 2

        subtitle.draw(at: CGPoint(x: ctx.layout.margin, y: ctx.y), withAttributes: [
            .font: subFont, .foregroundColor: UIColor.darkGray
        ])
        ctx.y += subFont.lineHeight + 12

        // Trait sous le header
        let path = UIBezierPath()
        path.move(to: CGPoint(x: ctx.layout.margin, y: ctx.y))
        path.addLine(to: CGPoint(x: ctx.layout.pageRect.width - ctx.layout.margin, y: ctx.y))
        UIColor.black.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        ctx.y += 12
    }

    private static func drawIdentity(input: Input, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        drawSectionTitle("Identité du patient", ctx: &ctx)

        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMMM yyyy"

        var lines: [(String, String)] = []
        lines.append(("Prénom", input.child?.firstName ?? "—"))
        if let bd = input.child?.birthDate {
            lines.append(("Date de naissance", df.string(from: bd)))
            if let age = input.child?.ageYears {
                lines.append(("Âge", "\(age) ans"))
            }
        }
        lines.append(("Période du rapport", "du \(df.string(from: input.periodStart)) au \(df.string(from: input.periodEnd))"))

        drawKeyValueLines(lines, ctx: &ctx, context: context)
        ctx.y += 12
    }

    private static func drawMedicationPlan(input: Input, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        drawSectionTitle("Traitement médicamenteux en cours", ctx: &ctx)
        let actives = input.medications.filter { $0.isActive }
        if actives.isEmpty {
            drawText("Aucun médicament actif déclaré.", italic: true, ctx: &ctx)
            ctx.y += 12
            return
        }
        let headers = ["Nom", "Dose", "Horaires"]
        let widths: [CGFloat] = [180, 80, 250]
        var rows: [[String]] = []
        for m in actives {
            rows.append([m.name, m.doseLabel, m.scheduledHours.map(\.formatted).joined(separator: " · ")])
        }
        drawTable(headers: headers, columnWidths: widths, rows: rows, ctx: &ctx, context: context)
        ctx.y += 12
    }

    private static func drawStatistics(input: Input, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        drawSectionTitle("Synthèse statistique", ctx: &ctx)
        let count = input.seizures.count
        let totalSec = input.seizures.reduce(0) { $0 + $1.durationSeconds }
        let avg = count > 0 ? Double(totalSec) / Double(count) : 0

        // Type le plus fréquent
        var typeFreq: [SeizureType: Int] = [:]
        input.seizures.forEach { typeFreq[$0.seizureType, default: 0] += 1 }
        let topType = typeFreq.max(by: { $0.value < $1.value })

        // Déclencheur le plus fréquent (hors none)
        var triggerFreq: [SeizureTrigger: Int] = [:]
        input.seizures.forEach { triggerFreq[$0.trigger, default: 0] += 1 }
        let topTrigger = triggerFreq
            .filter { $0.key != .none }
            .max(by: { $0.value < $1.value })

        let lines: [(String, String)] = [
            ("Nombre total de crises", "\(count)"),
            ("Durée totale", formatDurationCompact(totalSec)),
            ("Durée moyenne par crise", count > 0 ? formatDurationCompact(Int(avg)) : "—"),
            ("Type le plus fréquent", topType.map { "\($0.key.label) (\($0.value)×)" } ?? "—"),
            ("Déclencheur identifié le plus fréquent", topTrigger.map { "\($0.key.label) (\($0.value)×)" } ?? "Aucun")
        ]
        drawKeyValueLines(lines, ctx: &ctx, context: context)
        ctx.y += 12
    }

    private static func drawSeizureTable(input: Input, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        drawSectionTitle("Calendrier détaillé des crises", ctx: &ctx)
        if input.seizures.isEmpty {
            drawText("Aucune crise enregistrée sur la période.", italic: true, ctx: &ctx)
            ctx.y += 12
            return
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "dd/MM/yyyy HH:mm"

        let headers = ["Date / heure", "Durée", "Type", "Déclencheur", "Notes"]
        let widths: [CGFloat] = [105, 60, 90, 90, 170]
        let sorted = input.seizures.sorted { $0.startTime < $1.startTime }
        let rows: [[String]] = sorted.map { s in
            [
                df.string(from: s.startTime),
                formatDurationCompact(s.durationSeconds),
                s.seizureType.label,
                s.trigger == .none ? "—" : s.trigger.label,
                s.notes
            ]
        }
        drawTable(headers: headers, columnWidths: widths, rows: rows, ctx: &ctx, context: context)
        ctx.y += 12
    }

    private static func drawAdherence(input: Input, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        drawSectionTitle("Observance médicamenteuse", ctx: &ctx)
        let scheduled = input.logs.count
        let taken = input.logs.filter { $0.taken }.count
        let pct = scheduled > 0 ? Int(Double(taken) / Double(scheduled) * 100) : 0
        let lines: [(String, String)] = [
            ("Prises planifiées", "\(scheduled)"),
            ("Prises effectives", "\(taken)"),
            ("Taux d'observance", scheduled > 0 ? "\(pct) %" : "—")
        ]
        drawKeyValueLines(lines, ctx: &ctx, context: context)
        ctx.y += 12
    }

    private static func drawParentNotes(input: Input, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        drawSectionTitle("Observations du parent / aidant", ctx: &ctx)
        let text = input.parentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        drawText(text.isEmpty ? "(aucune observation)" : text, italic: text.isEmpty, ctx: &ctx)
        ctx.y += 12
    }

    private static func drawFooter(input: Input, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        let footerY = ctx.layout.pageRect.height - ctx.layout.margin - 20
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMMM yyyy 'à' HH:mm"
        let footerFont = UIFont.systemFont(ofSize: 8, weight: .light)
        let line1 = "Rapport généré par RettApp le \(df.string(from: Date()))."
        let line2 = "RettApp est un outil de suivi destiné aux aidants. Ce n'est pas un dispositif médical au sens du règlement UE 2017/745."
        line1.draw(at: CGPoint(x: ctx.layout.margin, y: footerY), withAttributes: [
            .font: footerFont, .foregroundColor: UIColor.darkGray
        ])
        line2.draw(at: CGPoint(x: ctx.layout.margin, y: footerY + footerFont.lineHeight + 1), withAttributes: [
            .font: footerFont, .foregroundColor: UIColor.darkGray
        ])
    }

    // MARK: - Drawing primitives

    private static func drawSectionTitle(_ title: String, ctx: inout DrawContext) {
        let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        title.draw(at: CGPoint(x: ctx.layout.margin, y: ctx.y), withAttributes: [
            .font: font, .foregroundColor: UIColor.black
        ])
        ctx.y += font.lineHeight + 4
    }

    private static func drawText(_ text: String, italic: Bool = false, ctx: inout DrawContext) {
        let font = italic
            ? UIFont.italicSystemFont(ofSize: 10)
            : UIFont.systemFont(ofSize: 10)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let rect = CGRect(
            x: ctx.layout.margin, y: ctx.y,
            width: ctx.layout.contentRect.width,
            height: 200
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: para
        ]
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        (text as NSString).draw(in: CGRect(origin: rect.origin, size: bounding.size), withAttributes: attrs)
        ctx.y += bounding.size.height + 2
    }

    private static func drawKeyValueLines(_ lines: [(String, String)], ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        let labelFont = UIFont.systemFont(ofSize: 10, weight: .medium)
        let valueFont = UIFont.systemFont(ofSize: 10)
        let labelWidth: CGFloat = 200
        for (k, v) in lines {
            beginPageIfNeeded(neededHeight: 16, ctx: &ctx, context: context)
            k.draw(at: CGPoint(x: ctx.layout.margin, y: ctx.y), withAttributes: [
                .font: labelFont, .foregroundColor: UIColor.black
            ])
            v.draw(at: CGPoint(x: ctx.layout.margin + labelWidth, y: ctx.y), withAttributes: [
                .font: valueFont, .foregroundColor: UIColor.darkGray
            ])
            ctx.y += 14
        }
    }

    private static func drawTable(
        headers: [String],
        columnWidths: [CGFloat],
        rows: [[String]],
        ctx: inout DrawContext,
        context: UIGraphicsPDFRendererContext
    ) {
        let headerFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 9)
        let rowHeight: CGFloat = 18
        let headerHeight: CGFloat = 22

        func drawHeaderRow() {
            // fond gris léger
            let bg = CGRect(
                x: ctx.layout.margin, y: ctx.y,
                width: columnWidths.reduce(0, +), height: headerHeight
            )
            UIColor(white: 0.92, alpha: 1).setFill()
            UIBezierPath(rect: bg).fill()
            var x = ctx.layout.margin
            for (i, h) in headers.enumerated() {
                h.draw(in: CGRect(x: x + 4, y: ctx.y + 5, width: columnWidths[i] - 8, height: headerHeight),
                       withAttributes: [.font: headerFont, .foregroundColor: UIColor.black])
                x += columnWidths[i]
            }
            ctx.y += headerHeight
        }

        beginPageIfNeeded(neededHeight: headerHeight + rowHeight, ctx: &ctx, context: context)
        drawHeaderRow()

        for row in rows {
            beginPageIfNeeded(neededHeight: rowHeight, ctx: &ctx, context: context)
            // si on vient de changer de page, redessiner les en-têtes
            if ctx.y < ctx.layout.margin + 100 && ctx.pageNumber > 1 {
                drawHeaderRow()
            }
            // Trait haut
            let topY = ctx.y
            var x = ctx.layout.margin
            for (i, cell) in row.enumerated() where i < columnWidths.count {
                let truncated = truncateForCell(cell, width: columnWidths[i] - 8, font: cellFont)
                truncated.draw(in: CGRect(x: x + 4, y: ctx.y + 4, width: columnWidths[i] - 8, height: rowHeight),
                               withAttributes: [.font: cellFont, .foregroundColor: UIColor.darkGray])
                x += columnWidths[i]
            }
            // ligne de séparation
            UIColor(white: 0.85, alpha: 1).setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: ctx.layout.margin, y: topY + rowHeight))
            line.addLine(to: CGPoint(x: ctx.layout.margin + columnWidths.reduce(0, +), y: topY + rowHeight))
            line.lineWidth = 0.3
            line.stroke()
            ctx.y += rowHeight
        }
    }

    private static func truncateForCell(_ s: String, width: CGFloat, font: UIFont) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if (s as NSString).size(withAttributes: attrs).width <= width { return s }
        var truncated = s
        while truncated.count > 1 && (truncated as NSString).appending("…").size(withAttributes: attrs).width > width {
            truncated.removeLast()
        }
        return truncated + "…"
    }

    private static func formatDurationCompact(_ seconds: Int) -> String {
        if seconds == 0 { return "0 s" }
        let m = seconds / 60
        let s = seconds % 60
        if m == 0 { return "\(s) s" }
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) s"
    }
}

private extension MedicalReportGenerator.DrawContext {
    mutating func beginPage(context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        pageNumber += 1
        y = layout.margin
    }
}
