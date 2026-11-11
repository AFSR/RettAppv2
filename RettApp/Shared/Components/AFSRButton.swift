import SwiftUI

// MARK: - Primary button

struct AFSRPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = .afsrPurpleAdaptive
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon { Image(systemName: icon) }
                Text(title)
                    .font(AFSRFont.headline(18))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: AFSRTokens.minTapTarget)
            .foregroundStyle(.white)
            .background(AFSRGradient.tinted(color), in: RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius, style: .continuous))
            .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(AFSRPressableStyle())
    }
}

// MARK: - Secondary / outline button

struct AFSRSecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon { Image(systemName: icon) }
                Text(title)
                    .font(AFSRFont.headline(17))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: AFSRTokens.minTapTarget)
            .foregroundStyle(.afsrPurpleAdaptive)
            .background(
                Color.afsrPurpleAdaptive.opacity(0.08),
                in: RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius, style: .continuous)
                    .stroke(Color.afsrPurpleAdaptive, lineWidth: 2)
            )
        }
        .buttonStyle(AFSRPressableStyle())
    }
}

// MARK: - Emergency giant button

struct AFSREmergencyButton: View {
    let title: String
    var icon: String? = "bolt.heart.fill"
    var subtitle: String? = "Toucher pour lancer le chronomètre"
    var color: Color = .afsrEmergency
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .bold))
                        .frame(width: 68, height: 68)
                        .background(.white.opacity(0.2), in: Circle())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AFSRFont.headline(22))
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(AFSRFont.caption())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                LinearGradient(
                    colors: [color, Color(hex: "#FF6F61")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: AFSRTokens.cornerRadiusLarge, style: .continuous)
            )
            .shadow(color: color.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(AFSRPressableStyle())
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack(spacing: 16) {
        AFSREmergencyButton(title: "🚨 Démarrer une crise") {}
        AFSRPrimaryButton(title: "Enregistrer", icon: "checkmark") {}
        AFSRSecondaryButton(title: "Annuler") {}
    }
    .padding()
}
