import Foundation
import SwiftUI

/// Calendar arithmetic deliberately uses days, including across daylight-saving changes.
struct ContributionCalendarModel {
    struct Day: Identifiable {
        let date: Date
        let count: Int
        let isFuture: Bool
        var id: Date { date }
        var intensity: Int { ContributionCalendarModel.intensity(for: count) }
    }

    let calendar: Calendar
    let today: Date
    let days: [Day]
    let monthLabels: [String]
    var firstDate: Date { days[0].date }
    var lastDate: Date { days[90].date }

    init(referenceDate: Date = Date(), calendar: Calendar = .current, counts: [DayCount] = []) {
        self.calendar = calendar
        let referenceDay = calendar.startOfDay(for: referenceDate)
        today = referenceDay
        let weekdayOffset = calendar.component(.weekday, from: referenceDay) - 1
        let sunday = calendar.date(byAdding: .day, value: -weekdayOffset, to: referenceDay)!
        let start = calendar.date(byAdding: .day, value: -84, to: sunday)!
        let countByDate = Dictionary(counts.map { (calendar.startOfDay(for: $0.date), max(0, $0.count)) }, uniquingKeysWith: +)
        days = (0..<91).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            let future = date > referenceDay
            return Day(date: date, count: future ? 0 : countByDate[date, default: 0], isFuture: future)
        }
        monthLabels = (0..<13).map { week in
            let weekStart = calendar.date(byAdding: .day, value: week * 7, to: start)!
            let dates = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: weekStart)! }
            if week == 0 { return "\(calendar.component(.month, from: weekStart))月" }
            guard let monthStart = dates.first(where: { calendar.component(.day, from: $0) == 1 }) else { return "" }
            return "\(calendar.component(.month, from: monthStart))月"
        }
    }

    func dayLabel(_ date: Date) -> String {
        "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
    }

    func accessibleDate(_ date: Date) -> String {
        "\(calendar.component(.year, from: date))年\(dayLabel(date))"
    }

    static func intensity(for count: Int) -> Int {
        switch count {
        case ...0: return 0
        case 1...5: return 1
        case 6...15: return 2
        case 16...30: return 3
        default: return 4
        }
    }
}

struct ContributionCalendar: View {
    @ObservedObject var history: WorkoutHistory
    @State private var selectedDate: Date?
    private let ink = Color(red: 0.16, green: 0.19, blue: 0.24)
    private let blue = Color(red: 0.16, green: 0.48, blue: 0.96)

    private func fill(for intensity: Int) -> Color {
        switch intensity {
        case 1: return blue.opacity(0.22)
        case 2: return blue.opacity(0.43)
        case 3: return blue.opacity(0.69)
        case 4: return blue
        default: return ink.opacity(0.065)
        }
    }

    var body: some View {
        let range = ContributionCalendarModel()
        let model = ContributionCalendarModel(referenceDate: range.today, counts: history.dayCounts(from: range.firstDate, through: range.today))
        let selected = model.days.first { model.calendar.isDate($0.date, inSameDayAs: selectedDate ?? model.today) } ?? model.days.first { $0.date == model.today }!
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("運動カレンダー").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("最近の13週間").font(.system(size: 11)).foregroundStyle(ink.opacity(0.52))
            }
            calendarGrid(model)
            HStack(spacing: 6) {
                Text("\(model.dayLabel(selected.date))").foregroundStyle(ink.opacity(0.55))
                Text("\(selected.count) 回").fontWeight(.semibold).monospacedDigit()
                Spacer(minLength: 8)
                Text("少").foregroundStyle(ink.opacity(0.45))
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 3).fill(fill(for: level)).frame(width: 10, height: 10)
                }
                Text("多").foregroundStyle(ink.opacity(0.45))
            }
            .font(.system(size: 11))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(model.accessibleDate(selected.date))、\(selected.count)回。色が濃い日ほど回数が多い")
        }
        .foregroundStyle(ink)
    }

    private func calendarGrid(_ model: ContributionCalendarModel) -> some View {
        GeometryReader { geometry in
            let gap: CGFloat = 5
            let labelWidth: CGFloat = 18
            let gridWidth = max(130, geometry.size.width - labelWidth - 8)
            let side = min(16, max(6, (gridWidth - gap * 12) / 13))
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: gap) {
                    Color.clear.frame(height: 18)
                    ForEach(0..<7) { weekday in
                        Text(weekday.isMultiple(of: 2) ? ["日", "月", "火", "水", "木", "金", "土"][weekday] : "")
                            .font(.system(size: 9)).foregroundStyle(ink.opacity(0.42))
                            .frame(width: labelWidth, height: side)
                    }
                }
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<13) { week in
                        VStack(spacing: gap) {
                            Text(model.monthLabels[week])
                                .font(.system(size: 9)).foregroundStyle(ink.opacity(0.50))
                                .fixedSize().frame(width: side, height: 18, alignment: .leading)
                            ForEach(0..<7) { weekday in
                                let day = model.days[week * 7 + weekday]
                                let isSelected = model.calendar.isDate(day.date, inSameDayAs: selectedDate ?? model.today)
                                Button { selectedDate = day.date } label: {
                                    RoundedRectangle(cornerRadius: min(5, side / 4), style: .continuous)
                                        .fill(day.isFuture ? ink.opacity(0.025) : fill(for: day.intensity))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: min(5, side / 4), style: .continuous)
                                                .stroke(isSelected ? blue.opacity(0.75) : .white.opacity(day.isFuture ? 0.2 : 0.65), lineWidth: isSelected ? 1.5 : 0.7)
                                        }
                                        .frame(width: side, height: side)
                                }
                                .buttonStyle(.plain)
                                .disabled(day.isFuture)
                                .help(day.isFuture ? "\(model.dayLabel(day.date))：これから" : "\(model.dayLabel(day.date))：\(day.count)回")
                                .accessibilityLabel(day.isFuture ? "\(model.accessibleDate(day.date))、これから" : "\(model.accessibleDate(day.date))、\(day.count)回")
                                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 165)
        .frame(maxWidth: .infinity)
    }
}
