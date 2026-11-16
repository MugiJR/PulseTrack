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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var health = health
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
        .sheet(isPresented: $health.showShortcutGuide) {
            ShortcutGuideView()
                .preferredColorScheme(.dark)
        }
        .preferredColorScheme(.dark)
        .task { await health.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && health.usesShortcut {
                Task { await health.refresh() }
            }
        }
    }
}
