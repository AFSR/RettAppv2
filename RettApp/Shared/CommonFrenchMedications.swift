import Foundation

/// Liste de médicaments fréquemment prescrits en France (focus pédiatrie + neurologie),
/// utilisée pour l'autocomplétion lors de la saisie d'une prise ponctuelle.
///
/// Cette liste n'est ni exhaustive ni limitative — l'utilisateur peut toujours saisir
/// un nom libre. Elle ne couvre que les noms commerciaux (DCI principale entre parenthèses
/// pour info). Source : VIDAL + ANSM répertoires courants.
enum CommonFrenchMedications {

    static let names: [String] = [
        // Antiépileptiques
        "Keppra (lévétiracétam)",
        "Dépakine (valproate)",
        "Dépakine Chrono",
        "Micropakine",
        "Lamictal (lamotrigine)",
        "Rivotril (clonazépam)",
        "Urbanyl (clobazam)",
        "Valium (diazépam)",
        "Tegretol (carbamazépine)",
        "Topamax (topiramate)",
        "Sabril (vigabatrine)",
        "Diacomit (stiripentol)",
        "Ospolot (sulthiame)",
        "Trileptal (oxcarbazépine)",
        "Zonegran (zonisamide)",
        "Briviact (brivaracétam)",
        "Vimpat (lacosamide)",
        "Inovelon (rufinamide)",
        "Frisium (clobazam)",
        "Buccolam (midazolam)",

        // Antipyrétiques / antalgiques
        "Doliprane (paracétamol)",
        "Efferalgan (paracétamol)",
        "Dafalgan (paracétamol)",
        "Advil (ibuprofène)",
        "Nurofen (ibuprofène)",

        // Sommeil
        "Slényto (mélatonine)",
        "Circadin (mélatonine)",

        // Respiratoire
        "Ventoline (salbutamol)",
        "Pulmicort (budésonide)",
        "Atrovent (ipratropium)",

        // Cortico
        "Solupred (prednisolone)",
        "Célestène (bétaméthasone)",

        // Antibiotiques pédiatriques
        "Amoxicilline",
        "Augmentin (amoxicilline + acide clavulanique)",
        "Clamoxyl (amoxicilline)",
        "Josacine (josamycine)",
        "Zithromax (azithromycine)",

        // Digestif / probiotique
        "Smecta (diosmectite)",
        "Motilium (dompéridone)",
        "Tiorfan (racécadotril)",
        "Inexium (ésoméprazole)",
        "Mopral (oméprazole)",
        "Lactibiane",
        "Ultra-Levure (saccharomyces boulardii)",

        // Allergie
        "Aerius (desloratadine)",
        "Zyrtec (cétirizine)",

        // Constipation
        "Forlax (macrogol)",
        "Movicol (macrogol)",
        "Eductyl",

        // Vitamines / suppléments
        "Zymad (vitamine D)",
        "Uvedose (vitamine D)",

        // Autres pédiatriques fréquents
        "Maxilase (alpha-amylase)",
        "Toplexil (oxomémazine)",
        "Polery (codéine)"
    ]

    /// Filtre la liste selon une saisie utilisateur. Retourne au plus `limit` suggestions.
    /// Insensible à la casse et aux accents.
    static func suggestions(matching query: String, limit: Int = 8) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let folded = trimmed.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        return names.filter { name in
            let f = name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return f.contains(folded)
        }
        .prefix(limit)
        .map { $0 }
    }
}
