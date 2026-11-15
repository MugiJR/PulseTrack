import SwiftUI

@main
struct PulseTrackApp: App {
    @State private var health = HealthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(health)
        }
    }
}

struct RootView: View {
    @Environment(HealthManager.self) private var health

    var body: some View {
        Group {
            if health.needsOnboarding {
                OnboardingView()
            } else {
                TabView {
                    SleepView()
                        .tabItem { Label("Sleep", systemImage: "moon.zzz.fill") }
                    WorkoutView()
                        .tabItem { Label("Workout", systemImage: "figure.run") }
                    RecoveryView()
                        .tabItem { Label("Recovery", systemImage: "bolt.heart.fill") }
                }
                .tint(Theme.accent)
            }
        }
        .preferredColorScheme(.dark)
        .task { await health.start() }
    }
}
