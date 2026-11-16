import AppIntents

/// Appears in the Shortcuts app as "Import Health Data" (PulseTrack).
struct ImportHealthDataIntent: AppIntent {
    static var title: LocalizedStringResource = "Import Health Data"
    static var description = IntentDescription("Sends Apple Health samples collected by a shortcut to PulseTrack.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Health Data", inputOptions: String.IntentInputOptions(multiline: true))
    var data: String

    static var parameterSummary: some ParameterSummary {
        Summary("Import \(\.$data) into PulseTrack")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let summary = try ImportStore.shared.ingest(data)
        return .result(value: summary)
    }
}
