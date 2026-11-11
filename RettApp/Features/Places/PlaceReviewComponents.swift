import SwiftUI
import UIKit

// MARK: - La note

/// Cinq étoiles qu'on touche ou qu'on balaie, avec le mot qui va avec.
///
/// Le balayage n'est pas un ornement : c'est le geste de Plans et de Google
/// Maps, et quelqu'un qui a noté un restaurant une fois dans sa vie l'a dans
/// les doigts. Toucher la troisième étoile fonctionne aussi — les deux gestes
/// mènent au même endroit, ce qui est la définition d'un contrôle qu'on n'a
/// pas besoin d'apprendre.
///
/// Le mot sous les étoiles compte autant qu'elles. « 3 sur 5 » n'aide
/// personne à savoir si c'est bien ; « Correct » le dit.
struct StarRatingPicker: View {
    @Binding var rating: Int

    /// Le cran sous le doigt pendant un balayage, pour que les étoiles
    /// suivent le geste avant qu'on relâche.
    @State private var survol: Int?

    private let taille: CGFloat = 38
    private let ecart: CGFloat = 10

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: ecart) {
                ForEach(1...5, id: \.self) { cran in
                    Image(systemName: cran <= (survol ?? rating) ? "star.fill" : "star")
                        .font(.system(size: taille, weight: .regular))
                        .foregroundStyle(cran <= (survol ?? rating) ? Color.afsrWarning : Color.secondary.opacity(0.45))
                        .frame(width: taille + ecart, height: taille + 6)
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { valeur in
                        let cran = Self.cran(pour: valeur.location.x, largeurPas: taille + ecart)
                        if cran != survol {
                            survol = cran
                            Self.retour(.light)
                        }
                    }
                    .onEnded { valeur in
                        rating = Self.cran(pour: valeur.location.x, largeurPas: taille + ecart)
                        survol = nil
                        Self.retour(.medium)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Note de l'accueil")
            .accessibilityValue(rating == 0 ? "Aucune note" : "\(rating) sur 5, \(Self.mot(rating))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: rating = min(5, max(1, rating + 1))
                case .decrement: rating = max(1, rating - 1)
                default: break
                }
            }

            Text(rating == 0 ? "Touchez une étoile" : Self.mot(rating))
                .font(AFSRFont.headline(17))
                .foregroundStyle(rating == 0 ? .secondary : .primary)
                .animation(.none, value: rating)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private static func cran(pour x: CGFloat, largeurPas: CGFloat) -> Int {
        min(5, max(1, Int(x / largeurPas) + 1))
    }

    /// Le mot qui qualifie l'accueil, et seulement l'accueil : l'accessibilité
    /// est décrite par les constats, pas par cette note.
    static func mot(_ note: Int) -> String {
        switch note {
        case 1: return "Très mauvais accueil"
        case 2: return "Accueil décevant"
        case 3: return "Accueil correct"
        case 4: return "Bon accueil"
        default: return "Accueil remarquable"
        }
    }

    private static func retour(_ force: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: force).impactOccurred()
    }
}

// MARK: - Les constats

/// L'état d'un constat : on a pu, on n'a pas pu, ou on n'a pas essayé.
enum CriterionAnswer {
    case inconnu
    case oui
    case non

    /// Le tour suivant. Trois états et non deux, parce que « je n'ai pas
    /// essayé » n'est pas « ce n'est pas là » — et qu'une famille qui n'a pas
    /// demandé les toilettes adaptées ne doit pas peser dans leur décompte.
    var suivant: CriterionAnswer {
        switch self {
        case .inconnu: return .oui
        case .oui: return .non
        case .non: return .inconnu
        }
    }

    var valeurEnvoyee: String? {
        switch self {
        case .inconnu: return nil
        case .oui: return "oui"
        case .non: return "non"
        }
    }

    init(_ brut: String?) {
        switch brut {
        case "oui": self = .oui
        case "non": self = .non
        default: self = .inconnu
        }
    }
}

/// Une pastille qu'on touche pour répondre à un constat.
///
/// Les pastilles plutôt qu'une liste de boutons à trois positions : c'est la
/// forme de Plans et de Google Maps, elle se parcourt d'un coup d'œil, et elle
/// tient sur un écran de téléphone là où quinze contrôles segmentés
/// demandaient de défiler.
struct CriterionChip: View {
    let question: String
    let answer: CriterionAnswer
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbole)
                    .font(.footnote.weight(.semibold))
                Text(question)
                    .font(AFSRFont.body())
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(fond, in: Capsule())
            .overlay(Capsule().strokeBorder(bordure, lineWidth: 1))
            .foregroundStyle(texte)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(question)
        .accessibilityValue(valeurVocale)
        .accessibilityHint("Touchez pour changer la réponse")
    }

    private var symbole: String {
        switch answer {
        case .inconnu: return "questionmark.circle"
        case .oui: return "checkmark.circle.fill"
        case .non: return "xmark.circle.fill"
        }
    }

    private var fond: Color {
        switch answer {
        case .inconnu: return Color.secondary.opacity(0.10)
        case .oui: return Color.afsrSuccess.opacity(0.16)
        case .non: return Color.afsrEmergency.opacity(0.14)
        }
    }

    private var bordure: Color {
        switch answer {
        case .inconnu: return Color.secondary.opacity(0.25)
        case .oui: return Color.afsrSuccess.opacity(0.55)
        case .non: return Color.afsrEmergency.opacity(0.5)
        }
    }

    private var texte: Color {
        switch answer {
        case .inconnu: return .secondary
        case .oui: return .afsrSuccess
        case .non: return .afsrEmergency
        }
    }

    private var valeurVocale: String {
        switch answer {
        case .inconnu: return "Pas de réponse"
        case .oui: return "Oui, j'ai pu"
        case .non: return "Non, je n'ai pas pu"
        }
    }
}

// MARK: - Disposition

/// Dispose ses éléments de gauche à droite et passe à la ligne quand la place
/// manque, comme les pastilles de Plans.
///
/// Écrit à la main parce que SwiftUI n'offre rien de tel ; `Layout`, lui, est
/// fait pour ça depuis iOS 16. Une grille à colonnes fixes ne conviendrait
/// pas : les questions n'ont pas la même longueur, et un gabarit rigide
/// laisserait des trous ou couperait les mots.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        let lignes = decouper(subviews: subviews, largeurMax: largeur)

        let hauteur = lignes.reduce(CGFloat.zero) { total, ligne in
            total + ligne.hauteur
        } + CGFloat(max(0, lignes.count - 1)) * lineSpacing

        return CGSize(width: proposal.width ?? lignes.map(\.largeur).max() ?? 0, height: hauteur)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lignes = decouper(subviews: subviews, largeurMax: bounds.width)
        var y = bounds.minY

        for ligne in lignes {
            var x = bounds.minX
            for index in ligne.indices {
                let taille = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (ligne.hauteur - taille.height) / 2),
                    proposal: ProposedViewSize(taille)
                )
                x += taille.width + spacing
            }
            y += ligne.hauteur + lineSpacing
        }
    }

    private struct Ligne {
        var indices: [Int] = []
        var largeur: CGFloat = 0
        var hauteur: CGFloat = 0
    }

    private func decouper(subviews: Subviews, largeurMax: CGFloat) -> [Ligne] {
        var lignes: [Ligne] = []
        var courante = Ligne()

        for index in subviews.indices {
            let taille = subviews[index].sizeThatFits(.unspecified)
            let ajout = courante.indices.isEmpty ? taille.width : taille.width + spacing

            if !courante.indices.isEmpty, courante.largeur + ajout > largeurMax {
                lignes.append(courante)
                courante = Ligne()
                courante.indices = [index]
                courante.largeur = taille.width
                courante.hauteur = taille.height
            } else {
                courante.indices.append(index)
                courante.largeur += ajout
                courante.hauteur = max(courante.hauteur, taille.height)
            }
        }

        if !courante.indices.isEmpty { lignes.append(courante) }

        return lignes
    }
}

// MARK: - Zone de texte avec invite

/// Un champ de texte libre qui porte son invite, comme celui de Google Maps.
///
/// `TextEditor` n'accepte pas de « placeholder » : on le superpose, et on le
/// masque dès qu'un caractère est saisi. Le texte de l'invite n'est pas
/// décoratif — « Partagez votre expérience » obtient des phrases vagues,
/// « ce que vous auriez aimé savoir avant de venir » obtient des faits.
struct PromptedTextEditor: View {
    @Binding var text: String
    let prompt: String
    var minHeight: CGFloat = 130

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(prompt)
                    .font(AFSRFont.body())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(AFSRFont.body())
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
        }
    }
}
