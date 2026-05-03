import SwiftUI
import PassKit

/// Wrapper SwiftUI autour de `PKPaymentButton`. SwiftUI fournit `PayWithApplePayButton`
/// depuis iOS 16, mais l'API reste capricieuse côté UIKit-style sur les paramètres
/// de style (luminance) et d'animation. On utilise notre propre wrapper pour avoir
/// un comportement prévisible.
struct ApplePayButtonRepresentable: UIViewRepresentable {
    var type: PKPaymentButtonType = .donate
    var style: PKPaymentButtonStyle = .automatic
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: type, paymentButtonStyle: style)
        button.cornerRadius = 12
        button.addTarget(context.coordinator,
                         action: #selector(Coordinator.tapped),
                         for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        context.coordinator.action = action
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
