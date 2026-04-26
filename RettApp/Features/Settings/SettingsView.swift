import SwiftUI
import SwiftData
import UserNotifications
import HealthKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query(sort: \SeizureEvent.startTime) private var seizures: [SeizureEvent]
    @Query(sort: \MedicationLog.scheduledTime) private var logs: [MedicationLog]

    @State private var notificationsEnabled: Bool = false
    @State private var healthKitStatus: HealthKitManager.SimpleAuthStatus = .notDetermined
    @State private var showChildEditor = false
    @State private var showMedicationPlan = false
    @State private var showEraseConfirm = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        List {
            childSection
            medicationsSection
            eyeGameSection
            healthSection
            notificationsSection
            dataSection
            medicalDisclaimerSection
            aboutSection
            accountSection
        }
        .navigationTitle("Réglages")
        .task { await refreshAuthorizations() }
        .sheet(isPresented: $showChildEditor) {
            if let profile = profiles.first {
                NavigationStack { ChildProfileEditor(profile: profile) }
            }
        }
        .sheet(isPresented: $showMedicationPlan) {
            NavigationStack { MedicationPlanView() }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL { ShareSheet(items: [url]) }
        }
        .confirmationDialog("Effacer toutes les données ?", isPresented: $showEraseConfirm) {
            Button("Effacer", role: .destructive) { eraseAll() }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Cette action supprimera le profil, les crises, les médicaments et les prises. Irréversible.")
        }
    }

    // MARK: - Sections

    private var childSection: some View {
        Section("Profil") {
            if let profile = profiles.first {
                Button { showChildEditor = true } label: {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.afsrPurple)
                        VStack(alignment: .leading) {
                            Text(profile.firstName).font(AFSRFont.headline(17)).foregroundStyle(.primary)
                            if let age = profile.ageYears {
                                Text("\(age) ans").font(AFSRFont.caption()).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var medicationsSection: some View {
        Section("Médicaments") {
            Button { showMedicationPlan = true } label: {
                Label("Plan médicamenteux", systemImage: "pills.fill")
            }
        }
    }

    private var eyeGameSection: some View {
        EyeGameSettingsSection()
    }

    private var healthSection: some View {
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
                Label("Gérer les permissions", systemImage: "gear")
            }
        } header: {
            Text("Santé")
        } footer: {
            Text("Toutes les données (crises, médicaments, prises) sont stockées localement sur l'appareil. L'API publique HealthKit n'expose pas encore de type pour les crises d'épilepsie — utilisez l'export CSV pour partager les données avec un professionnel de santé.")
        }
    }

    private var notificationsSection: some View {
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
                        await refreshAuthorizations()
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
    }

    private var dataSection: some View {
        Section("Données") {
            Button {
                exportAllCSV()
            } label: {
                Label("Exporter toutes les données (CSV)", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                showEraseConfirm = true
            } label: {
                Label("Effacer les données de l'application", systemImage: "trash")
            }
        }
    }

    private var medicalDisclaimerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.afsrWarning)
                VStack(alignment: .leading, spacing: 6) {
                    Text("RettApp n'est pas un dispositif médical")
                        .font(AFSRFont.headline(15))
                    Text("Cette application est un outil de suivi destiné aux parents et aidants. Elle ne constitue pas un dispositif médical au sens du règlement européen 2017/745 (MDR) et ne remplace en aucun cas un avis, un diagnostic ou un traitement médical délivré par un professionnel de santé. En cas d'urgence, contactez le 15 ou le 112.")
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Avertissement médical")
        }
    }

    private var aboutSection: some View {
        Section("À propos") {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion).foregroundStyle(.secondary)
            }
            Link(destination: URL(string: "https://www.afsr.fr")!) {
                Label("Site de l'AFSR", systemImage: "safari")
            }
            Link(destination: URL(string: "https://www.afsr.fr/mentions-legales")!) {
                Label("Mentions légales", systemImage: "doc.text")
            }
            Link(destination: URL(string: "https://www.afsr.fr/confidentialite")!) {
                Label("Politique de confidentialité", systemImage: "lock.shield")
            }
        }
    }

    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                authManager.signOut()
            } label: {
                Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } footer: {
            Text("Vos données locales ne sont pas supprimées à la déconnexion.")
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var healthKitStatusLabel: String {
        switch healthKitStatus {
        case .notDetermined: return "Non demandé"
        case .denied: return "Refusé"
        case .authorized: return "Autorisé"
        case .unavailable: return "Indisponible"
        }
    }

    private func refreshAuthorizations() async {
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
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "RettApp"
        content.body = "Notification de test — tout fonctionne ✅"
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "afsr.test.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        try? await center.add(req)
    }

    // MARK: - Export / Erase

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

        var medLines = ["id,name,dose,unit,hours,active"]
        for m in medications {
            medLines.append([
                m.id.uuidString,
                csvEscape(m.name),
                "\(m.doseAmount)",
                m.doseUnit.rawValue,
                m.scheduledHours.map(\.formatted).joined(separator: "|"),
                m.isActive ? "1" : "0"
            ].joined(separator: ","))
        }
        try? medLines.joined(separator: "\n").write(to: dir.appendingPathComponent("medicaments.csv"), atomically: true, encoding: .utf8)

        var logLines = ["id,medication_id,name,scheduled,taken,taken_time,dose,unit"]
        for l in logs {
            logLines.append([
                l.id.uuidString,
                l.medicationId.uuidString,
                csvEscape(l.medicationName),
                isoFormatter.string(from: l.scheduledTime),
                l.taken ? "1" : "0",
                l.takenTime.map { isoFormatter.string(from: $0) } ?? "",
                "\(l.dose)",
                l.doseUnit.rawValue
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

    private func eraseAll() {
        for e in seizures { modelContext.delete(e) }
        for l in logs { modelContext.delete(l) }
        for m in medications { modelContext.delete(m) }
        for p in profiles { modelContext.delete(p) }
        try? modelContext.save()
        Task { await MedicationViewModel().cancelAllNotifications() }
    }
}

// MARK: - Child profile editor

struct ChildProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var profile: ChildProfile

    @State private var hasBirthDate: Bool = false
    @State private var birthDate: Date = Date()

    var body: some View {
        Form {
            Section("Prénom") {
                TextField("Prénom", text: $profile.firstName)
            }
            Section {
                Toggle("Date de naissance", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker("Née le", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                }
            }
            Section {
                Toggle(isOn: $profile.hasEpilepsy) {
                    Label("Épilepsie", systemImage: "waveform.path.ecg")
                }
            } footer: {
                Text("Désactiver masque l'onglet de suivi des crises.")
            }
        }
        .navigationTitle("Profil de l'enfant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") {
                    profile.birthDate = hasBirthDate ? birthDate : nil
                    dismiss()
                }
            }
        }
        .onAppear {
            if let existing = profile.birthDate {
                hasBirthDate = true
                birthDate = existing
            }
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .modelContainer(PreviewData.container)
        .environment(AuthManager.previewSignedIn())
}
