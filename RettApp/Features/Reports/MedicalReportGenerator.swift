import Foundation
import UIKit
import PDFKit

/// Génère un rapport médical PDF imprimable pour le médecin traitant.
///
/// Structure du document (A4 portrait, multi-pages, paginé automatiquement) :
///
/// 1. **En-tête** — titre + date de génération + période
/// 2. **Identité patient** — prénom + nom + date de naissance + âge
/// 3. **Disclaimers réglementaires** — non-dispositif médical, finalité documentaire
/// 4. **Synthèse statistique** — compteurs + graphiques fréquence et intensité
///    (granularité adaptée à la période : journalière, hebdomadaire, mensuelle)
/// 5. **Répartition par type** — graphique à barres horizontales
/// 6. **Étude exploratoire des corrélations** — Pearson entre fréquence des crises
///    et humeur / repas / sommeil / observance, avec interprétation textuelle
/// 7. **Analyse du plan médicamenteux** — par traitement : adhérence, régularité
///    (écart-type des décalages horaires), retards, oublis
/// 8. **Synthèse rédigée pour le médecin** — texte consolidé (volume, types, déclencheurs,
///    observance, humeur, corrélations significatives)
/// 9. **Observations parent** — bloc libre saisi par l'utilisateur
/// 10. **Annexe** — calendrier détaillé chronologique de toutes les crises
/// 11. **Pied de page** sur chaque page — disclaimer + date génération
@MainActor
enum MedicalReportGenerator {

    static let reportsDirectoryName = "Reports"

    struct Input {
        let child: ChildProfile?
        let periodStart: Date
        let periodEnd: Date
        let seizures: [SeizureEvent]
        let medications: [Medication]
        let logs: [MedicationLog]
        let moods: [MoodEntry]
        let observations: [DailyObservation]
        let symptoms: [SymptomEvent]
        let parentNotes: String
    }

    @MainActor
    static func generate(_ input: Input) throws -> URL {
        let pageWidth: CGFloat = 595.0
        let pageHeight: CGFloat = 842.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "RettApp",
            kCGPDFContextAuthor as String: "Association Française du Syndrome de Rett",
            kCGPDFContextTitle as String: "Rapport de suivi - \(input.child?.fullName ?? "Enfant")"
        ] as [String: Any]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let url = try makeReportURL(child: input.child, generatedAt: Date())

        // Pré-calculs
        let analysisInput = MedicalReportAnalysis.Input(
            periodStart: input.periodStart, periodEnd: input.periodEnd,
            seizures: input.seizures, medications: input.medications,
            logs: input.logs, moods: input.moods, observations: input.observations,
            symptoms: input.symptoms
        )
        let overall = MedicalReportAnalysis.computeOverall(analysisInput)
        let granularity = MedicalReportAnalysis.granularity(for: overall.periodDays)
        var seizureBuckets = MedicalReportAnalysis.buckets(
            start: input.periodStart, end: input.periodEnd, granularity: granularity
        )
        MedicalReportAnalysis.fillSeizureBuckets(&seizureBuckets, seizures: input.seizures)

        let dailySignals = MedicalReportAnalysis.dailySignals(analysisInput)
        let correlations = MedicalReportAnalysis.correlations(from: dailySignals)
        let medAnalysis = MedicalReportAnalysis.analyzeMedicationPlan(analysisInput)
        let symptomAnalysis = MedicalReportAnalysis.analyzeSymptoms(analysisInput)

        let layout = Layout(pageRect: pageRect)
        try renderer.writePDF(to: url) { context in
            var ctx = DrawContext(layout: layout)
            ctx.beginPage(context: context)

            drawHeader(input: input, ctx: &ctx, context: context)
            drawIdentity(input: input, ctx: &ctx, context: context)
            drawDisclaimer(ctx: &ctx, context: context)

            drawStatsSection(input: input, overall: overall, granularity: granularity,
                             buckets: seizureBuckets, ctx: &ctx, context: context)

            drawCorrelationsSection(correlations: correlations, ctx: &ctx, context: context)

            drawMedicationAnalysis(analysis: medAnalysis, ctx: &ctx, context: context)

            drawSymptomAnalysis(analysis: symptomAnalysis, ctx: &ctx, context: context)

            drawSynthesis(input: input, overall: overall,
                          correlations: correlations, medAnalysis: medAnalysis,
                          symptomAnalysis: symptomAnalysis,
                          ctx: &ctx, context: context)

            drawParentNotes(input: input, ctx: &ctx, context: context)

            // Annexe - sur nouvelle page
            ctx.beginPage(context: context)
            drawAnnexHeader(ctx: &ctx)
            drawSeizureTable(input: input, ctx: &ctx, context: context)

            // Footer + pagination ne nécessitent pas d'append spécial — déjà tracé dans beginPage
        }

        return url
    }

    // MARK: - File management

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

    static func archivedReports() -> [URL] {
        guard let dir = try? reportsDirectory(),
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

    static func deleteReport(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    private static func makeReportURL(child: ChildProfile?, generatedAt: Date) throws -> URL {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = fmt.string(from: generatedAt)
        let name = (child?.fullName ?? "Enfant").folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: " ", with: "_")
        let filename = "RettApp_Rapport_\(name)_\(stamp).pdf"
        return try reportsDirectory().appendingPathComponent(filename)
    }

    // MARK: - Layout

    private struct Layout {
        let pageRect: CGRect
        let margin: CGFloat = 40
        var contentRect: CGRect { pageRect.insetBy(dx: margin, dy: margin) }
        var contentWidth: CGFloat { pageRect.width - 2 * margin }
        var bottomLimit: CGFloat { pageRect.height - margin - 40 } // garde la place pour footer
    }

    @MainActor
    private struct DrawContext {
        let layout: Layout
        var y: CGFloat = 0
        var pageNumber: Int = 0

        mutating func beginPage(context: UIGraphicsPDFRendererContext) {
            context.beginPage()
            pageNumber += 1
            y = layout.margin
            drawPageFooter(context: context, layout: layout, pageNumber: pageNumber)
        }

        mutating func ensureSpace(_ needed: CGFloat, context: UIGraphicsPDFRendererContext) {
            if y + needed > layout.bottomLimit {
                beginPage(context: context)
            }
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
        ctx.y += subFont.lineHeight + 8

        let path = UIBezierPath()
        path.move(to: CGPoint(x: ctx.layout.margin, y: ctx.y))
        path.addLine(to: CGPoint(x: ctx.layout.pageRect.width - ctx.layout.margin, y: ctx.y))
        UIColor.black.setStroke(); path.lineWidth = 0.5; path.stroke()
        ctx.y += 12
    }

    private static func drawIdentity(input: Input, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        drawSectionTitle("Identité du patient", ctx: &ctx)

        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMMM yyyy"

        var lines: [(String, String)] = []
        lines.append(("Patient", input.child?.fullName ?? "—"))
        if let bd = input.child?.birthDate {
            lines.append(("Date de naissance", df.string(from: bd)))
            if let age = input.child?.ageYears {
                lines.append(("Âge", "\(age) ans"))
            }
        }
        lines.append(("Période du rapport",
                      "du \(df.string(from: input.periodStart)) au \(df.string(from: input.periodEnd))"))

        drawKeyValueLines(lines, ctx: &ctx, context: context)
        ctx.y += 8
    }

    private static func drawDisclaimer(ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        ctx.ensureSpace(60, context: context)
        let text = "Document généré par RettApp à partir des données saisies par les aidants. RettApp est un outil de suivi destiné aux parents et aidants. Ce n'est pas un dispositif médical au sens du règlement européen 2017/745 (MDR). Les analyses statistiques et corrélations ci-dessous sont fournies à titre exploratoire et n'ont pas valeur de diagnostic. Elles ne se substituent pas à l'avis du médecin."
        drawCallout(text, ctx: &ctx, context: context, color: UIColor.systemOrange.withAlphaComponent(0.10), borderColor: UIColor.systemOrange)
        ctx.y += 12
    }

    private static func drawStatsSection(
        input: Input, overall: MedicalReportAnalysis.OverallStats,
        granularity: MedicalReportAnalysis.Granularity,
        buckets: [MedicalReportAnalysis.Bucket],
        ctx: inout DrawContext, context: UIGraphicsPDFRendererContext
    ) {
        drawSectionTitle("Synthèse statistique", ctx: &ctx)

        // Bandeau de KPIs
        ctx.ensureSpace(70, context: context)
        let kpiY = ctx.y
        let kpiWidth = (ctx.layout.contentWidth - 30) / 4
        let kpis: [(label: String, value: String, color: UIColor)] = [
            ("Total crises", "\(overall.totalCount)", .systemPurple),
            ("Crises / sem.", String(format: "%.1f", overall.crisesPerWeek), .systemRed),
            ("Durée moy.", formatDur(Int(overall.avgDurationSec)), .systemOrange),
            ("Observance", String(format: "%.0f %%", overall.dailyAdherence * 100), .systemGreen)
        ]
        for (i, k) in kpis.enumerated() {
            let x = ctx.layout.margin + CGFloat(i) * (kpiWidth + 10)
            drawKPI(label: k.label, value: k.value, color: k.color,
                    rect: CGRect(x: x, y: kpiY, width: kpiWidth, height: 60))
        }
        ctx.y = kpiY + 70

        // Texte explicatif sur la granularité
        let granText = "Échelle de représentation : \(granularity.label)e (déterminée automatiquement selon la longueur de la période — \(overall.periodDays) jours)."
        drawText(granText, italic: true, ctx: &ctx)
        ctx.y += 4

        // Graphique fréquence
        ctx.ensureSpace(180, context: context)
        let chartFreq = ChartImageRenderer.frequencyChart(
            buckets: buckets, granularity: granularity,
            size: CGSize(width: ctx.layout.contentWidth, height: 160)
        )
        if let img = chartFreq {
            drawCaption("Fréquence des crises", ctx: &ctx)
            img.draw(in: CGRect(x: ctx.layout.margin, y: ctx.y,
                                width: ctx.layout.contentWidth, height: 160))
            ctx.y += 168
        }

        // Graphique intensité
        ctx.ensureSpace(180, context: context)
        let chartInt = ChartImageRenderer.intensityChart(
            buckets: buckets, granularity: granularity,
            size: CGSize(width: ctx.layout.contentWidth, height: 160)
        )
        if let img = chartInt {
            drawCaption("Intensité (durée totale par \(granularity.label))", ctx: &ctx)
            img.draw(in: CGRect(x: ctx.layout.margin, y: ctx.y,
                                width: ctx.layout.contentWidth, height: 160))
            ctx.y += 168
        }

        // Graphique répartition par type
        if !overall.typeBreakdown.isEmpty {
            ctx.ensureSpace(180, context: context)
            let h = max(120, CGFloat(overall.typeBreakdown.count) * 28 + 40)
            let chartTypes = ChartImageRenderer.typeBreakdownChart(
                items: overall.typeBreakdown,
                size: CGSize(width: ctx.layout.contentWidth, height: h)
            )
            if let img = chartTypes {
                drawCaption("Répartition par type de crise", ctx: &ctx)
                img.draw(in: CGRect(x: ctx.layout.margin, y: ctx.y,
                                    width: ctx.layout.contentWidth, height: h))
                ctx.y += h + 8
            }
        }
    }

    private static func drawCorrelationsSection(
        correlations: [MedicalReportAnalysis.Correlation],
        ctx: inout DrawContext, context: UIGraphicsPDFRendererContext
    ) {
        ctx.ensureSpace(120, context: context)
        drawSectionTitle("Étude exploratoire des corrélations", ctx: &ctx)
        drawText("Coefficients de Pearson (r ∈ [-1, +1]) calculés sur les jours où les deux signaux sont renseignés. Force interprétée selon les conventions usuelles : faible (|r|<0,2), modérée (0,2-0,4), forte (>0,4). Ces résultats sont exploratoires et ne démontrent pas de causalité.", italic: true, ctx: &ctx)

        if correlations.isEmpty {
            drawText("Données insuffisantes : il faut au moins 5 jours communs avec un signal renseigné pour calculer une corrélation.", italic: true, ctx: &ctx)
            ctx.y += 8
            return
        }

        let headers = ["Signal", "r", "Force", "Sens", "n"]
        let widths: [CGFloat] = [200, 50, 80, 90, 60]
        let rows: [[String]] = correlations.sorted { abs($0.r) > abs($1.r) }.map { c in
            [
                c.signal,
                String(format: "%.2f", c.r),
                c.strength.label,
                c.direction,
                "\(c.n)"
            ]
        }
        drawTable(headers: headers, columnWidths: widths, rows: rows, ctx: &ctx, context: context)
        ctx.y += 8
    }

    private static func drawMedicationAnalysis(
        analysis: MedicalReportAnalysis.MedicationAnalysis,
        ctx: inout DrawContext, context: UIGraphicsPDFRendererContext
    ) {
        ctx.ensureSpace(100, context: context)
        drawSectionTitle("Analyse du plan médicamenteux", ctx: &ctx)

        if analysis.perMedication.isEmpty {
            drawText("Aucun médicament récurrent à analyser sur la période.", italic: true, ctx: &ctx)
            ctx.y += 8
            return
        }

        let headers = ["Médicament", "Dose", "Horaires", "Adhérence", "Retards (>30 min)", "Oubliés", "Régularité (σ)"]
        let widths: [CGFloat] = [110, 50, 90, 65, 70, 50, 80]
        let rows: [[String]] = analysis.perMedication.map { p in
            let m = p.medication
            let pct = Int((p.adherence * 100).rounded())
            let hours = m.scheduledHours.map(\.formatted).joined(separator: " ")
            let std = formatStdDev(p.timingStdDevSec)
            return [
                m.name,
                m.doseLabel,
                hours.isEmpty ? "—" : hours,
                "\(pct) %",
                "\(p.lateIntakes)",
                "\(p.missedIntakes)",
                std
            ]
        }
        drawTable(headers: headers, columnWidths: widths, rows: rows, ctx: &ctx, context: context)
        ctx.y += 4

        let pct = Int((analysis.weightedAdherence * 100).rounded())
        drawText("Adhérence pondérée tous traitements : \(pct) %. La régularité (σ) mesure la dispersion des décalages horaires entre la prise réelle et l'heure planifiée — plus la valeur est faible, plus les prises sont régulières.", italic: true, ctx: &ctx)
        ctx.y += 8

        // Section dédiée aux prises ponctuelles (à la demande)
        if !analysis.adHocSummary.isEmpty {
            ctx.ensureSpace(80, context: context)
            drawSectionTitle("Prises ponctuelles (à la demande)", ctx: &ctx)
            drawText("Médicaments donnés en dehors du plan régulier (antipyrétiques, anticonvulsifs d'urgence, etc.). Le détail chronologique est en annexe.", italic: true, ctx: &ctx)

            let df = DateFormatter()
            df.locale = Locale(identifier: "fr_FR")
            df.dateFormat = "dd/MM/yyyy HH:mm"

            let adhocHeaders = ["Médicament", "Prises", "Dose cumulée", "Dernière prise", "Raison principale"]
            let adhocWidths: [CGFloat] = [130, 55, 90, 100, 140]
            let adhocRows: [[String]] = analysis.adHocSummary.map { ah in
                let dose = ah.totalDose.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(ah.totalDose)) \(ah.unitLabel)"
                    : String(format: "%.1f \(ah.unitLabel)", ah.totalDose)
                return [
                    ah.name,
                    "\(ah.occurrences)",
                    dose,
                    ah.lastTaken.map { df.string(from: $0) } ?? "—",
                    ah.mostFrequentReason ?? "—"
                ]
            }
            drawTable(headers: adhocHeaders, columnWidths: adhocWidths, rows: adhocRows, ctx: &ctx, context: context)
            ctx.y += 8
        }
    }

    private static func drawSynthesis(
        input: Input, overall: MedicalReportAnalysis.OverallStats,
        correlations: [MedicalReportAnalysis.Correlation],
        medAnalysis: MedicalReportAnalysis.MedicationAnalysis,
        symptomAnalysis: MedicalReportAnalysis.SymptomAnalysis,
        ctx: inout DrawContext, context: UIGraphicsPDFRendererContext
    ) {
        ctx.ensureSpace(80, context: context)
        drawSectionTitle("Synthèse pour le médecin", ctx: &ctx)
        let text = MedicalReportAnalysis.synthesisText(
            overall: overall,
            correlations: correlations,
            medicationAnalysis: medAnalysis,
            symptomAnalysis: symptomAnalysis,
            childFirstName: input.child?.firstName ?? ""
        )
        drawText(text, italic: false, ctx: &ctx)
        ctx.y += 8
    }

    private static func drawSymptomAnalysis(
        analysis: MedicalReportAnalysis.SymptomAnalysis,
        ctx: inout DrawContext, context: UIGraphicsPDFRendererContext
    ) {
        ctx.ensureSpace(80, context: context)
        drawSectionTitle("Symptômes du syndrome de Rett", ctx: &ctx)

        if analysis.totalObservations == 0 {
            drawText("Aucun symptôme spécifique au syndrome de Rett saisi sur la période.", italic: true, ctx: &ctx)
            ctx.y += 8
            return
        }

        drawText("\(analysis.totalObservations) observation\(analysis.totalObservations > 1 ? "s" : "") consolidée\(analysis.totalObservations > 1 ? "s" : "") par type. L'intensité est sur une échelle 1-5 (vide si non renseignée).", italic: true, ctx: &ctx)

        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "dd/MM/yyyy HH:mm"

        let headers = ["Symptôme", "Occurrences", "Intensité moy.", "Durée cumul.", "Dernière obs."]
        let widths: [CGFloat] = [180, 70, 75, 75, 115]
        let rows: [[String]] = analysis.perSymptom.map { p in
            let intensity = p.avgIntensity.map { String(format: "%.1f / 5", $0) } ?? "—"
            let duration = p.totalDurationMinutes > 0 ? "\(p.totalDurationMinutes) min" : "—"
            let last = p.lastObserved.map { df.string(from: $0) } ?? "—"
            return [p.type.label, "\(p.occurrences)", intensity, duration, last]
        }
        drawTable(headers: headers, columnWidths: widths, rows: rows, ctx: &ctx, context: context)
        ctx.y += 8
    }

    private static func drawParentNotes(
        input: Input, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext
    ) {
        ctx.ensureSpace(60, context: context)
        drawSectionTitle("Observations du parent / aidant", ctx: &ctx)
        let text = input.parentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        drawText(text.isEmpty ? "(aucune observation renseignée)" : text, italic: text.isEmpty, ctx: &ctx)
        ctx.y += 12
    }

    private static func drawAnnexHeader(ctx: inout DrawContext) {
        let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        "Annexe — Calendrier détaillé des crises".draw(
            at: CGPoint(x: ctx.layout.margin, y: ctx.y),
            withAttributes: [.font: titleFont, .foregroundColor: UIColor.black]
        )
        ctx.y += titleFont.lineHeight + 8

        let subFont = UIFont.systemFont(ofSize: 10, weight: .regular)
        "Liste chronologique exhaustive des crises sur la période, triées par date.".draw(
            at: CGPoint(x: ctx.layout.margin, y: ctx.y),
            withAttributes: [.font: subFont, .foregroundColor: UIColor.darkGray]
        )
        ctx.y += subFont.lineHeight + 12
    }

    private static func drawSeizureTable(input: Input, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        if input.seizures.isEmpty {
            drawText("Aucune crise enregistrée sur la période.", italic: true, ctx: &ctx)
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
                formatDur(s.durationSeconds),
                s.seizureType.label,
                s.trigger == .none ? "—" : s.trigger.label,
                s.notes
            ]
        }
        drawTable(headers: headers, columnWidths: widths, rows: rows, ctx: &ctx, context: context)
    }

    // MARK: - Footer

    private static func drawPageFooter(context: UIGraphicsPDFRendererContext, layout: Layout, pageNumber: Int) {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMMM yyyy 'à' HH:mm"
        let footerFont = UIFont.systemFont(ofSize: 8, weight: .light)
        let line1 = "RettApp — Rapport généré le \(df.string(from: Date())). Outil de suivi pour aidants — non-dispositif médical (UE 2017/745)."
        let line2 = "Page \(pageNumber)"
        let baseY = layout.pageRect.height - layout.margin - 12
        line1.draw(at: CGPoint(x: layout.margin, y: baseY), withAttributes: [
            .font: footerFont, .foregroundColor: UIColor.darkGray
        ])
        let pageStr = NSAttributedString(string: line2, attributes: [
            .font: footerFont, .foregroundColor: UIColor.darkGray
        ])
        let size = pageStr.size()
        pageStr.draw(at: CGPoint(x: layout.pageRect.width - layout.margin - size.width, y: baseY))
    }

    // MARK: - Drawing primitives

    private static func drawSectionTitle(_ title: String, ctx: inout DrawContext) {
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        title.draw(at: CGPoint(x: ctx.layout.margin, y: ctx.y), withAttributes: [
            .font: font, .foregroundColor: UIColor.black
        ])
        ctx.y += font.lineHeight + 6
    }

    private static func drawCaption(_ text: String, ctx: inout DrawContext) {
        let font = UIFont.systemFont(ofSize: 10, weight: .medium)
        text.draw(at: CGPoint(x: ctx.layout.margin, y: ctx.y), withAttributes: [
            .font: font, .foregroundColor: UIColor.darkGray
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
            width: ctx.layout.contentWidth, height: 600
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.darkGray, .paragraphStyle: para
        ]
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attrs, context: nil
        )
        (text as NSString).draw(in: CGRect(origin: rect.origin, size: bounding.size), withAttributes: attrs)
        ctx.y += bounding.size.height + 4
    }

    private static func drawCallout(_ text: String, ctx: inout DrawContext, context: UIGraphicsPDFRendererContext, color: UIColor, borderColor: UIColor) {
        let font = UIFont.systemFont(ofSize: 9.5, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.black, .paragraphStyle: para
        ]
        let textRect = CGRect(x: ctx.layout.margin + 10, y: 0,
                              width: ctx.layout.contentWidth - 20, height: 400)
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: textRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: attrs, context: nil
        )
        let totalH = bounding.height + 16
        ctx.ensureSpace(totalH, context: context)

        let fullRect = CGRect(x: ctx.layout.margin, y: ctx.y,
                              width: ctx.layout.contentWidth, height: totalH)
        color.setFill()
        UIBezierPath(roundedRect: fullRect, cornerRadius: 6).fill()
        borderColor.setStroke()
        let border = UIBezierPath(roundedRect: fullRect, cornerRadius: 6)
        border.lineWidth = 0.5
        border.stroke()

        (text as NSString).draw(
            in: CGRect(x: ctx.layout.margin + 10, y: ctx.y + 8,
                       width: ctx.layout.contentWidth - 20, height: bounding.height),
            withAttributes: attrs
        )
        ctx.y += totalH
    }

    private static func drawKPI(label: String, value: String, color: UIColor, rect: CGRect) {
        UIColor(white: 0.96, alpha: 1).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        // Bandeau de couleur en haut
        let strip = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 4)
        color.setFill()
        UIBezierPath(rect: strip).fill()

        let valueFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        let labelFont = UIFont.systemFont(ofSize: 9, weight: .regular)
        let para = NSMutableParagraphStyle(); para.alignment = .center

        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont, .foregroundColor: color, .paragraphStyle: para
        ]
        (value as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.minY + 14, width: rect.width, height: 24),
            withAttributes: valueAttrs
        )
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont, .foregroundColor: UIColor.darkGray, .paragraphStyle: para
        ]
        (label as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.minY + 38, width: rect.width, height: 16),
            withAttributes: labelAttrs
        )
    }

    private static func drawKeyValueLines(_ lines: [(String, String)], ctx: inout DrawContext, context: UIGraphicsPDFRendererContext) {
        let labelFont = UIFont.systemFont(ofSize: 10, weight: .medium)
        let valueFont = UIFont.systemFont(ofSize: 10)
        let labelWidth: CGFloat = 200
        for (k, v) in lines {
            ctx.ensureSpace(16, context: context)
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
        headers: [String], columnWidths: [CGFloat], rows: [[String]],
        ctx: inout DrawContext, context: UIGraphicsPDFRendererContext
    ) {
        let headerFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 9)
        let rowHeight: CGFloat = 18
        let headerHeight: CGFloat = 22

        func drawHeaderRow() {
            let totalW = columnWidths.reduce(0, +)
            UIColor(white: 0.92, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: ctx.layout.margin, y: ctx.y, width: totalW, height: headerHeight)).fill()
            var x = ctx.layout.margin
            for (i, h) in headers.enumerated() {
                h.draw(in: CGRect(x: x + 4, y: ctx.y + 5, width: columnWidths[i] - 8, height: headerHeight),
                       withAttributes: [.font: headerFont, .foregroundColor: UIColor.black])
                x += columnWidths[i]
            }
            ctx.y += headerHeight
        }

        ctx.ensureSpace(headerHeight + rowHeight, context: context)
        drawHeaderRow()

        for row in rows {
            ctx.ensureSpace(rowHeight, context: context)
            // si on vient de changer de page, redessine l'en-tête
            if ctx.y < ctx.layout.margin + 30 && ctx.pageNumber > 1 {
                drawHeaderRow()
            }
            let topY = ctx.y
            var x = ctx.layout.margin
            for (i, cell) in row.enumerated() where i < columnWidths.count {
                let truncated = truncateForCell(cell, width: columnWidths[i] - 8, font: cellFont)
                truncated.draw(in: CGRect(x: x + 4, y: ctx.y + 4, width: columnWidths[i] - 8, height: rowHeight),
                               withAttributes: [.font: cellFont, .foregroundColor: UIColor.darkGray])
                x += columnWidths[i]
            }
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
        var t = s
        while t.count > 1 && (t as NSString).appending("…").size(withAttributes: attrs).width > width {
            t.removeLast()
        }
        return t + "…"
    }

    private static func formatDur(_ seconds: Int) -> String {
        if seconds == 0 { return "0 s" }
        let m = seconds / 60
        let s = seconds % 60
        if m == 0 { return "\(s) s" }
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) s"
    }

    private static func formatStdDev(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.0f s", seconds) }
        let m = seconds / 60
        return String(format: "%.0f min", m)
    }
}
