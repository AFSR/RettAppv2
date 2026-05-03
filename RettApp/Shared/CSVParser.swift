import Foundation

/// Parseur CSV tolérant aux deux séparateurs fréquents (`,` et `;` — Excel FR) et
/// au BOM UTF-8. Gère les champs entre guillemets et les guillemets échappés (`""`).
enum CSVParser {

    /// Découpe un contenu CSV en tableau de lignes, chaque ligne étant un tableau de champs.
    static func parse(_ raw: String) -> [[String]] {
        var text = raw
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        guard !text.isEmpty else { return [] }

        let separator = detectSeparator(text)
        let chars = Array(text)

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if insideQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    } else {
                        insideQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    insideQuotes = true
                case separator:
                    row.append(field); field.removeAll()
                case "\r":
                    break
                case "\n":
                    row.append(field); field.removeAll()
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row.removeAll()
                default:
                    field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
        }
        return rows
    }

    /// Parse en dictionnaires avec en-têtes (première ligne).
    static func parseKeyed(_ raw: String) -> [[String: String]] {
        let rows = parse(raw)
        guard let headers = rows.first else { return [] }
        let lower = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return rows.dropFirst().map { row in
            var dict: [String: String] = [:]
            for (i, value) in row.enumerated() where i < lower.count {
                dict[lower[i]] = value.trimmingCharacters(in: .whitespaces)
            }
            return dict
        }
    }

    private static func detectSeparator(_ text: String) -> Character {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let commaCount = firstLine.filter { $0 == "," }.count
        let semiCount = firstLine.filter { $0 == ";" }.count
        return semiCount > commaCount ? ";" : ","
    }

    // MARK: - Export helpers

    static func escape(_ s: String, separator: Character = ",") -> String {
        let needsQuotes = s.contains(separator) || s.contains("\n") || s.contains("\"") || s.contains("\r")
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }

    static func joinLine(_ fields: [String], separator: Character = ",") -> String {
        fields.map { escape($0, separator: separator) }.joined(separator: String(separator))
    }
}

// MARK: - Date parsing

enum CSVDateParser {
    static func parse(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let d = isoFormatter.date(from: trimmed) { return d }
        if let d = isoFractional.date(from: trimmed) { return d }
        for fmt in legacyFormats {
            if let d = fmt.date(from: trimmed) { return d }
        }
        return nil
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let legacyFormats: [DateFormatter] = {
        ["yyyy-MM-dd HH:mm:ss",
         "yyyy-MM-dd'T'HH:mm:ss",
         "yyyy-MM-dd HH:mm",
         "dd/MM/yyyy HH:mm",
         "dd/MM/yyyy HH:mm:ss",
         "yyyy-MM-dd"]
            .map { pattern in
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone.current
                f.dateFormat = pattern
                return f
            }
    }()
}

// MARK: - File output

enum CSVFile {
    /// Écrit un CSV dans un fichier temporaire et retourne son URL. Ajoute le BOM
    /// UTF-8 pour que les ouvertures dans Excel soient proprement décodées.
    static func writeTemp(filename: String, content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(filename)
        let bom = "\u{FEFF}"
        try (bom + content).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
