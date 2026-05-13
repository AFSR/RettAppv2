import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Configuration du suivi

/// Sous-page Réglages → Configuration du suivi.
/// Regroupe Plan médicamenteux, Jeu du Regard, Notifications, Apple Santé.
struct ConfigurationSubView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query private var profiles: [ChildProfile]

    @State private var showMedicationPlan = false
    @State private var notificationsEnabled = false
    @State private var healthKitStatus: HealthKitManager.SimpleAuthStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                Button {
                    showMedicationPlan = true
                } label: {
                    Label("Plan médicamenteux", systemImage: "pills.fill")
                }
            } header: {
                Text("Médicaments")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { notificationsEnabled },
                    set: { newValue in
                        Task {
                            if newValue {
                                let center = UNUserNotificationCenter.current()
                                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                                await MedicationViewModel().rescheduleAllNotifications(
                                    medications: medications,
                                    childFirstName: profiles.first?.firstName ?? ""
                                )
                            } else {
                                await MedicationViewModel().cancelAllNotifications()
                            }
                            await refresh()
                        }
                    }
                )) {
                    Label("Rappels médicaments", systemImage: "bell.badge.fill")
                }
                Button {
                    Task { await sendTestNotification() }
                } label: {
                    Label("Envoyer une notification test", systemImage: "bell")
                }
            } header: {
                Text("Notifications")
            }

            // Section Apple Santé uniquement en mode enfant — la lecture
            // des données Santé n'a de sens que sur l'iPhone de l'enfant.
            // Sur l'iPhone d'un parent, l'app n'utilise pas HealthKit.
            if DeviceRoleStore.shared.role == .child {
                Section {
                    HStack {
                        Label("Apple Santé", systemImage: "heart.fill")
                            .foregroundStyle(.pink)
                        Spacer()
                        Text(healthKitStatusLabel)
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
                    } label: {
                        Label("Ouvrir l'app Santé", systemImage: "arrow.up.forward.app")
                    }
                } header: {
                    Text("Santé")
                } footer: {
                    Text("Choix des types de données et activation depuis Réglages → Données Apple Santé.")
                }
            }
        }
        .navigationTitle("Configuration")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .sheet(isPresented: $showMedicationPlan) {
            NavigationStack { MedicationPlanView() }
        }
    }

    private var healthKitStatusLabel: String {
        switch healthKitStatus {
        case .notDetermined: return "Non demandé"
        case .denied: return "Refusé"
        case .authorized: return "Autorisé"
        case .unavailable: return "Indisponible"
        }
    }

    private func refresh() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        await MainActor.run {
            notificationsEnabled = (settings.authorizationStatus == .authorized
                                    || settings.authorizationStatus == .provisional)
            healthKitStatus = HealthKitManager.shared.authorizationStatus()
        }
    }

    private func sendTestNotification() async {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "RettApp"
        content.body = "Notification de test — tout fonctionne ✅"
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "afsr.test.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        )
        try? await center.add(req)
    }
}

// MARK: - Données

/// Sous-page Réglages → Données.
/// Export CSV, données de démo (générer/supprimer), effacer toutes les données.
struct DataSubView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query(sort: \SeizureEvent.startTime) private var seizures: [SeizureEvent]
    @Query(sort: \MedicationLog.scheduledTime) private var logs: [MedicationLog]

    @State private var showDemoConfirm = false
    @State private var showPurgeDemoConfirm = false
    @State private var showEraseConfirm = false
    @State private var demoSummary: String?
    @State private var exportURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    HistoricalDataImportView()
                } label: {
                    Label("Importer un historique (CSV)", systemImage: "tray.and.arrow.down")
                }
            } footer: {
                Text("Pré-remplit l'app à partir d'un suivi externe (tableur, ancien outil). Modèles CSV téléchargeables pour chaque type de données.")
            }

            Section {
                Button {
                    exportAllCSV()
                } label: {
                    Label("Exporter toutes les données (CSV)", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Exporte vos données en CSV pour les transmettre vous-même à un professionnel de santé via AirDrop, Mail ou Messages.")
            }

            Section {
                Button {
                    showDemoConfirm = true
                } label: {
                    Label("Générer des données de démonstration", systemImage: "wand.and.stars")
                }
                Button(role: .destructive) {
                    showPurgeDemoConfirm = true
                } label: {
                    Label("Supprimer les données de démonstration", systemImage: "wand.and.stars.inverse")
                }
            } footer: {
                Text("Les données de démonstration sont identifiées par le suffixe « (démo) » et la note « Données de démonstration » — elles peuvent être supprimées sans toucher à vos données réelles.")
            }

            Section {
                Button(role: .destructive) {
                    showEraseConfirm = true
                } label: {
                    Label("Effacer toutes les données", systemImage: "trash")
                }
            } footer: {
                Text("Action irréversible : profil, crises, médicaments, prises, humeurs et observations seront supprimés.")
            }
        }
        .navigationTitle("Données")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL { ShareSheet(items: [url]) }
        }
        .confirmationDialog("Effacer toutes les données ?", isPresented: $showEraseConfirm) {
            Button("Effacer", role: .destructive) { eraseAll() }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Cette action supprimera le profil, les crises, les médicaments et les prises. Irréversible.")
        }
        .confirmationDialog("Générer des données de démonstration ?", isPresented: $showDemoConfirm) {
            Button("Générer") { runGenerateDemo() }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Crée 3 mois de crises synthétiques + 2 médicaments de démo + 14 jours de prises. Vos données réelles ne sont pas modifiées.")
        }
        .confirmationDialog("Supprimer les données de démonstration ?", isPresented: $showPurgeDemoConfirm) {
            Button("Supprimer", role: .destructive) { runPurgeDemo() }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Seules les entrées identifiées comme démo seront retirées. Vos données réelles sont conservées.")
        }
        .alert("Données de démonstration", isPresented: Binding(
            get: { demoSummary != nil },
            set: { if !$0 { demoSummary = nil } }
        ), presenting: demoSummary) { _ in
            Button("OK") { demoSummary = nil }
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Helpers (dupliqués depuis SettingsView pour rester self-contained)

    private func runGenerateDemo() {
        let result = DemoDataGenerator.generate(in: modelContext)
        demoSummary = "\(result.seizuresCreated) crises · \(result.medicationsCreated) médicaments · \(result.logsCreated) prises générées."
    }

    private func runPurgeDemo() {
        let count = DemoDataGenerator.purgeDemoData(in: modelContext)
        demoSummary = "\(count) entrée(s) de démonstration supprimée(s)."
    }

    private func eraseAll() {
        for e in seizures { modelContext.delete(e) }
        for l in logs { modelContext.delete(l) }
        for m in medications { modelContext.delete(m) }
        for p in profiles { modelContext.delete(p) }
        try? modelContext.save()
        Task { await MedicationViewModel().cancelAllNotifications() }
    }

    private func exportAllCSV() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rettapp-export-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let isoFormatter = ISO8601DateFormatter()

        var seizureLines = ["id,start,end,duration_seconds,type,trigger,trigger_notes,notes"]
        for e in seizures {
            seizureLines.append([
                e.id.uuidString,
                isoFormatter.string(from: e.startTime),
                isoFormatter.string(from: e.endTime),
                "\(e.durationSeconds)",
                e.seizureType.rawValue,
                e.trigger.rawValue,
                csvEscape(e.triggerNotes),
                csvEscape(e.notes)
            ].joined(separator: ","))
        }
        try? seizureLines.joined(separator: "\n").write(to: dir.appendingPathComponent("crises.csv"), atomically: true, encoding: .utf8)

        var medLines = ["id,name,dose,unit,hours,active,kind"]
        for m in medications {
            medLines.append([
                m.id.uuidString,
                csvEscape(m.name),
                "\(m.doseAmount)",
                m.doseUnit.rawValue,
                m.intakes.map { $0.encode(defaultDose: m.doseAmount) }.joined(separator: "|"),
                m.isActive ? "1" : "0",
                m.kind.rawValue
            ].joined(separator: ","))
        }
        try? medLines.joined(separator: "\n").write(to: dir.appendingPathComponent("medicaments.csv"), atomically: true, encoding: .utf8)

        var logLines = ["id,medication_id,name,scheduled,taken,taken_time,dose,unit,is_adhoc,reason"]
        for l in logs {
            logLines.append([
                l.id.uuidString,
                l.medicationId.uuidString,
                csvEscape(l.medicationName),
                isoFormatter.string(from: l.scheduledTime),
                l.taken ? "1" : "0",
                l.takenTime.map { isoFormatter.string(from: $0) } ?? "",
                "\(l.dose)",
                l.doseUnit.rawValue,
                l.isAdHoc ? "1" : "0",
                csvEscape(l.adhocReason)
            ].joined(separator: ","))
        }
        try? logLines.joined(separator: "\n").write(to: dir.appendingPathComponent("prises.csv"), atomically: true, encoding: .utf8)

        exportURL = dir
        showShareSheet = true
    }

    private func csvEscape(_ s: String) -> String {
        let needsQuotes = s.contains(",") || s.contains("\n") || s.contains("\"")
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }
}

// MARK: - Avertissement médical (page complète)

struct MedicalDisclaimerSubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.afsrWarning)
                    Text("RettApp n'est pas un dispositif médical")
                        .font(AFSRFont.title(20))
                }
                Text("Cette application est un outil de suivi destiné aux parents et aidants d'enfants atteints du syndrome de Rett. Elle ne constitue pas un dispositif médical au sens du règlement européen 2017/745 (MDR) et ne dispose d'aucun marquage CE médical, FDA, ou UKCA.")
                    .font(AFSRFont.body())
                    .fixedSize(horizontal: false, vertical: true)

                Text("Limites d'utilisation")
                    .font(AFSRFont.headline(16))
                    .padding(.top, 8)
                disclaimerRow(icon: "stethoscope", text: "Ne diagnostique pas, ne traite pas, ne recommande aucune dose ni traitement.")
                disclaimerRow(icon: "doc.text.below.ecg", text: "Les analyses statistiques (corrélations, tendances) sont fournies à titre exploratoire et n'établissent pas de causalité médicale.")
                disclaimerRow(icon: "person.crop.circle.badge.checkmark", text: "Ne remplace pas l'avis, le diagnostic ou le traitement délivré par un professionnel de santé.")

                Text("En cas d'urgence")
                    .font(AFSRFont.headline(16))
                    .padding(.top, 8)
                HStack(spacing: 16) {
                    EmergencyBadge(label: "Samu", number: "15")
                    EmergencyBadge(label: "Secours européen", number: "112")
                }

                Text("RGPD et confidentialité")
                    .font(AFSRFont.headline(16))
                    .padding(.top, 8)
                Text("Toutes les données saisies dans RettApp restent stockées localement sur votre appareil. Aucune donnée n'est transmise à l'AFSR ou à un tiers. L'usage de l'application est soumis à votre consentement parental et à notre politique de confidentialité.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)

                Link("Lire la politique de confidentialité",
                     destination: URL(string: "https://rettapp.afsr.fr/confidentialite.html")!)
                    .font(AFSRFont.body())
                    .padding(.top, 4)

                Spacer(minLength: 24)
            }
            .padding()
        }
        .background(Color.afsrBackground.ignoresSafeArea())
        .navigationTitle("Avertissement médical")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func disclaimerRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.afsrPurpleAdaptive)
                .frame(width: 24)
            Text(text)
                .font(AFSRFont.body(15))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EmergencyBadge: View {
    let label: String
    let number: String
    var body: some View {
        VStack(spacing: 4) {
            Text(number)
                .font(AFSRFont.title(28))
                .foregroundStyle(.afsrEmergency)
            Text(label)
                .font(AFSRFont.caption())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.afsrEmergency.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - À propos (page complète)

struct AboutSubView: View {
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Version de l'application")
                    Spacer()
                    Text(appVersion).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Section("Liens AFSR") {
                Link(destination: URL(string: "https://afsr.fr")!) {
                    Label("Site officiel", systemImage: "safari")
                }
                Link(destination: URL(string: "https://afsr.fr/nous-soutenir/faire-un-don")!) {
                    Label("Faire un don", systemImage: "heart.fill")
                }
            }
            Section("Documents légaux") {
                Link(destination: URL(string: "https://rettapp.afsr.fr/mentions-legales.html")!) {
                    Label("Mentions légales", systemImage: "doc.text")
                }
                Link(destination: URL(string: "https://rettapp.afsr.fr/confidentialite.html")!) {
                    Label("Politique de confidentialité", systemImage: "lock.shield")
                }
            }
            Section("Crédits") {
                Text("RettApp est une application de l'Association Française du Syndrome de Rett (AFSR), association loi 1901 reconnue d'intérêt général.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }
}
