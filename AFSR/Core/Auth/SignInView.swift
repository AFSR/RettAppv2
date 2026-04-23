import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.afsrPurpleDark, .afsrPurple, .afsrPurpleLight],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "heart.text.square.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .foregroundStyle(.white)
                        .shadow(radius: 8)

                    Text("RettApp")
                        .font(AFSRFont.title(44))
                        .foregroundStyle(.white)

                    Text("Association Française\ndu Syndrome de Rett")
                        .font(AFSRFont.headline(18))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer()

                VStack(spacing: 16) {
                    Text("Connectez-vous pour suivre\nle quotidien de votre enfant.")
                        .font(AFSRFont.body())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.95))

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName]
                    } onCompletion: { result in
                        authManager.handle(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: AFSRTokens.minTapTarget)
                    .clipShape(RoundedRectangle(cornerRadius: AFSRTokens.cornerRadius))

                    if let error = authManager.lastError {
                        Text(error)
                            .font(AFSRFont.caption())
                            .foregroundStyle(.white)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(.red.opacity(0.6), in: Capsule())
                    }
                }
                .padding(.horizontal, AFSRTokens.spacingLarge)

                Text("Vos données restent sur votre appareil.")
                    .font(AFSRFont.caption())
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, AFSRTokens.spacingLarge)
            }
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthManager())
}
