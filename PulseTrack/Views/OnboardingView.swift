import SwiftUI

struct OnboardingView: View {
    @Environment(HealthManager.self) private var health

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15)).frame(width: 140, height: 140)
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.accent)
            }
            VStack(spacing: 8) {
                Text("PulseTrack").font(.largeTitle.bold())
                Text("Your Apple Watch, decoded.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                feature("moon.zzz.fill", Theme.sleep, "Sleep score", "A nightly 0–100 score with stages, efficiency and vitals.")
                feature("figure.run", Theme.workout, "Previous workout", "Duration, heart-rate zones, calories and training load.")
                feature("bolt.heart.fill", Theme.recovery, "Recovery time", "Hours until you're ready, based on load, sleep, HRV and resting HR.")
            }
            .padding(.horizontal, 8)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    Task { await health.connect() }
                } label: {
                    Label("Connect Apple Health", systemImage: "heart.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button("Explore with demo data") { Task { await health.setDemo(true) } }
                    .foregroundStyle(.secondary)

                if let error = health.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
                Text("Data is read-only and never leaves your iPhone.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .background(Theme.background.ignoresSafeArea())
    }

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
