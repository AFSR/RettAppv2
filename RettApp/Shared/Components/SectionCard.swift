import SwiftUI

struct SectionCard<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var accent: Color = .afsrPurple
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(accent)
                }
                Text(title)
                    .font(AFSRFont.headline(18))
            }
            content()
        }
        .afsrCard()
    }
}

#Preview {
    SectionCard(title: "Aujourd'hui", systemImage: "sun.max.fill") {
        Text("Contenu de la carte")
    }
    .padding()
}
