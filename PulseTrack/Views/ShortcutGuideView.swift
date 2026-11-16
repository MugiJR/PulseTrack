import SwiftUI

/// Step-by-step guide for building the "PulseTrack Sync" shortcut.
struct ShortcutGuideView: View {
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private struct Row: Identifiable {
        let id = UUID()
        let type: String, days: String, code: String, note: String?
    }

    private let rows = [
        Row(type: "Sleep Analysis", days: "8", code: "S", note: nil),
        Row(type: "Heart Rate", days: "2", code: "HR", note: "Use 7 for your first sync to load history"),
        Row(type: "Resting Heart Rate", days: "30", code: "RHR", note: nil),
        Row(type: "Heart Rate Variability", days: "30", code: "HRV", note: nil),
        Row(type: "Respiratory Rate", days: "8", code: "RR", note: "Optional"),
        Row(type: "Blood Oxygen", days: "8", code: "O2", note: "Optional"),
        Row(type: "Workouts", days: "30", code: "W", note: "Optional · use Type instead of Value")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    partA
                    table
                    partAEnd
                    partB
                    actions
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Shortcut sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Why a shortcut?", systemImage: "info.circle.fill").font(.headline).foregroundStyle(Theme.accent)
            Text("Apps installed with a free Apple ID can't read Apple Health directly. Apple's Shortcuts app can, so you build one shortcut once, and it sends your Apple Watch data to PulseTrack. It takes about 10 minutes.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .card()
    }

    private var partA: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("1 · Build the shortcut").font(.title3.bold())
            step(1, "Open **Shortcuts**, tap **+**, and name it **PulseTrack Sync**.")
            step(2, "Add **Find Health Samples**. Set the type to **Sleep Analysis**, add the filter **Start Date is in the last 8 days**, and set **Sort by** to **Start Date**.")
            step(3, "Add **Repeat with Each** so it repeats over the Health Samples.")
            step(4, "Inside the repeat, add a **Text** action and fill it in exactly like this:")
            Text("S|Start Date|End Date|Value")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.tile, in: RoundedRectangle(cornerRadius: 10))
            Text("Type `S|`, then insert the **Repeat Item** variable. Tap it, choose **Start Date**, set the date format to **ISO 8601** and turn on **Include ISO 8601 Time**. Type `|`, add Repeat Item again as **End Date** (also ISO 8601), type `|`, then add Repeat Item as **Value**.")
                .font(.footnote).foregroundStyle(.secondary)
            step(5, "Still inside the repeat, add **Add to Variable** and name the variable **Lines**.")
            step(6, "Repeat steps 2–5 below the first block for every row in this table. Change the type, the days and the code at the start of the Text. Tip: long-press an action and choose **Duplicate**.")
        }
        .card()
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Health type").frame(maxWidth: .infinity, alignment: .leading)
                Text("Days").frame(width: 44)
                Text("Code").frame(width: 48)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(r.type).frame(maxWidth: .infinity, alignment: .leading)
                        Text(r.days).monospacedDigit().frame(width: 44)
                        Text(r.code).font(.system(.body, design: .monospaced).weight(.bold))
                            .foregroundStyle(Theme.accent).frame(width: 48)
                    }
                    .font(.subheadline)
                    if let note = r.note { Text(note).font(.caption2).foregroundStyle(.tertiary) }
                }
                Divider().opacity(0.3)
            }
            Text("If **Workouts** isn't in the type list, skip it. PulseTrack will spot workouts from your heart rate instead.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private var partAEnd: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(7, "After the last block, add **Combine Text**: combine **Lines** with **New Lines**.")
            step(8, "Add **Import Health Data** (search for *PulseTrack*) and set Health Data to the **Combined Text**.")
            Text("Can't find the PulseTrack action? Use **Copy to Clipboard** instead, then tap **Paste from clipboard** below.")
                .font(.footnote).foregroundStyle(.secondary)
            step(9, "Tap ▶︎ to run it. When Shortcuts asks for Health access, allow everything. The first run can take a minute.")
        }
        .card()
    }

    private var partB: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("2 · Make it automatic").font(.title3.bold())
            step(1, "In Shortcuts, open **Automation**, tap **+**, and choose **App**. Pick **PulseTrack**, tick **Is Opened**, select **Run Immediately**, then choose **PulseTrack Sync**. Your data now refreshes every time you open the app.")
            step(2, "Optional: add a **Time of Day** automation (say 8:00 daily, Run Immediately) so your sleep is ready each morning.")
        }
        .card()
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if let url = URL(string: "shortcuts://") { openURL(url) }
            } label: {
                Label("Open Shortcuts", systemImage: "square.stack.3d.up.fill").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)

            Button {
                health.importFromClipboard()
            } label: {
                Label("Paste from clipboard", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.bordered)

            if let last = health.lastImport {
                Text("Last sync \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(Theme.recovery)
            }
            if let error = health.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(Theme.accent.opacity(0.2), in: Circle())
                .foregroundStyle(Theme.accent)
            Text(text).font(.subheadline)
        }
    }
}
