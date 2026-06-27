import SwiftUI

enum Theme {
    // 背景 / 卡片 / 文字随系统外观切换；番茄红是品牌色，深浅模式通用。
    static let cream = dynamic(
        light: Color(red: 0.99, green: 0.97, blue: 0.93),
        dark:  Color(red: 0.12, green: 0.11, blue: 0.10))
    static let card = dynamic(
        light: .white,
        dark:  Color(red: 0.18, green: 0.17, blue: 0.16))
    static let tomato = Color(red: 0.89, green: 0.32, blue: 0.25)
    static let tomatoDark = Color(red: 0.76, green: 0.22, blue: 0.18)
    static let coffee = dynamic(
        light: Color(red: 0.45, green: 0.30, blue: 0.18),
        dark:  Color(red: 0.80, green: 0.62, blue: 0.44))
    static let textPrimary = dynamic(
        light: Color(red: 0.24, green: 0.18, blue: 0.14),
        dark:  Color(red: 0.95, green: 0.93, blue: 0.90))
    static let textSecondary = dynamic(
        light: Color(red: 0.55, green: 0.48, blue: 0.42),
        dark:  Color(red: 0.70, green: 0.66, blue: 0.62))

    /// 按当前外观（深/浅色）解析的动态色。
    private static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
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
