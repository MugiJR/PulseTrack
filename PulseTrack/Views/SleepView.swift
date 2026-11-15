import SwiftUI
import Charts

struct SleepView: View {
    @Environment(HealthManager.self) private var health

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dayPicker
                    if let error = health.errorMessage { ErrorBanner(message: error) }

                    if let night = health.night, let score = health.sleepScore {
                        scoreCard(score, night)
                        hypnogram(night)
                        stages(night)
                        metrics(night)
                        breakdown(score)
                    } else if health.phase == .loading {
                        ProgressView().padding(.top, 80)
                    } else {
                        EmptyStateView(symbol: "moon.zzz", title: "No sleep data for this night",
                                       message: "Wear your Apple Watch to bed with Sleep Focus or sleep tracking turned on.")
                    }

                    if !health.history.isEmpty { historyCard }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Sleep")
            .toolbar {
                if health.isDemo { ToolbarItem(placement: .topBarLeading) { DemoBadge() } }
                ToolbarItem(placement: .topBarTrailing) { OptionsMenu() }
            }
            .refreshable { await health.refresh() }
        }
    }

    // MARK: Sections

    private var dayPicker: some View {
        HStack {
            Button { Task { await health.shiftDay(by: -1) } } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(health.isToday ? "Last night" : health.selectedDay.formatted(.dateTime.weekday(.wide).day().month()))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button { Task { await health.shiftDay(by: 1) } } label: { Image(systemName: "chevron.right") }
                .disabled(health.isToday)
        }
        .padding(.horizontal, 4)
    }

    private func scoreCard(_ score: SleepScore, _ night: SleepNight) -> some View {
        HStack(spacing: 20) {
            ScoreRing(progress: Double(score.total) / 100, color: score.color, lineWidth: 14) {
                VStack(spacing: 0) {
                    Text("\(score.total)").font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("SLEEP SCORE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 10) {
                Text(score.rating).font(.title2.bold()).foregroundStyle(score.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(night.asleep.hm).font(.title3.weight(.semibold))
                    Text("asleep").font(.caption).foregroundStyle(.secondary)
                }
                Text("\(night.start.formatted(date: .omitted, time: .shortened)) – \(night.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func hypnogram(_ night: SleepNight) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Sleep stages")
            Chart(night.segments) { seg in
                RectangleMark(
                    xStart: .value("Start", seg.start),
                    xEnd: .value("End", seg.end),
                    y: .value("Stage", seg.stage.label),
                    height: .ratio(0.75)
                )
                .foregroundStyle(seg.stage.color)
                .cornerRadius(3)
            }
            .chartYScale(domain: SleepStage.allCases.map(\.label))
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: 170)
        }
        .card()
    }

    private func stages(_ night: SleepNight) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Time in each stage", subtitle: "Share of total sleep")
            ForEach([SleepStage.deep, .core, .rem, .awake]) { stage in
                let share = night.share(of: stage)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle().fill(stage.color).frame(width: 8, height: 8)
                        Text(stage.label).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(stage == .awake ? night.awake.hm : night.duration(of: stage).hm)
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(share.percent).font(.caption).foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                    ProgressView(value: min(share, 1)).tint(stage.color)
                    Text("Ideal: \(stage.idealRange)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .card()
    }

    private func metrics(_ night: SleepNight) -> some View {
        let v = night.vitals
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Sleep metrics")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricTile(title: "Time in bed", value: night.timeInBed.hm, symbol: "bed.double.fill")
                MetricTile(title: "Efficiency", value: night.efficiency.percent, symbol: "gauge.with.dots.needle.67percent")
                MetricTile(title: "Bedtime", value: night.start.formatted(date: .omitted, time: .shortened), symbol: "moon.fill")
                MetricTile(title: "Wake up", value: night.end.formatted(date: .omitted, time: .shortened), symbol: "sun.max.fill")
                MetricTile(title: "Wake-ups", value: "\(night.awakenings)", symbol: "eye.fill")
                MetricTile(title: "Awake", value: night.awake.hm, symbol: "clock.fill")
                MetricTile(title: "Avg heart rate", value: v.heartRate.map { "\(Int($0)) bpm" } ?? "—", symbol: "heart.fill", tint: .pink)
                MetricTile(title: "HRV", value: v.hrv.map { "\(Int($0)) ms" } ?? "—", symbol: "waveform.path.ecg", tint: .pink)
                MetricTile(title: "Respiratory", value: v.respiratoryRate.map { String(format: "%.1f /min", $0) } ?? "—", symbol: "lungs.fill", tint: .cyan)
                MetricTile(title: "Blood oxygen", value: v.oxygen.map { "\(Int($0.rounded()))%" } ?? "—", symbol: "drop.fill", tint: .cyan)
            }
        }
        .card()
    }

    private func breakdown(_ score: SleepScore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Score breakdown")
            ForEach(score.components) { c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(c.name).font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(c.points.rounded()))/\(Int(c.maxPoints))")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    ProgressView(value: c.points / c.maxPoints)
                        .tint(Theme.scoreColor(Int(c.points / c.maxPoints * 100)))
                    Text(c.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private var historyCard: some View {
        let avg = health.history.map(\.score).reduce(0, +) / max(health.history.count, 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Last 7 nights", subtitle: "Average \(avg)")
            Chart(health.history) { item in
                BarMark(x: .value("Night", item.date, unit: .day), y: .value("Score", item.score), width: .ratio(0.55))
                    .foregroundStyle(Theme.scoreColor(item.score)
                        .opacity(Calendar.current.isDate(item.date, inSameDayAs: health.selectedDay) ? 1 : 0.55))
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        Text("\(item.score)").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .frame(height: 150)
        }
        .card()
    }
}
