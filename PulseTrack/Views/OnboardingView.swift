import SwiftUI

struct OnboardingView: View {
    @Environment(HealthManager.self) private var health

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.15)).frame(width: 130, height: 130)
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.top, 40)
                VStack(spacing: 8) {
                    Text("PulseTrack").font(.largeTitle.bold())
                    Text("Your Apple Watch, decoded.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 18) {
                    feature("moon.zzz.fill", Theme.sleep, "Sleep score", "A nightly 0–100 score with stages, efficiency and vitals.")
                    feature("figure.run", Theme.workout, "Previous workout", "Duration, heart-rate zones and training load.")
                    feature("bolt.heart.fill", Theme.recovery, "Recovery time", "Hours until you're ready, based on load, sleep, HRV and resting HR.")
                }
                .padding(.horizontal, 8)

                VStack(spacing: 12) {
                    Button {
                        Task { await health.useShortcut() }
                    } label: {
                        Label("Sync with Shortcuts", systemImage: "square.stack.3d.up.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    Text("Recommended for apps installed with Sideloadly or a free Apple ID.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

                    Button {
                        Task { await health.connect() }
                    } label: {
                        Label("Connect Apple Health directly", systemImage: "heart.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)

                    Button("Explore with demo data") { Task { await health.setDemo(true) } }
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    if health.isEntitlementError {
                        Text("Direct Health access isn't allowed for apps signed with a free Apple ID. Use **Sync with Shortcuts** instead.")
                            .font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                    } else if let error = health.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                    Text("Data is read-only and never leaves your iPhone.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(24)
        }
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
