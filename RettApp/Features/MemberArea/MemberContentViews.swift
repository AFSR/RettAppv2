import SwiftUI

// MARK: - Publications

struct MemberPublicationsView: View {
    let session: MemberSession
    @State private var opener = MemberDocumentOpener()

    var body: some View {
        MemberResourceView<PublicationsResponse, PublicationsContent>(session: session, path: "/publications") { response, reload in
            PublicationsContent(session: session, opener: opener, response: response, reload: reload)
        }
        .navigationTitle("Publications AFSR")
        .navigationBarTitleDisplayMode(.inline)
        .memberDocumentPreview(opener)
    }
}

private struct PublicationsContent: View {
    let session: MemberSession
    let opener: MemberDocumentOpener
    let response: PublicationsResponse
    let reload: () async -> Void

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if response.rettInfos.isEmpty && response.documents.isEmpty {
                    ContentUnavailableView(
                        "Aucune publication",
                        systemImage: "books.vertical",
                        description: Text("Les publications réservées aux adhérents apparaîtront ici.")
                    )
                }

                if !response.rettInfos.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rett Infos")
                            .font(AFSRFont.headline(18))
                        Text("\(response.rettInfos.count) numéro\(response.rettInfos.count > 1 ? "s" : "")")
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(response.rettInfos) { issue in issueCard(issue) }
                        }
                    }
                }

                if !response.documents.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Documents")
                            .font(AFSRFont.headline(18))
                        ForEach(response.documents) { document in documentCard(document) }
                    }
                }
            }
            .padding()
        }
        .background(Color.afsrBackground)
        .refreshable { await reload() }
    }

    private func issueCard(_ issue: MemberPublication) -> some View {
        Button {
            open(issue)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                cover(issue)
                Text(issue.label)
                    .font(AFSRFont.headline(14))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let year = issue.issueYear {
                    Text(String(year)).font(AFSRFont.caption()).foregroundStyle(.secondary)
                }
                if opener.busyKey == issue.slug {
                    ProgressView()
                } else if !issue.downloadable {
                    Text("Fichier indisponible").font(AFSRFont.caption()).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!issue.downloadable || opener.busyKey != nil)
        .accessibilityHint(issue.downloadable ? "Ouvre le document" : "Fichier indisponible")
    }

    private func cover(_ issue: MemberPublication) -> some View {
        Group {
            if let raw = issue.coverUrl, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    private var placeholder: some View {
        ZStack {
            Color.afsrAccent
            Image(systemName: "books.vertical").font(.largeTitle).foregroundStyle(.afsrPurple)
        }
    }

    private func documentCard(_ document: MemberPublication) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let date = MemberFormat.longDate(document.date) {
                Label(date, systemImage: "calendar")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.secondary)
            }
            Text(document.title).font(AFSRFont.headline(16))
            if let description = document.description {
                Text(description)
                    .font(AFSRFont.body(14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                open(document)
            } label: {
                HStack {
                    Label(document.downloadable ? "Ouvrir" : "Fichier indisponible", systemImage: "arrow.down.doc")
                    if opener.busyKey == document.slug { ProgressView() }
                }
            }
            .buttonStyle(.bordered)
            .disabled(!document.downloadable || opener.busyKey != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .afsrCard()
    }

    private func open(_ publication: MemberPublication) {
        guard let path = publication.downloadPath else { return }
        Task {
            await opener.open(
                key: publication.slug,
                path: path,
                fallbackName: "\(publication.slug).pdf",
                using: session
            )
        }
    }
}

// MARK: - Communications

struct MemberCommunicationsView: View {
    let session: MemberSession

    var body: some View {
        MemberResourceView<CommunicationsResponse, CommunicationsContent>(session: session, path: "/communications") { response, reload in
            CommunicationsContent(communications: response.communications, reload: reload)
        }
        .navigationTitle("Communications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CommunicationsContent: View {
    let communications: [MemberCommunication]
    let reload: () async -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if communications.isEmpty {
                    ContentUnavailableView(
                        "Aucune communication",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Les annonces de l'association à ses adhérents apparaîtront ici.")
                    )
                }
                ForEach(communications) { communication in
                    VStack(alignment: .leading, spacing: 10) {
                        if let raw = communication.logoUrl, let url = URL(string: raw) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFit()
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(maxHeight: 60, alignment: .leading)
                        }
                        if let date = MemberFormat.longDate(communication.date) {
                            Label(date, systemImage: "calendar")
                                .font(AFSRFont.caption())
                                .foregroundStyle(.secondary)
                        }
                        Text(communication.title).font(AFSRFont.headline(18))
                        MemberHTMLText(html: communication.html)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .afsrCard()
                }
            }
            .padding()
        }
        .background(Color.afsrBackground)
        .refreshable { await reload() }
    }
}

// MARK: - Rubriques du back-office

struct MemberSectionView: View {
    let session: MemberSession
    let section: MemberSection

    @State private var opener = MemberDocumentOpener()

    var body: some View {
        Group {
            if section.locked {
                MemberLockedView()
            } else {
                MemberResourceView<SectionDetailResponse, SectionContent>(
                    session: session,
                    path: "/rubriques/\(section.slug)"
                ) { response, reload in
                    SectionContent(session: session, opener: opener, slug: section.slug, detail: response.section, reload: reload)
                }
            }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .memberDocumentPreview(opener)
    }
}

private struct SectionContent: View {
    let session: MemberSession
    let opener: MemberDocumentOpener
    let slug: String
    let detail: SectionDetailResponse.Detail
    let reload: () async -> Void

    private var isEmpty: Bool {
        detail.introduction == nil && (detail.html ?? "").isEmpty && detail.files.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let introduction = detail.introduction {
                    Text(introduction)
                        .font(AFSRFont.body(16))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let html = detail.html, !html.isEmpty {
                    MemberHTMLText(html: html)
                }

                if !detail.files.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Documents").font(AFSRFont.headline(18))
                        ForEach(detail.files) { file in fileRow(file) }
                    }
                }

                if isEmpty {
                    ContentUnavailableView(
                        "Rubrique vide",
                        systemImage: "doc.text",
                        description: Text("Cette rubrique n'a pas encore de contenu.")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(Color.afsrBackground)
        .refreshable { await reload() }
    }

    private func fileRow(_ file: SectionDetailResponse.File) -> some View {
        let key = "\(slug)-\(file.index)"
        return Button {
            Task {
                await opener.open(
                    key: key,
                    path: "/api/membre/rubriques/\(slug)/fichiers/\(file.index)",
                    fallbackName: file.name,
                    using: session
                )
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill").foregroundStyle(.afsrPurpleAdaptive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).font(AFSRFont.body(15)).foregroundStyle(.primary)
                    if let size = file.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(AFSRFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if opener.busyKey == key { ProgressView() } else { Image(systemName: "arrow.down.circle") }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusSmall))
        }
        .buttonStyle(.plain)
        .disabled(opener.busyKey != nil)
    }
}
