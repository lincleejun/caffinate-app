import SwiftUI

struct HistoryCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Theme.coffee)
                Text("历史")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }

            if state.recentHistory.isEmpty {
                Text("暂无运行记录")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(Array(state.recentHistory.enumerated()), id: \.offset) { _, record in
                    Text(record.display)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
