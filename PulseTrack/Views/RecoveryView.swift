import SwiftUI

struct RecoveryView: View {
    @Environment(HealthManager.self) private var health
    @State private var showMethod = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = health.errorMessage { ErrorBanner(message: error) }

                    if let r = health.recovery, r.lastWorkout != nil || !r.factors.isEmpty {
                        timeCard(r)
                        readinessCard(r)
                        factorsCard(r)
                        recommendationCard(r)
                        methodCard
                    } else if health.phase == .loading {
                        ProgressView().padding(.top, 80)
                    } else {
                        EmptyStateView(symbol: "bolt.heart", title: "Not enough data yet",
                                       message: "Recovery needs a recent workout, a night of sleep, or HRV readings from your Apple Watch.")
                    }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Recovery")
            .toolbar {
                if health.isDemo { ToolbarItem(placement: .topBarLeading) { DemoBadge() } }
                ToolbarItem(placement: .topBarTrailing) { OptionsMenu() }
            }
            .refreshable { await health.refresh() }
        }
    }

    private func timeCard(_ r: RecoveryStatus) -> some View {
        let recovered = r.remainingHours < 1
        return VStack(spacing: 16) {
            ScoreRing(progress: r.progress, color: Theme.recovery, lineWidth: 18) {
                VStack(spacing: 2) {
                    if recovered {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(Theme.recovery)
                        Text("Recovered").font(.title3.bold())
                    } else {
                        Text("\(Int(r.remainingHours.rounded(.up)))h")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                        Text("until recovered").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 200, height: 200)
            .padding(.top, 8)

            if !recovered {
                Label("Ready \(r.readyAt.formatted(.dateTime.weekday(.wide).hour().minute()))", systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.medium))
            }
            if let w = r.lastWorkout {
                Text("Total recovery for your \(w.name.lowercased()): \(Int(r.totalHours.rounded()))h · \(Int(r.progress * 100))% done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func readinessCard(_ r: RecoveryStatus) -> some View {
        let color = Theme.scoreColor(r.readiness)
        return HStack(spacing: 16) {
            ScoreRing(progress: Double(r.readiness) / 100, color: color, lineWidth: 8) {
                Text("\(r.readiness)").font(.title2.bold().monospacedDigit())
            }
            .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text("Readiness").font(.headline)
                Text(readinessLabel(r.readiness)).font(.subheadline).foregroundStyle(color)
                Text("Combines sleep, HRV, resting heart rate and remaining fatigue.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func factorsCard(_ r: RecoveryStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "What's affecting recovery")
            ForEach(r.factors) { f in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: f.impact.symbol).foregroundStyle(f.impact.color).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(f.title).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(f.value).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        Text(f.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card()
    }

    private func recommendationCard(_ r: RecoveryStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's guidance").font(.headline)
                Text(r.recommendation).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var methodCard: some View {
        DisclosureGroup(isExpanded: $showMethod) {
            Text("""
            Training load uses Banister's TRIMP: workout minutes weighted by how close your average heart rate was to your max. \
            Base recovery is 4h + 0.33h per load point (max 72h). That's then adjusted by last night's sleep score, \
            your HRV and resting heart rate compared with your 30-day averages. Fatigue from older workouts in the past \
            5 days adds on top. This is an estimate, not medical advice.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        } label: {
            Label("How it's calculated", systemImage: "info.circle").font(.subheadline.weight(.medium))
        }
        .tint(.secondary)
        .card()
    }

    private func readinessLabel(_ v: Int) -> String {
        switch v {
        case 85...: "Primed — go hard"
        case 70..<85: "Good to train"
        case 50..<70: "Take it moderate"
        default: "Rest recommended"
        }
    }
}
