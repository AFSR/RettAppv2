import XCTest
@testable import RettApp

/// Le client des actualités parle à une API qu'on ne peut pas appeler depuis
/// les tests. Ce qui casse en vrai, ce n'est pas le réseau : c'est l'écart
/// entre la forme réellement renvoyée par Statamic et ce que le décodeur
/// attend. Ces tests figent donc les formes observées dans le blueprint du
/// site, pour qu'un renommage ou un changement de type se voie ici plutôt
/// qu'en production sur un onglet vide.
final class NewsArticleDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> NewsArticle {
        try JSONDecoder().decode(NewsArticle.self, from: Data(json.utf8))
    }

    // MARK: - Handle de collection

    /// RÉGRESSION : le handle valait « actualites », qui est le titre
    /// d'affichage, pas le handle. L'API répondait 404 et la liste restait
    /// vide sans la moindre explication.
    func test_handleDeCollectionEstLeHandleStatamic() {
        XCTAssertEqual(APIConfig.newsCollection, "news")
    }

    // MARK: - Bard avec ensembles

    /// Le champ `content` est un Bard **avec** ensembles : Statamic l'augmente
    /// en tableau de nœuds, pas en chaîne. Décodé comme `String`, tout
    /// l'article échouait.
    func test_contenuBard_tableauDeNoeuds() throws {
        let article = try decode("""
        {
          "id": "abc",
          "title": "Journée mondiale",
          "content": [
            { "type": "text", "text": "<p>Premier paragraphe.</p>" },
            { "type": "set", "values": { "type": "team", "title": "L'équipe" } },
            { "type": "text", "text": "<p>Second paragraphe.</p>" }
          ]
        }
        """)

        XCTAssertTrue(article.content.contains("Premier paragraphe"))
        XCTAssertTrue(article.content.contains("Second paragraphe"))
        XCTAssertFalse(article.content.contains("L'équipe"),
                       "un ensemble structuré n'est pas du HTML : on ne l'injecte pas tel quel")
    }

    /// Un Bard sans ensembles s'augmente en simple chaîne HTML. Les deux
    /// formes doivent passer.
    func test_contenuBard_chaineSimple() throws {
        let article = try decode("""
        { "id": "abc", "title": "T", "content": "<p>Bonjour.</p>" }
        """)
        XCTAssertEqual(article.content, "<p>Bonjour.</p>")
    }

    /// Article fait uniquement d'ensembles : le corps est vide, et c'est le
    /// signal qui fait proposer la page du site dans `NewsDetailView`.
    func test_contenuEntierementStructure_donneUnCorpsVide() throws {
        let article = try decode("""
        {
          "id": "abc", "title": "T",
          "permalink": "https://afsr.fr/actualites/t",
          "content": [ { "type": "set", "values": { "type": "two_columns" } } ]
        }
        """)
        XCTAssertTrue(article.content.isEmpty)
        XCTAssertEqual(article.permalink?.absoluteString, "https://afsr.fr/actualites/t")
    }

    // MARK: - Image principale

    /// Le handle est `featured_picture`, et un champ `assets` s'augmente en
    /// tableau même avec `max_files: 1`.
    func test_imagePrincipale_tableauDAssets() throws {
        let article = try decode("""
        {
          "id": "abc", "title": "T",
          "featured_picture": [ { "url": "/assets/a.jpg", "permalink": "https://afsr.fr/assets/a.jpg" } ]
        }
        """)
        XCTAssertEqual(article.featuredImageURL?.absoluteString, "https://afsr.fr/assets/a.jpg")
    }

    func test_imagePrincipale_absenteNEmpechePasLeDecodage() throws {
        let article = try decode("""
        { "id": "abc", "title": "T" }
        """)
        XCTAssertNil(article.featuredImageURL)
    }

    // MARK: - Résumé

    /// Le blueprint n'a pas de champ chapô : le résumé de la liste est dérivé
    /// du corps, balises retirées.
    func test_resumeDeriveDuCorps_sansBalises() throws {
        let article = try decode("""
        { "id": "abc", "title": "T", "content": "<p>Chaque <strong>année</strong>, le 17 octobre.</p>" }
        """)
        let excerpt = try XCTUnwrap(article.excerpt)
        XCTAssertFalse(excerpt.contains("<"), "le résumé doit être du texte brut")
        XCTAssertTrue(excerpt.contains("Chaque année, le 17 octobre"))
    }

    func test_resumeTronqueAuMot() {
        let long = "<p>" + String(repeating: "mot ", count: 200) + "</p>"
        let excerpt = NewsArticle.plainTextExcerpt(fromHTML: long, limit: 20)
        let unwrapped = excerpt ?? ""
        XCTAssertTrue(unwrapped.hasSuffix("…"))
        XCTAssertLessThanOrEqual(unwrapped.count, 21)
        XCTAssertFalse(unwrapped.contains("mo…"), "on coupe sur un espace, pas au milieu d'un mot")
    }

    // MARK: - Robustesse

    /// Un champ manquant ou d'un type inattendu ne doit jamais faire échouer
    /// toute la liste : une rubrique informative ne casse pas l'app.
    func test_champsInattendusNeFontPasEchouerLeDecodage() throws {
        let article = try decode("""
        { "id": 42, "title": "T", "content": { "inattendu": true }, "date": "2026-10-17 09:30:00" }
        """)
        XCTAssertEqual(article.id, "42")
        XCTAssertTrue(article.content.isEmpty)
        XCTAssertNotNil(article.date, "le format « yyyy-MM-dd HH:mm:ss » de Statamic doit être lu")
    }

    func test_enveloppeStatamic() throws {
        let payload = """
        { "data": [ { "id": "1", "title": "A" }, { "id": "2", "title": "B" } ] }
        """
        let envelope = try JSONDecoder().decode(
            StatamicEnvelope<[NewsArticle]>.self, from: Data(payload.utf8)
        )
        XCTAssertEqual(envelope.data.map(\.title), ["A", "B"])
    }
}
