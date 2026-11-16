import SwiftUI

enum Theme {
    static let background = Color(red: 0.04, green: 0.05, blue: 0.08)
    static let card = Color(red: 0.10, green: 0.11, blue: 0.15)
    static let tile = Color(red: 0.14, green: 0.15, blue: 0.20)
    static let accent = Color(red: 0.45, green: 0.55, blue: 1.00)
    static let sleep = Color(red: 0.50, green: 0.42, blue: 1.00)
    static let workout = Color(red: 1.00, green: 0.48, blue: 0.25)
    static let recovery = Color(red: 0.25, green: 0.85, blue: 0.55)

    static func scoreColor(_ score: Int) -> Color {
        switch score {
        case 85...: recovery
        case 70..<85: Color(red: 0.55, green: 0.80, blue: 0.35)
        case 50..<70: Color(red: 1.00, green: 0.75, blue: 0.25)
        default: Color(red: 1.00, green: 0.42, blue: 0.40)
        }
    }
}

extension View {
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    func screenBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
    }
}

extension TimeInterval {
    /// "7h 32m"
    var hm: String {
        let m = Int((self / 60).rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

extension Double {
    var percent: String { "\(Int((self * 100).rounded()))%" }
}

struct ScoreRing<Content: View>: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.9), value: progress)
            content
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct EmptyStateView: View {
    @Environment(HealthManager.self) private var health
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: health.awaitingFirstImport ? "square.stack.3d.up" : symbol)
                .font(.system(size: 44)).foregroundStyle(.secondary)
            Text(health.awaitingFirstImport ? "Waiting for your first sync" : title)
                .font(.title3.weight(.semibold))
            Text(health.awaitingFirstImport
                 ? "Build the PulseTrack Sync shortcut and run it once. Your Apple Watch data will show up here."
                 : message)
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if health.usesShortcut {
                Button("Shortcut setup guide") { health.showShortcutGuide = true }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .padding(.top, 4)
                Button("Paste from clipboard") { health.importFromClipboard() }
                    .buttonStyle(.bordered)
            } else if !health.isDemo {
                Button("Explore with demo data") { Task { await health.setDemo(true) } }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .card()
    }
}

/// "Synced 2 hours ago" line shown at the top of each tab when using Shortcuts.
struct SyncStatusView: View {
    @Environment(HealthManager.self) private var health

    var body: some View {
        if health.usesShortcut, let last = health.lastImport {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.icloud.fill")
                Text("Synced \(last.formatted(.relative(presentation: .named)))")
                if Date().timeIntervalSince(last) > 12 * 3600 {
                    Text("· run PulseTrack Sync to update").foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .card()
    }
}

struct DemoBadge: View {
    var body: some View {
        Text("DEMO DATA")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.orange.opacity(0.2), in: Capsule())
            .foregroundStyle(.orange)
    }
}

struct OptionsMenu: View {
    @Environment(HealthManager.self) private var health

    var body: some View {
        Menu {
            Button { Task { await health.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            if health.usesShortcut {
                Button { health.importFromClipboard() } label: { Label("Paste data from clipboard", systemImage: "doc.on.clipboard") }
                Button { health.showShortcutGuide = true } label: { Label("Shortcut setup guide", systemImage: "square.stack.3d.up") }
            }
            Divider()
            if health.isDemo {
                Button { Task { await health.setDemo(false) } } label: { Label("Use my Apple Watch data", systemImage: "applewatch") }
            } else {
                Button { Task { await health.setDemo(true) } } label: { Label("Show demo data", systemImage: "sparkles") }
            }
            if health.source == .shortcut {
                Button { Task { await health.useHealthKit() } } label: { Label("Try direct Apple Health access", systemImage: "heart") }
            } else {
                Button { Task { await health.useShortcut() } } label: { Label("Sync with Shortcuts instead", systemImage: "square.stack.3d.up") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}
