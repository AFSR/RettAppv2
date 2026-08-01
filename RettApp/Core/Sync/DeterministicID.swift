import Foundation
import CryptoKit

/// Génère des UUID **déterministes** (style UUID v5) à partir d'un contenu.
///
/// Pourquoi : dans une app synchronisée multi-appareil, tout enregistrement
/// susceptible d'être créé indépendamment sur deux appareils à partir de la
/// même source (prise planifiée générée par le plan, ligne d'un CSV importé
/// des deux côtés, donnée de démo) DOIT porter le même UUID partout — sinon
/// CloudKit voit deux records distincts et l'utilisateur des doublons.
///
/// Deux appels avec le même namespace et les mêmes parts produisent toujours
/// le même UUID, sur n'importe quel appareil.
enum DeterministicID {
    static func uuid(namespace: String, _ parts: String...) -> UUID {
        let seed = ([namespace] + parts).joined(separator: "|")
        var digest = Array(Insecure.MD5.hash(data: Data(seed.utf8)))
        // Version 5 (name-based), variante RFC 4122.
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        let bytes: uuid_t = (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        )
        return UUID(uuid: bytes)
    }
}
