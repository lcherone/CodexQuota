import Charts
import CodexQuotaCore
import SwiftUI

struct UsageChartView: View {
    var buckets: [DailyBucket]
    @Environment(\.colorScheme) private var scheme
    @State private var allHistory = false
    @State private var hoveredDate: Date?

    private struct Reading: Identifiable {
        var date: Date
        var tokens: Int64
        var id: Date { date }
    }

    private var readings: [Reading] {
        var values: [Date: Int64] = [:]
        for bucket in buckets where bucket.tokens >= 0 {
            let parts = bucket.startDate.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = LondonClock.calendar().date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { continue }
            values[date] = bucket.tokens
        }
        let ordered = values.map { Reading(date: $0.key, tokens: $0.value) }.sorted { $0.date < $1.date }
        return allHistory ? ordered : Array(ordered.suffix(14))
    }

    private var highlighted: Reading? {
        guard let hoveredDate else { return readings.last }
        return readings.min { abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate)) }
    }

    private func dateLabel(_ date: Date, includesYear: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = LondonClock.zone
        formatter.dateFormat = includesYear ? "d MMM yyyy" : "d MMM"
        return formatter.string(from: date)
    }

    var body: some View {
        let palette = Palette.current(scheme)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Daily tokens").font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("Chart history", selection: $allHistory) {
                    Text("Latest 14").tag(false)
                    Text("All history").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
            }
            if let first = readings.first, let last = readings.last {
                let crossesYear = LondonClock.calendar().component(.year, from: first.date) != LondonClock.calendar().component(.year, from: last.date)
                Text("\(readings.count) records · \(dateLabel(first.date, includesYear: crossesYear)) – \(dateLabel(last.date, includesYear: crossesYear))")
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
                Chart(readings) { reading in
                    BarMark(
                        x: .value("Date", reading.date, unit: .day),
                        y: .value("Tokens", Double(reading.tokens))
                    )
                    .foregroundStyle(reading.id == highlighted?.id ? palette.warning : palette.accent)
                    .cornerRadius(2)
                    .accessibilityLabel(LondonClock.dayLabel(reading.date))
                    .accessibilityValue("\(UsageFormatting.exact(reading.tokens)) tokens")
                }
                .environment(\.calendar, LondonClock.calendar())
                .environment(\.timeZone, LondonClock.zone)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(palette.hairline)
                        AxisValueLabel {
                            if let tokens = value.as(Double.self) {
                                Text(tokens.formatted(.number.notation(.compactName)))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case let .active(location):
                                    if let frame = proxy.plotFrame {
                                        let plot = geometry[frame]
                                        hoveredDate = plot.contains(location) ? proxy.value(atX: location.x - plot.minX) : nil
                                    }
                                case .ended: hoveredDate = nil
                                }
                            }
                    }
                }
                .frame(height: 110)
                if let highlighted {
                    Text("\(dateLabel(highlighted.date, includesYear: true)) · \(UsageFormatting.exact(highlighted.tokens)) tokens")
                        .font(.system(size: 11)).monospacedDigit()
                }
                Text("Missing dates have no reading.")
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
            } else {
                Text("No daily token totals supplied.")
                    .font(.system(size: 12)).foregroundStyle(palette.secondary)
            }
        }
        .padding(.bottom, 12)
    }
}
