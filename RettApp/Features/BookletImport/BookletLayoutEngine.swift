import CoreGraphics
import Foundation

/// Calcule la position de chaque case à cocher du cahier de suivi en
/// coordonnées PDF (système A4 portrait : origine en haut à gauche, unité = pt).
///
/// **Algorithme partagé** entre le générateur PDF (qui dessine les cases) et
/// le scanner (qui les échantillonne). Tant que les deux côtés appellent les
/// mêmes méthodes avec le même `BookletSchema`, ils retombent sur les mêmes
/// coordonnées exactement.
///
/// La sortie est une liste de `Cell` avec section + indices logiques + centre.
enum BookletLayoutEngine {

    // Constantes alignées sur FollowUpBookletGenerator
    static let pageWidth: CGFloat = 595
    static let pageHeight: CGFloat = 842
    static let margin: CGFloat = 24
    static let footerReserve: CGFloat = 18

    // Position fixe du QR (haut-droite)
    static let qrSize: CGFloat = 60
    static var qrOrigin: CGPoint {
        CGPoint(x: pageWidth - margin - qrSize, y: margin)
    }

    /// Position y où commence le contenu (sections), juste après le bloc
    /// header (QR + bandeau date + trait séparateur). Doit être identique au
    /// générateur : après drawHeader, y = margin + qrSize + 4 (pour la ligne)
    /// + 6 (espacement final) = margin + qrSize + 10.
    static var contentStartY: CGFloat {
        margin + qrSize + 10
    }

    /// Cellule générique : une case à cocher dans le cahier.
    struct Cell: Equatable, Hashable {
        let section: BookletSchema.Section
        let rowIndex: Int        // index dans la section (0-based)
        let dayIndex: Int        // 0 = lundi, 6 = dimanche
        let optionIndex: Int     // 0 pour case binaire ; 0..N pour multi-option
        let half: HalfDay?       // matin/après-midi pour les symptômes Rett
        let center: CGPoint      // en coordonnées PDF (pt)

        enum HalfDay: String, Equatable, Hashable {
            case morning, afternoon
        }
    }

    /// Hauteur de ligne adaptative — copie 1:1 du calcul du générateur.
    /// Utilisée pour reproduire les mêmes positions au scan.
    static func rowHeight(for schema: BookletSchema) -> CGFloat {
        let medRows = schema.meds.count
        let seizureRows = SeizureType.allCases.count
        let moodRows = 5
        let mealsRows = schema.mealSlots.count + 1  // + hydration row
        let sleepRows = 5
        let symptomRows = schema.symptoms.count
        let eventsRows = 6

        let included = schema.includedSections
        let sectionOverhead: CGFloat = 32
        var fixedOverhead: CGFloat = 0
        if included.contains(.medication) && medRows > 0 { fixedOverhead += sectionOverhead }
        if included.contains(.seizure) { fixedOverhead += sectionOverhead }
        if included.contains(.mood) { fixedOverhead += sectionOverhead }
        if included.contains(.meals) && mealsRows > 1 { fixedOverhead += sectionOverhead }
        if included.contains(.sleep) { fixedOverhead += sectionOverhead }
        if included.contains(.symptoms) && symptomRows > 0 { fixedOverhead += sectionOverhead + 10 }
        if included.contains(.events) { fixedOverhead += sectionOverhead }

        let totalRows = (included.contains(.medication) ? medRows : 0)
            + (included.contains(.seizure) ? seizureRows : 0)
            + (included.contains(.mood) ? moodRows : 0)
            + (included.contains(.meals) ? mealsRows : 0)
            + (included.contains(.sleep) ? sleepRows : 0)
            + (included.contains(.symptoms) ? symptomRows : 0)
            + (included.contains(.events) ? eventsRows : 0)

        // y disponible = hauteur totale − contenu déjà occupé par le header
        // (QR + date + trait) − réserve footer. Doit être strictement
        // identique au générateur, sinon les hauteurs de ligne ne matchent pas.
        let availableHeight = pageHeight - contentStartY - footerReserve
        let rowSpace = max(0, availableHeight - fixedOverhead)
        guard totalRows > 0 else { return 14 }
        let raw = rowSpace / CGFloat(totalRows)
        return max(11, min(16, raw))
    }

    /// Calcule toutes les cellules cliquables du cahier.
    /// Le `yOffset` initial doit correspondre à la position de départ du
    /// générateur (après le header).
    static func cells(for schema: BookletSchema) -> [Cell] {
        var cells: [Cell] = []
        let rowH = rowHeight(for: schema)
        var y = contentStartY  // après le header (QR + date + trait)

        let included = schema.includedSections

        // ── Médicaments : 1 case binaire par jour
        if included.contains(.medication), !schema.meds.isEmpty {
            y += sectionTitleHeight + headerRowHeight
            cells.append(contentsOf: singleCheckCells(
                section: .medication, rowCount: schema.meds.count,
                schema: schema, leftColumnWidth: 220, rowHeight: rowH, yStart: &y
            ))
            y += sectionGap
        }

        // ── Crises : 4 options par jour, par type de crise
        if included.contains(.seizure) {
            y += sectionTitleHeight + dayHeaderHeight + codeHeaderHeight
            cells.append(contentsOf: multiCheckCells(
                section: .seizure, rowCount: SeizureType.allCases.count,
                optionCount: 4,  // 0/1/2-3/4+
                schema: schema, leftColumnWidth: 180, rowHeight: rowH, yStart: &y
            ))
            y += sectionGap
        }

        // ── Humeur : 1 case binaire par jour, 5 niveaux d'humeur (rows)
        if included.contains(.mood) {
            y += sectionTitleHeight + headerRowHeight
            cells.append(contentsOf: singleCheckCells(
                section: .mood, rowCount: 5,
                schema: schema, leftColumnWidth: 180, rowHeight: rowH, yStart: &y
            ))
            y += sectionGap
        }

        // ── Repas : 5 options par jour (R/P/M/B/T) × N rows (slots)
        if included.contains(.meals), !schema.mealSlots.isEmpty {
            y += sectionTitleHeight + dayHeaderHeight + codeHeaderHeight
            cells.append(contentsOf: multiCheckCells(
                section: .meals, rowCount: schema.mealSlots.count,
                optionCount: 5,
                schema: schema, leftColumnWidth: 150, rowHeight: rowH, yStart: &y
            ))
            y += sectionGap
            // Hydratation : 4 options, 1 ligne
            y += sectionTitleHeight + dayHeaderHeight + codeHeaderHeight
            cells.append(contentsOf: multiCheckCells(
                section: .hydration, rowCount: 1,
                optionCount: 4,  // F/M/B/E
                schema: schema, leftColumnWidth: 150, rowHeight: rowH, yStart: &y
            ))
            y += sectionGap
        }

        // ── Sommeil : 5 sous-grilles (durée nuit, qualité, sieste matin, sieste aprem, réveils)
        if included.contains(.sleep) {
            y += sectionTitleHeight  // titre global "Sommeil"
            // Chaque sous-ligne du sommeil a son propre nb d'options
            let sleepRows: [(rowIdx: Int, options: Int)] = [
                (0, 4), // Sommeil de nuit (h) — 4 options
                (1, 3), // Qualité — 3 options
                (2, 4), // Sieste matin — 4 options
                (3, 4), // Sieste après-midi — 4 options
                (4, 3)  // Réveils nocturnes — 3 options
            ]
            for sub in sleepRows {
                y += dayHeaderHeight + codeHeaderHeight
                cells.append(contentsOf: multiCheckCells(
                    section: .sleep, rowCount: 1,
                    optionCount: sub.options,
                    schema: schema, leftColumnWidth: 220, rowHeight: rowH, yStart: &y,
                    rowIndexOffset: sub.rowIdx
                ))
                y += sectionGap
            }
        }

        // ── Symptômes Rett : 2 cases (M/A) par jour
        // Note : le bandeau jour des symptômes fait 12 pt (pas 11 comme les
        // autres multi-options) — c'est la valeur du générateur.
        if included.contains(.symptoms), !schema.symptoms.isEmpty {
            y += sectionTitleAdvance + symptomDayHeaderHeight + symptomHalfHeaderHeight
            cells.append(contentsOf: symptomCells(
                schema: schema, rowHeight: rowH, yStart: &y
            ))
            y += sectionGap
        }

        // ── Événements particuliers : 1 case binaire par jour, 6 catégories
        if included.contains(.events) {
            y += sectionTitleHeight + headerRowHeight
            cells.append(contentsOf: singleCheckCells(
                section: .events, rowCount: 6,
                schema: schema, leftColumnWidth: 220, rowHeight: rowH, yStart: &y
            ))
        }

        return cells
    }

    // MARK: - Constantes de layout (source unique partagée avec le générateur)
    //
    // CRITIQUE : ces constantes doivent être strictement identiques aux
    // valeurs utilisées par FollowUpBookletGenerator pour que le sampler
    // tombe exactement sur les cases dessinées. Les hauteurs sont des
    // **forfaits fixes** — pas de calculs basés sur UIFont.lineHeight, qui
    // varient au runtime selon le système et provoquent des dérives de
    // ~0.5 pt par titre × N sections = plusieurs points cumulés.

    /// Avance verticale après le titre d'une section (forfait, ≥ lineHeight de
    /// SF Pro 9.5 semibold ~11.5 + marge de respiration).
    static let sectionTitleAdvance: CGFloat = 13

    /// Hauteur du bandeau jour pour les grilles à case unique
    /// (médication / humeur / événements).
    static let singleCheckHeaderHeight: CGFloat = 12

    /// Hauteur du bandeau jour pour les grilles multi-options
    /// (crises / repas / hydratation / sommeil).
    static let multiDayHeaderHeight: CGFloat = 11

    /// Hauteur du bandeau de codes-options sous le bandeau jour
    /// (R/P/M/B/T pour repas, 0/1/2-3/4+ pour crises, etc.).
    static let multiCodeHeaderHeight: CGFloat = 9

    /// Hauteur du bandeau jour pour les symptômes Rett (différent du
    /// multi-options : 12 pt au lieu de 11 dans le générateur).
    static let symptomDayHeaderHeight: CGFloat = 12

    /// Hauteur du bandeau Matin/Après-midi sous les jours (symptômes).
    static let symptomHalfHeaderHeight: CGFloat = 10

    /// Espacement vertical après chaque grille avant la section suivante.
    static let sectionGap: CGFloat = 4

    // Alias pour rétrocompat / lisibilité — utilisés dans cells(for:).
    private static var sectionTitleHeight: CGFloat { sectionTitleAdvance }
    private static var headerRowHeight: CGFloat { singleCheckHeaderHeight }
    private static var dayHeaderHeight: CGFloat { multiDayHeaderHeight }
    private static var codeHeaderHeight: CGFloat { multiCodeHeaderHeight }
    private static var halfDayHeaderHeight: CGFloat { symptomHalfHeaderHeight }

    // MARK: - Générateurs de cellules par type de grille

    private static func singleCheckCells(
        section: BookletSchema.Section,
        rowCount: Int,
        schema: BookletSchema,
        leftColumnWidth: CGFloat,
        rowHeight: CGFloat,
        yStart: inout CGFloat
    ) -> [Cell] {
        var out: [Cell] = []
        let totalWidth = pageWidth - 2 * margin
        let dayColumnWidth = (totalWidth - leftColumnWidth) / CGFloat(schema.days)
        for r in 0..<rowCount {
            for d in 0..<schema.days {
                let centerX = margin + leftColumnWidth + (CGFloat(d) + 0.5) * dayColumnWidth
                let centerY = yStart + (CGFloat(r) + 0.5) * rowHeight
                out.append(Cell(section: section, rowIndex: r, dayIndex: d,
                                optionIndex: 0, half: nil,
                                center: CGPoint(x: centerX, y: centerY)))
            }
        }
        yStart += rowHeight * CGFloat(rowCount)
        return out
    }

    private static func multiCheckCells(
        section: BookletSchema.Section,
        rowCount: Int, optionCount: Int,
        schema: BookletSchema,
        leftColumnWidth: CGFloat,
        rowHeight: CGFloat,
        yStart: inout CGFloat,
        rowIndexOffset: Int = 0
    ) -> [Cell] {
        var out: [Cell] = []
        let totalWidth = pageWidth - 2 * margin
        let dayColumnWidth = (totalWidth - leftColumnWidth) / CGFloat(schema.days)
        let optionWidth = dayColumnWidth / CGFloat(optionCount)
        for r in 0..<rowCount {
            for d in 0..<schema.days {
                for o in 0..<optionCount {
                    let centerX = margin + leftColumnWidth
                        + CGFloat(d) * dayColumnWidth
                        + (CGFloat(o) + 0.5) * optionWidth
                    let centerY = yStart + (CGFloat(r) + 0.5) * rowHeight
                    out.append(Cell(section: section, rowIndex: r + rowIndexOffset,
                                    dayIndex: d, optionIndex: o, half: nil,
                                    center: CGPoint(x: centerX, y: centerY)))
                }
            }
        }
        yStart += rowHeight * CGFloat(rowCount)
        return out
    }

    private static func symptomCells(
        schema: BookletSchema, rowHeight: CGFloat,
        yStart: inout CGFloat
    ) -> [Cell] {
        var out: [Cell] = []
        let totalWidth = pageWidth - 2 * margin
        let leftColumnWidth: CGFloat = 170
        let halfDayWidth = (totalWidth - leftColumnWidth) / CGFloat(schema.days * 2)
        for (r, _) in schema.symptoms.enumerated() {
            for d in 0..<schema.days {
                let xM = margin + leftColumnWidth + CGFloat(d * 2) * halfDayWidth + halfDayWidth / 2
                let xA = xM + halfDayWidth
                let centerY = yStart + (CGFloat(r) + 0.5) * rowHeight
                out.append(Cell(section: .symptoms, rowIndex: r, dayIndex: d,
                                optionIndex: 0, half: .morning,
                                center: CGPoint(x: xM, y: centerY)))
                out.append(Cell(section: .symptoms, rowIndex: r, dayIndex: d,
                                optionIndex: 0, half: .afternoon,
                                center: CGPoint(x: xA, y: centerY)))
            }
        }
        yStart += rowHeight * CGFloat(schema.symptoms.count)
        return out
    }
}
