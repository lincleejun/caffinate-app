import SwiftUI
import CaffinateKit

struct HistoryCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Theme.coffee)
                Text("History")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }

            if state.recentHistory.isEmpty {
                Text("No runs yet")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(Array(state.recentHistory.enumerated()), id: \.offset) { _, record in
                    Text(localizedDisplay(record))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// GUI 本地化的单行历史；CLI 用 record.display（固定英文）。
    private func localizedDisplay(_ r: HistoryRecord) -> String {
        let check = r.completed ? "✓" : "✗"
        switch r.type {
        case "caffeine":
            let mode = r.detail == "enhanced"
                ? String(localized: "Enhanced") : String(localized: "Basic")
            return "☕ \(mode) · \(r.startHM)–\(r.endHM) · \(r.durationText)"
        case "focus":
            return String(localized: "🍅 Focus · \(r.durationText) \(check)")
        case "rest":
            return String(localized: "🍵 Break · \(r.durationText) \(check)")
        default:
            return "\(r.type) · \(r.durationText)"
        }
    }
}
