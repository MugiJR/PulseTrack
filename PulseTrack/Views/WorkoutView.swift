import SwiftUI
import Charts

struct WorkoutView: View {
    @Environment(HealthManager.self) private var health

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = health.errorMessage { ErrorBanner(message: error) }

                    if let w = health.selectedWorkout {
                        hero(w)
                        if !health.zones.isEmpty { zonesCard }
                        recentList
                    } else if health.phase == .loading {
                        ProgressView().padding(.top, 80)
                    } else {
                        EmptyStateView(symbol: "figure.run", title: "No recent workouts",
                                       message: "Workouts recorded on your Apple Watch in the last 30 days will appear here.")
                    }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Workout")
            .toolbar {
                if health.isDemo { ToolbarItem(placement: .topBarLeading) { DemoBadge() } }
                ToolbarItem(placement: .topBarTrailing) { OptionsMenu() }
            }
            .refreshable { await health.refresh() }
        }
    }

    private func hero(_ w: WorkoutSummary) -> some View {
        let isLatest = w.id == health.workouts.first?.id
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: w.symbol)
                    .font(.title)
                    .foregroundStyle(Theme.workout)
                    .frame(width: 58, height: 58)
                    .background(Theme.workout.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLatest ? "PREVIOUS WORKOUT" : "WORKOUT")
                        .font(.caption2.weight(.bold)).foregroundStyle(Theme.workout)
                    Text(w.name).font(.title2.bold())
                    Text(w.start.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricTile(title: "Time", value: w.duration.hm, symbol: "timer", tint: Theme.workout)
                MetricTile(title: "Active", value: w.energy.map { "\(Int($0)) kcal" } ?? "—", symbol: "flame.fill", tint: Theme.workout)
                MetricTile(title: "Distance", value: w.distance.map(formatDistance) ?? "—", symbol: "location.fill", tint: Theme.workout)
                MetricTile(title: "Avg HR", value: w.avgHR.map { "\(Int($0))" } ?? "—", symbol: "heart.fill", tint: .pink)
                MetricTile(title: "Max HR", value: w.maxHR.map { "\(Int($0))" } ?? "—", symbol: "heart.circle.fill", tint: .pink)
                MetricTile(title: "Load", value: "\(Int(w.load))", symbol: "chart.bar.fill", tint: Theme.accent)
            }

            HStack {
                Label("\(w.intensity) effort", systemImage: "speedometer")
                Spacer()
                Label("~\(Int(health.recoveryHours(for: w).rounded()))h to recover", systemImage: "bolt.heart.fill")
                    .foregroundStyle(Theme.recovery)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .card()
    }

    private var zonesCard: some View {
        let total = health.zones.reduce(0) { $0 + $1.minutes }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Heart-rate zones", subtitle: "Based on max HR \(Int(health.maxHR)) bpm")
            ForEach(health.zones) { z in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(z.name).font(.subheadline.weight(.medium))
                        Text(z.range).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: 92, alignment: .leading)
                    GeometryReader { geo in
                        Capsule()
                            .fill(z.color)
                            .frame(width: max(4, geo.size.width * (total > 0 ? z.minutes / total : 0)))
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 12)
                    Text(TimeInterval(z.minutes * 60).hm)
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .card()
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Recent workouts").padding(.bottom, 8)
            ForEach(health.workouts) { w in
                Button {
                    Task { await health.select(w) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: w.symbol)
                            .foregroundStyle(Theme.workout)
                            .frame(width: 38, height: 38)
                            .background(Theme.workout.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name).font(.subheadline.weight(.semibold))
                            Text(w.start.formatted(.relative(presentation: .named)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(w.duration.hm).font(.subheadline.weight(.semibold)).monospacedDigit()
                            Text(w.intensity).font(.caption).foregroundStyle(.secondary)
                        }
                        if w.id == health.selectedWorkout?.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if w.id != health.workouts.last?.id { Divider().opacity(0.3) }
            }
        }
        .card()
    }

    private func formatDistance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road,
                                    numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }
}
