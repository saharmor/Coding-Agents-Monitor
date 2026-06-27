import SwiftUI
import UsageCore

struct WidgetView: View {
    @ObservedObject var store: UsageStore
    @State private var showsWeekly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Usage")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                if store.setupMessage.contains("failed") {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .help(store.setupMessage)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsWeekly.toggle()
                    }
                } label: {
                    Image(systemName: showsWeekly ? "calendar.badge.minus" : "calendar")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(showsWeekly ? .primary : .secondary)
                .help(showsWeekly ? "Hide weekly usage" : "Show weekly usage")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            ProviderView(title: "Claude", snapshot: store.claude, showsWeekly: showsWeekly)
            ProviderView(title: "Codex", snapshot: store.codex, showsWeekly: showsWeekly)
        }
        .padding(10)
        .frame(width: 238)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: showsWeekly) { value in
            NotificationCenter.default.post(
                name: .usageMonitorWeeklyVisibilityChanged,
                object: nil,
                userInfo: ["showsWeekly": value]
            )
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 12)
    }
}

private struct ProviderView: View {
    var title: String
    var snapshot: UsageSnapshot?
    var showsWeekly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 44, alignment: .leading)

                UsageMeter(label: "5h", window: snapshot?.fiveHour, emptyText: statusText)
            }

            if showsWeekly {
                HStack(spacing: 6) {
                    Color.clear
                        .frame(width: 5, height: 5)
                    Text("")
                        .frame(width: 44)

                    UsageMeter(label: "7d", window: snapshot?.sevenDay, emptyText: statusText)
                }
            }
        }
    }

    private var statusText: String {
        guard let snapshot else {
            return "waiting"
        }
        let age = Date().timeIntervalSince(snapshot.updatedAt)
        if age > 600 {
            return "stale \(Int(age / 60))m"
        }
        if age < 60 {
            return "live"
        }
        return "\(Int(age / 60))m ago"
    }

    private var statusColor: Color {
        guard let snapshot else {
            return .orange
        }
        return Date().timeIntervalSince(snapshot.updatedAt) > 600 ? .orange : .green
    }
}

private struct UsageMeter: View {
    var label: String
    var window: LimitWindow?
    var emptyText: String

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .frame(width: 20, alignment: .leading)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(color)
                            .frame(width: geometry.size.width * CGFloat((window?.usedPercent ?? 0) / 100))
                    }
                }
                .frame(height: 6)
                Text(usedText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(width: 34, alignment: .trailing)
            }
            HStack {
                Text(resetText)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var usedText: String {
        guard let used = window?.usedPercent else {
            return "--"
        }
        return "\(Int(round(used)))%"
    }

    private var resetText: String {
        if window == nil {
            return emptyText
        }
        guard let date = window?.resetsAt else {
            return "reset unknown"
        }
        return "resets \(ResetFormatter.shared.string(from: date))"
    }

    private var color: Color {
        guard let used = window?.usedPercent else {
            return .gray
        }
        if used >= 90 {
            return .red
        }
        if used >= 70 {
            return .orange
        }
        return .green
    }
}

@MainActor
private final class ResetFormatter {
    static let shared = ResetFormatter()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter
    }()

    func string(from date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 24 * 60 * 60 {
            return timeFormatter.string(from: date)
        }
        return dateFormatter.string(from: date)
    }
}
