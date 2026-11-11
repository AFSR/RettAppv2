import SwiftUI

struct SectionCard<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var accent: Color = .afsrPurple
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let systemImage {
                    AFSRIconBadge(systemImage: systemImage, color: accent, size: 30)
                }
                Text(title)
                    .font(AFSRFont.headline(17))
            }
            content()
        }
        .afsrCard()
    }
}

// MARK: - Pastille d'icône

/// Icône blanche sur carré arrondi coloré, à la manière des Réglages iOS.
/// Donne un repère visuel par rubrique au lieu d'une liste de pictogrammes
/// monochromes.
struct AFSRIconBadge: View {
    let systemImage: String
    var color: Color = .afsrPurple
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                AFSRGradient.tinted(color),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// Variante douce : icône colorée sur fond teinté pâle. Pour les lignes de
/// contenu (journal) où une pastille pleine serait trop appuyée.
struct AFSRSoftIconBadge: View {
    let systemImage: String
    var color: Color = .afsrPurpleAdaptive
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Libellé de ligne de liste avec pastille colorée. Remplace `Label` dans
/// les `List` des onglets Réglages, AFSR et Adhérent.
struct AFSRRowLabel: View {
    let title: String
    let systemImage: String
    var color: Color = .afsrPurple
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            AFSRIconBadge(systemImage: systemImage, color: color, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(AFSRFont.caption())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Avatar

/// Avatar rond aux initiales, sur le dégradé AFSR.
struct AFSRAvatar: View {
    let name: String
    var size: CGFloat = 52

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map { String($0).uppercased() }
        return letters.joined()
    }

    var body: some View {
        ZStack {
            Circle().fill(AFSRGradient.brand)
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 2))
        .shadow(color: .afsrShadow, radius: 6, x: 0, y: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - En-tête d'onglet

/// Bandeau d'accueil sur dégradé AFSR : titre, sous-titre et symbole en
/// filigrane. Pose l'identité de l'onglet dès le premier regard.
struct AFSRHeroHeader<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String = "heart.fill"
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: 110, weight: .bold))
                .foregroundStyle(.white.opacity(0.12))
                .rotationEffect(.degrees(-12))
                .offset(x: 24, y: -14)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(AFSRFont.title(24))
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(AFSRFont.body(15))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
                accessory()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(AFSRGradient.brand)
        .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusLarge, style: .continuous))
        .shadow(color: Color.afsrPurpleDark.opacity(0.25), radius: 14, x: 0, y: 6)
    }
}

extension AFSRHeroHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String = "heart.fill") {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = { EmptyView() }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            AFSRHeroHeader(title: "Bonjour", subtitle: "Voici la journée de Léa", systemImage: "sun.max.fill")
            SectionCard(title: "Aujourd'hui", systemImage: "sun.max.fill") {
                Text("Contenu de la carte")
            }
            AFSRRowLabel(title: "Soutenir l'AFSR", systemImage: "heart.fill", color: .afsrEmergency)
            AFSRAvatar(name: "Marie Dupont")
        }
        .padding()
    }
    .background(Color.afsrBackground)
}
