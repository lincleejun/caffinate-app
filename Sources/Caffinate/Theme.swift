import SwiftUI

enum Theme {
    static let cream = Color(red: 0.99, green: 0.97, blue: 0.93)
    static let card = Color.white
    static let tomato = Color(red: 0.89, green: 0.32, blue: 0.25)
    static let tomatoDark = Color(red: 0.76, green: 0.22, blue: 0.18)
    static let coffee = Color(red: 0.45, green: 0.30, blue: 0.18)
    static let textPrimary = Color(red: 0.24, green: 0.18, blue: 0.14)
    static let textSecondary = Color(red: 0.55, green: 0.48, blue: 0.42)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}
