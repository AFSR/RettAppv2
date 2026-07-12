import Foundation
import CloudKit
import os.log

/// Wrapper autour d'une opération CloudKit qui retry avec back-off exponentiel
/// pour les erreurs transitoires connues d'Apple (`.requestRateLimited`,
/// `.zoneBusy`, `.networkUnavailable`, `.networkFailure`, `.serviceUnavailable`).
///
/// - Respecte `CKErrorRetryAfterKey` quand le serveur le fournit (obligation
///   Apple : ignorer ce hint peut faire escalader le rate-limit et bannir
///   temporairement le device).
/// - Ne retry PAS les erreurs terminales (`.notAuthenticated`, `.permissionFailure`,
///   `.quotaExceeded`, `.constraintViolation` …) — les remonter immédiatement à
///   l'UI est plus utile qu'un retry qui reboucle.
/// - Cap dur à `maxAttempts` (5 par défaut) pour ne pas geler l'app sur une
///   panne longue durée.
enum CKRetry {
    private static let log = Logger(subsystem: "fr.afsr.RettApp", category: "CKRetry")

    /// Exécute `operation` en la retentant jusqu'à `maxAttempts` fois, avec
    /// back-off exponentiel + jitter plafonné à 30 s. La dernière erreur est propagée.
    ///
    /// Le jitter (±25 %) évite le thundering-herd : quand deux devices d'un
    /// même utilisateur se prennent le même rate-limit CloudKit, ils
    /// retentent à des instants différents.
    static func run<T>(
        maxAttempts: Int = 5,
        baseDelaySeconds: Double = 1.0,
        label: String = "op",
        _ operation: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var delay = baseDelaySeconds
        while true {
            attempt += 1
            do {
                return try await operation()
            } catch let error {
                let (retryable, hint) = classify(error)
                guard retryable, attempt < maxAttempts else {
                    if attempt >= maxAttempts {
                        log.error("[\(label)] fail after \(attempt) attempts : \(error.localizedDescription)")
                    }
                    throw error
                }
                let base = hint ?? delay
                // Jitter uniforme dans [0.75x, 1.25x] du délai calculé.
                let jitter = 1.0 + (Double.random(in: -0.25...0.25))
                let waitSeconds = base * jitter
                log.info("[\(label)] retryable error, attempt \(attempt)/\(maxAttempts), retry in \(String(format: "%.1f", waitSeconds))s : \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                // Back-off exponentiel plafonné à 30s pour la prochaine itération.
                delay = min(delay * 2, 30)
            }
        }
    }

    /// Retourne `(retryable, retryAfterHint)`. Le hint est nil si le serveur
    /// n'a pas fourni de `retryAfter` — l'appelant utilise alors son back-off.
    static func classify(_ error: Error) -> (retryable: Bool, retryAfter: Double?) {
        guard let ck = error as? CKError else {
            // URLError transitoires (offline, timeout DNS) : idem, retryable.
            if let ue = error as? URLError {
                switch ue.code {
                case .notConnectedToInternet, .networkConnectionLost,
                     .timedOut, .dnsLookupFailed, .cannotFindHost,
                     .cannotConnectToHost, .resourceUnavailable:
                    return (true, nil)
                default:
                    return (false, nil)
                }
            }
            return (false, nil)
        }
        let hint = ck.userInfo[CKErrorRetryAfterKey] as? Double
        switch ck.code {
        case .requestRateLimited,
             .zoneBusy,
             .serverResponseLost,
             .serviceUnavailable,
             .networkUnavailable,
             .networkFailure:
            return (true, hint)
        default:
            return (false, hint)
        }
    }

    /// Certaines erreurs sont fatales pour un cycle mais NE justifient PAS
    /// d'alerter l'utilisateur (ex. `.unknownItem` sur une subscription qu'on
    /// vient de vouloir lire). Cette classification est utile côté UI banner.
    static func isBenign(_ error: Error) -> Bool {
        guard let ck = error as? CKError else { return false }
        switch ck.code {
        case .unknownItem, .partialFailure:
            return true
        default:
            return false
        }
    }
}
