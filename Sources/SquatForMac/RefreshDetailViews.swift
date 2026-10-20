import SwiftUI
import AppKit

struct RefreshResult: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var history: WorkoutHistory
    @ObservedObject var settings: AppSettings
    var body: some View {
        let result = coordinator.result
        ZStack(alignment: .topLeading) {
            Text(title).font(RefreshDesign.font(40, medium: true, japanese: settings.isJapanese)).frame(width: 342, height: 48).position(x: 200.5, y: 241)
            Text("\(result?.count ?? 0)").font(RefreshDesign.font(128, medium: true)).frame(width: 240, height: 153).position(x: 200.5, y: 361.5)
            Button { coordinator.goHome() } label: { Text("Home").font(RefreshDesign.font(20, medium: true)).tracking(0.4).foregroundStyle(.white).frame(width: 130, height: 30).background(RefreshDesign.blue, in: Capsule()) }
                .buttonStyle(.plain).position(x: 201, y: 473).accessibilityIdentifier("refresh.resultHome")
            VStack(spacing: 10) {
                if result?.isDemo == true { Text(settings.t("デモの回数は記録されません", "Demo — not recorded")) }
                else if history.saveState == .pending { Text(settings.t("保存中…", "Saving…")) }
                else if history.saveState == .failed {
                    Text(settings.t("記録を保存できませんでした。", "Could not save your record."))
                    Button(settings.t("保存を再試行", "Retry saving")) { coordinator.retrySave() }
                }
            }.font(RefreshDesign.font(14, japanese: settings.isJapanese)).frame(width: 350).position(x: 201, y: 540)
        }.frame(width: 402, height: 706)
    }
    private var title: String {
        guard let result = coordinator.result else { return settings.t("またいつでもどうぞ", "Ready when you are") }
        if result.count == 0 { return settings.t("またいつでもどうぞ", "Ready when you are") }
        if !result.completed { return settings.t("ここまでおつかれさま！", "Nice work!") }
        return settings.t("おつかれさま！", "You did it !!")
    }
}

struct RefreshHistory: View {
    @ObservedObject var history: WorkoutHistory
    @ObservedObject var settings: AppSettings
    @ObservedObject var usage: RefreshUsageService
    let dates: Namespace.ID
    @State private var year: Int
    @State private var selectingYear = false
    @State private var columns: [[DayCount]] = []
    @State private var periodStart = Date()
    @State private var periodEnd = Date()
    @State private var maxCount = 1
    @State private var hovered: Date?
    @FocusState private var focusedDay: Date?
    init(history: WorkoutHistory,settings: AppSettings,usage: RefreshUsageService,dates: Namespace.ID) {
        self.history = history; self.settings = settings; self.usage = usage; self.dates = dates
        let c = Calendar.current.dateComponents([.year,.month],from: history.currentDate)
        _year = State(initialValue: (c.year ?? 2026)+((c.month ?? 1) >= 11 ? 1 : 0))
    }
    private var calendar: Calendar { ProgressCalendarModel.localCalendar(timeZone: history.calendarTimeZone) }
    private var selected: Date? { hovered ?? focusedDay }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Button { selectingYear = true } label: { Text(String(year)).font(RefreshDesign.font(24,medium: true)) }
                .buttonStyle(.plain).frame(width: 100,height: 29,alignment: .leading).position(x: 76,y: 151.5)
                .popover(isPresented: $selectingYear) {
                    ScrollView { VStack { ForEach(years,id: \.self) { y in Button(String(y)) { year = y; selectingYear = false }.buttonStyle(.plain).padding(6) } }.padding(12) }.frame(width: 140,height: 200)
                }
            Text(settings.t("日別", "Daily")).font(RefreshDesign.font(12,medium: true,japanese: settings.isJapanese)).frame(width: 60,height: 14,alignment: .trailing).position(x: 746,y: 157)
            summary
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .top,spacing: 2) {
                            ForEach(columns.indices,id: \.self) { col in
                                VStack(spacing: 2) { ForEach(columns[col]) { day in cell(day) } }.frame(width: 13).id(col)
                            }
                        }
                        ForEach(0..<12) { index in
                            let m = (index+10)%12+1
                            let y = m >= 11 ? year-1 : year
                            if let d = calendar.date(from: DateComponents(year: y,month: m,day: 1)), let col = columns.firstIndex(where: { $0.contains { calendar.isDate($0.date,inSameDayAs: d) } }) {
                                Button { proxy.scrollTo(col,anchor: .leading) } label: { Text(month(m)).font(RefreshDesign.font(16,medium: true,japanese: settings.isJapanese)).foregroundStyle(RefreshDesign.secondary).frame(width: 60,height: 19,alignment: .leading) }
                                    .buttonStyle(.plain).position(x: CGFloat(col)*15+30,y: 124.5)
                            }
                        }
                    }.frame(width: CGFloat(columns.count)*15-2,height: 134,alignment: .topLeading)
                }.scrollIndicators(.hidden).frame(width: 748,height: 134).position(x: 402,y: 323)
                    .onAppear {
                        rebuild()
                        if Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27", CommandLine.arguments.contains("--review-selected-day") {
                            focusedDay = calendar.startOfDay(for: history.currentDate)
                        }
                        DispatchQueue.main.async { scrollToToday(proxy) }
                    }
                    .onChange(of: year) { _ in hovered = nil; focusedDay = nil; rebuild(); proxy.scrollTo(0,anchor: .leading) }
                    .onChange(of: history.historyRevision) { _ in rebuild() }
                    .onChange(of: focusedDay) { d in if let d,let c = columns.firstIndex(where: { $0.contains { $0.date == d } }) { proxy.scrollTo(c,anchor: .center) } }
            }
        }.frame(width: 802,height: 481)
            .onExitCommand { hovered = nil; focusedDay = nil }
    }
    private var summary: some View {
        let times = usage.summary(from: periodStart,through: periodEnd,day: selected,calendar: calendar)
        let reps = selected.map { history.count(on: $0) } ?? columns.flatMap { $0 }.filter { $0.date >= periodStart && $0.date <= periodEnd }.reduce(0) { $0+$1.count }
        return ZStack(alignment: .topLeading) {
            Text(selected.map(dateTitle) ?? "Total").font(RefreshDesign.font(40,medium: true)).frame(width: 350,height: 48,alignment: .leading).position(x: 201,y: 210)
            metric("ChatGPT/Claude",value: times.0,x: 473.5,width: 103)
            metric("Desk time",value: times.1,x: 593.5,width: 103)
            metric("Squad reps",value: String(format: "%03d",reps),x: 713.5,width: 63)
        }
    }
    private func metric(_ title: String,value: String,x: CGFloat,width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(Color(white: 0.85)).frame(width: 10,height: 10).position(x: x-8,y: 188)
            Text(title).font(RefreshDesign.font(12,medium: true)).foregroundStyle(RefreshDesign.secondary).frame(width: width,height: 14,alignment: .leading).position(x: x+width/2,y: 188)
            Text(value).font(RefreshDesign.font(32,medium: true)).lineLimit(1).minimumScaleFactor(0.55).frame(width: width,height: 38,alignment: .leading).position(x: x+width/2,y: 219)
        }
    }
    private func dateTitle(_ date: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = history.calendarTimeZone; f.dateFormat = "d MMM"; return f.string(from: date) }
    private var years: [Int] {
        let c = calendar.dateComponents([.year,.month],from: history.currentDate)
        let latest = (c.year ?? 2026)+((c.month ?? 1) >= 11 ? 1 : 0)
        let earliest = history.sessions.map { calendar.component(.year,from: $0.startedAt) }.min() ?? latest
        return Array(min(earliest,latest)...latest).reversed()
    }
    private func month(_ m: Int) -> String { settings.isJapanese ? "\(m)月" : ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][m-1] }
    private func cell(_ day: DayCount) -> some View {
        let inside = day.date >= periodStart && day.date <= periodEnd
        let count = inside && day.date <= history.currentDate ? day.count : 0
        let color = count > 0 ? SquatDesign.heat(min(5,max(1,Int(ceil(5*Double(count)/Double(maxCount)))))) : Color(white: 240/255)
        return RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 13,height: 13)
            .matchedGeometryEffect(id: calendar.startOfDay(for: day.date),in: dates,isSource: false)
            .focusable(inside).focused($focusedDay,equals: day.date)
            .onMoveCommand { direction in
                let offset: Int
                switch direction { case .left: offset = -7; case .right: offset = 7; case .up: offset = -1; case .down: offset = 1; default: return }
                if let next = calendar.date(byAdding: .day,value: offset,to: day.date),next >= periodStart,next <= periodEnd { focusedDay = next }
            }
            .onHover { over in if inside { hovered = over ? day.date : nil } }
            .onTapGesture { if inside { focusedDay = day.date } }
            .help(inside ? "\(day.date.formatted(date: .complete,time: .omitted)), \(count)" : settings.t("期間外", "Outside this period"))
            .accessibilityLabel(inside ? "\(day.date.formatted(date: .complete,time: .omitted)), \(count)" : settings.t("期間外", "Outside this period"))
    }
    private func rebuild() {
        guard let start = calendar.date(from: DateComponents(year: year-1,month: 11,day: 1)),let end = calendar.date(from: DateComponents(year: year,month: 10,day: 31)),let first = calendar.date(byAdding: .day,value: -(calendar.component(.weekday,from: start)-1),to: start) else { return }
        periodStart = start; periodEnd = end
        var d = first; var output: [[DayCount]] = []
        while d <= end {
            var column: [DayCount] = []
            for _ in 0..<7 {
                column.append(DayCount(date: d,count: d >= start && d <= end ? history.count(on: d) : 0))
                d = calendar.date(byAdding: .day,value: 1,to: d)!
            }
            output.append(column)
        }
        columns = output; maxCount = max(1,output.flatMap { $0 }.map(\.count).max() ?? 1)
    }
    private func scrollToToday(_ proxy: ScrollViewProxy) {
        if CommandLine.arguments.contains("--ui-fixture=refresh-reference") { proxy.scrollTo(0,anchor: .leading); return }
        let i = columns.firstIndex { $0.contains { calendar.isDate($0.date,inSameDayAs: history.currentDate) } } ?? 0
        proxy.scrollTo(i,anchor: .trailing)
    }
}
