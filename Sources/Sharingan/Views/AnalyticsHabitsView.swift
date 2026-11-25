import SwiftUI
import SharinganCore

/// Dashboard ▸ Habits: the full habit report — KPIs, charts, an eyes strip and
/// per-habit rows.
struct AnalyticsHabitsView: View {
    @ObservedObject private var store = TaskStore.shared
    @State private var days = 30
    private let calendar = Calendar.current

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let report = store.habitReport(days: days, today: today, calendar: calendar)
        VStack(alignment: .leading, spacing: 16) {
            if report.rows.isEmpty {
                VStack(spacing: 10) {
                    HabitEyeView(stage: .dormant, diameter: 48)
                    Text("No habits yet — turn on Habit in any task")
                        .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 48)
            } else {
                HabitRangePicker(days: $days)
                HabitKPIRow(report: report, calendar: calendar)
                HabitChartsRow(report: report, calendar: calendar)
                HabitCard(title: "Eyes") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.lg) {
                            ForEach(report.rows) { row in
                                VStack(spacing: 6) {
                                    HabitEyeView(stage: row.eye, diameter: 44)
                                    Text(row.title).font(.dsCaption).foregroundStyle(Color.dsPrimary).lineLimit(1)
                                    Text(row.eye.awakened).font(.dsMicro).foregroundStyle(Color.habitRed)
                                }
                                .frame(width: 96)
                            }
                        }
                    }
                }
                VStack(spacing: DS.Space.sm) {
                    ForEach(report.rows) { row in habitRow(row) }
                }
            }
        }
    }

    private func habitRow(_ row: HabitReportRow) -> some View {
        HStack(spacing: DS.Space.md) {
            HabitEyeView(stage: row.eye, diameter: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).font(.dsCallout).foregroundStyle(Color.dsPrimary).lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.dsFillStrong)
                        Capsule().fill(Color.habitRed).frame(width: g.size.width * CGFloat(row.rate))
                    }
                }
                .frame(height: 6)
            }
            Text(HabitFormat.percent(row.rate)).font(.dsCallout).foregroundStyle(Color.dsPrimary)
                .frame(width: 48, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 1) {
                Text("🔥 \(row.currentStreak)").font(.dsCaption).foregroundStyle(Color.dsPrimary)
                Text("best \(row.longestStreak)").font(.dsMicro).foregroundStyle(Color.dsSecondary)
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(DS.Space.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(Color.dsFill))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(Color.dsHairline, lineWidth: 1))
    }
}
