import Foundation

/// Sérialiseur pour les cycles de synchronisation CloudKit. Garantit qu'un
/// seul push/pull est en vol à un instant donné — les autres attendent leur
/// tour dans une file FIFO.
///
/// Pourquoi : sans ça, deux `scheduleSync` rapprochés (par exemple un toggle
/// de prise + un ajout d'observation) déclenchent deux `replicateAll` en
/// parallèle qui écrasent leurs writes mutuellement côté serveur, et deux
/// `pullChanges` qui interfèrent avec `ensureLogsExist` en cours de dedup.
///
/// Design : simple actor avec un booléen d'occupation + une queue de
/// continuations. Pas de priorité — le contrat "premier arrivé, premier servi"
/// suffit pour la charge attendue (max ~2 cycles/seconde).
actor SyncGate {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Attend son tour, exécute `body`, libère la porte. En cas de throw du body,
    /// la porte est libérée quand même (`defer`).
    ///
    /// Signature non-Sendable pour hériter du contexte de l'appelant : les
    /// consommateurs sont `@MainActor` et lire `self.foo` depuis le body ne
    /// doit pas déclencher de hop d'acteur.
    func run<T>(_ body: () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    /// Variante non-throwing (pour les `await gate.perform { ... }` de best-effort).
    func perform<T>(_ body: () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await body()
    }

    private func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
        isBusy = true
    }

    private func release() {
        isBusy = false
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}
