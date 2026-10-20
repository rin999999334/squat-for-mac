import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TodayCardSnapshot {
    struct Day { let date: Date; let count: Int; let today: Bool }
    let japanese: Bool
    let title: String
    let ai: String
    let desk: String
    let reps: String
    let days: [Day]
    @MainActor static func make(history: WorkoutHistory, usage: RefreshUsageService) -> Self {
        let calendar = ProgressCalendarModel.localCalendar(timeZone: history.calendarTimeZone)
        let today = calendar.startOfDay(for: history.currentDate)
        let start = calendar.date(byAdding: .day, value: -(calendar.component(.weekday,from: today)-1), to: today)!
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = history.calendarTimeZone; f.dateFormat = "d MMM"
        return Self(japanese: usage.settings.isJapanese,title: "Today・\(f.string(from: today))", ai: usage.aiDisplay, desk: usage.deskDisplay,
                    reps: String(format: "%03d",history.todayReps), days: (0..<7).map { i in
            let d = calendar.date(byAdding: .day,value: i,to: start)!
            return Day(date: d,count: d <= today ? history.count(on: d) : 0,today: d == today)
        })
    }
}
struct TodayCardView: View {
    let snapshot: TodayCardSnapshot
    var showShare = true
    var dates: Namespace.ID? = nil
    var share: () -> Void = {}
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.1))
            Text(snapshot.title).font(RefreshDesign.font(24,medium: true)).foregroundStyle(.white)
                .frame(width: 290,height: 29,alignment: .leading).position(x: 160,y: 24.5)
            if showShare { Button(action: share) { Image(systemName: "square.and.arrow.up").resizable().scaledToFit().frame(width: 16,height: 16).frame(width: 32,height: 32).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(.white).position(x: 338,y: 24).accessibilityLabel(snapshot.japanese ? "今日の記録をシェア" : "Share today’s record") }
            RefreshCardMetrics(ai: snapshot.ai, desk: snapshot.desk, reps: snapshot.reps)
            ForEach(snapshot.days.indices,id: \.self) { i in
                let day = snapshot.days[i]
                let lx: [CGFloat] = [42,91.5,140,188.5,237.5,283.5,328]
                let cx: [CGFloat] = [42.5,91.5,140.5,188.5,237.5,283.5,328.5]
                Text(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][i]).font(RefreshDesign.font(16)).foregroundStyle(day.today ? .white : RefreshDesign.secondary).position(x: lx[i],y: 120.5)
                dayCircle(day).frame(width: 25,height: 25).position(x: cx[i],y: 151.5)
                    .help("\(day.date.formatted(date: .complete,time: .omitted)) · \(day.count)")
            }
        }.frame(width: 362,height: 187).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    @ViewBuilder private func dayCircle(_ day: TodayCardSnapshot.Day) -> some View {
        if let dates { circle(day).matchedGeometryEffect(id: day.date,in: dates) }
        else { circle(day) }
    }
    private func circle(_ day: TodayCardSnapshot.Day) -> some View {
        ZStack {
            if day.count > 0 { Image(systemName: "checkmark.circle.fill").resizable().symbolRenderingMode(.palette).foregroundStyle(.white, RefreshDesign.blue) }
            else if day.today { Circle().fill(.white) }
            else { Circle().stroke(.white,style: StrokeStyle(lineWidth: 1,dash: [2,2])) }
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(day.date.formatted(date: .complete,time: .omitted)), \(day.count)")
    }
}

/// Shared metric content, with separate reference geometry for Today and Total.
struct RefreshCardMetrics: View {
    enum Layout { case today, total }
    var layout: Layout = .today
    private var widths: [CGFloat] { layout == .total ? [112,75,87] : [115,90,87] }
    private var rowWidth: CGFloat { widths.reduce(0,+) + 40 }
    private var rowHeight: CGFloat { layout == .total ? 43 : 48 }
    private var rowTop: CGFloat { layout == .total ? 124 : 54 }
    let ai: String
    let desk: String
    let reps: String
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            metric("ChatGPT/Claude", value: ai, width: widths[0], icon: "clock")
            metric("Desk time", value: desk, width: widths[1], icon: "clock")
            metric("Squad reps", value: reps, width: widths[2], icon: "person")
        }.frame(width: rowWidth, height: rowHeight, alignment: .topLeading).position(x: 15+rowWidth/2, y: rowTop+rowHeight/2)
    }
    private func metric(_ title: String, value: String, width: CGFloat, icon: String) -> some View {
        VStack(alignment: .leading, spacing: layout == .total ? 2 : 4) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 10)).frame(width: 10, height: 10)
                Text(title).font(RefreshDesign.font(14, medium: true)).fixedSize(horizontal: true, vertical: false)
            }.foregroundStyle(RefreshDesign.secondary).frame(width: width, height: 17, alignment: .leading)
            Text(value).font(RefreshDesign.font(20, medium: true)).foregroundStyle(Color(white: 0.98))
                .lineLimit(1).minimumScaleFactor(0.6).frame(width: width-13, height: 24, alignment: .leading).padding(.leading,13)
        }.frame(width: width, alignment: .leading)
    }
}

struct TotalCardSnapshot {
    let japanese: Bool
    let elapsedDays: Int
    let bestStreak: Int
    let ai: String
    let desk: String
    let reps: String
    @MainActor static func make(history: WorkoutHistory, usage: RefreshUsageService) -> Self {
        let total = usage.lifetimeSummary()
        let days = history.shareDayStatistics()
        return Self(japanese: usage.settings.isJapanese, elapsedDays: days.elapsedDays, bestStreak: days.bestStreak, ai: total.ai, desk: total.desk, reps: String(format: "%03d", history.lifetimeReps))
    }
}
struct TotalCardView: View {
    let snapshot: TotalCardSnapshot
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.1))
            Text("Total").font(RefreshDesign.font(24, medium: true)).foregroundStyle(.white)
                .frame(width: 74, height: 29, alignment: .leading).position(x: 52, y: 24.5)
            dayStat(snapshot.elapsedDays, title: snapshot.japanese ? "経過日数" : "Since start", x: 15, width: 112)
            dayStat(snapshot.bestStreak, title: snapshot.japanese ? "最長連続" : "Best streak", x: 147, width: 112)
            RefreshCardMetrics(layout: .total, ai: snapshot.ai, desk: snapshot.desk, reps: snapshot.reps)
        }.frame(width: 362, height: 187).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func dayStat(_ value: Int, title: String, x: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(value)").font(RefreshDesign.font(48, medium: true)).lineLimit(1).minimumScaleFactor(0.35)
                Text(value == 1 ? "day" : "days").font(RefreshDesign.font(20, medium: true))
            }.foregroundStyle(.white).frame(width: width, height: 57, alignment: .leading).position(x: x+width/2, y: 92.5)
            Text(title).font(RefreshDesign.font(14, medium: true, japanese: snapshot.japanese))
                .foregroundStyle(RefreshDesign.secondary).frame(width: width, height: 17, alignment: .leading).position(x: x+width/2, y: 55.5)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.japanese ? "\(title)、\(value)日" : "\(title), \(value) \(value == 1 ? "day" : "days")")
    }
}

/// Used only during real pending work, never to delay a ready screen.
struct RefreshLoadingPlaceholder: View {
    let japanese: Bool
    @State private var visible = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.92))
            RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.83)).frame(width: 150,height: 24).offset(x: 15,y: 12)
            HStack(spacing: 20) {
                ForEach(0..<3) { _ in VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).frame(width: 85,height: 17)
                    RoundedRectangle(cornerRadius: 3).frame(width: 85,height: 24)
                } }
            }.foregroundStyle(Color(white: 0.83)).offset(x: 15,y: 54)
        }.frame(width: 362,height: 187).opacity(visible ? 1 : 0)
            .accessibilityElement(children: .ignore).accessibilityLabel(japanese ? "読み込み中" : "Loading")
            .task {
                do { try await Task.sleep(nanoseconds: 150_000_000); visible = true } catch { }
            }
    }
}

@MainActor final class RefreshShareController: ObservableObject {
    @Published var image: NSImage?
    @Published private(set) var isPreparing = false
    @Published private(set) var isTotal = false
    @Published var error: String?
    private var png: Data?
    private var url: URL?
    private var picker: NSSharingServicePicker?
    private var generation = UUID()
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SquatReviewV27-Share",isDirectory: true)
    init() { try? FileManager.default.removeItem(at: folder) }
    func prepare(_ snapshot: TodayCardSnapshot) async {
        await render(TodayCardView(snapshot: snapshot, showShare: false), total: false)
    }
    func prepare(_ snapshot: TotalCardSnapshot) async {
        await render(TotalCardView(snapshot: snapshot), total: true)
    }
    private func render<V: View>(_ view: V, total: Bool) async {
        let request = UUID(); generation = request
        isTotal = total; isPreparing = true; image = nil; png = nil; url = nil; error = nil
        defer { if generation == request { isPreparing = false } }
        await Task.yield()
        guard generation == request else { return }
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light)); renderer.scale = 2
        guard let cg = renderer.cgImage else { error = "Could not create the image. Please try again."; return }
        let data = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let context = CGContext(data: nil,width: 724,height: 374,bitsPerComponent: 8,bytesPerRow: 0,space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(cg,in: CGRect(x: 0,y: 0,width: 724,height: 374))
            guard let image = context.makeImage() else { return nil }
            return NSBitmapImageRep(cgImage: image).representation(using: .png,properties: [:])
        }.value
        guard generation == request else { return }
        guard let data, let image = NSImage(data: data) else { error = "Could not create the image. Please try again."; return }
        do {
            try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(UUID().uuidString+".png"); try data.write(to: url)
            self.url = url; png = data; image.size = NSSize(width: 362,height: 187); self.image = image
        } catch { self.error = error.localizedDescription }
    }
    func cancel() { generation = UUID(); isPreparing = false; image = nil; png = nil; url = nil }
    func writeReviewPNG(to url: URL) throws {
        guard Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27", url.path.hasPrefix("/private/tmp/"), let png else { return }
        try png.write(to: url)
    }
    func copyImage() { guard let png else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setData(png,forType: .png) }
    func save() {
        guard let png else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = isTotal ? "Squat-Total.png" : "Squat-Today.png"
        if panel.runModal() == .OK, let url = panel.url { do { try png.write(to: url) } catch { self.error = error.localizedDescription } }
    }
    func share(githubURL: URL?) {
        guard let url, let view = NSApp.keyWindow?.contentView else { return }
        guard let githubURL else { return }
        picker = NSSharingServicePicker(items: [url, githubURL]); picker?.show(relativeTo: CGRect(x: view.bounds.midX,y: view.bounds.midY,width: 1,height: 1),of: view,preferredEdge: .minY)
    }
}
