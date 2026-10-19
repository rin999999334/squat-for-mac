import SwiftUI

struct SquatProgressView: View {
    @ObservedObject var history: WorkoutHistory
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: ProgressSelection
    @StateObject private var dataCache = ProgressDataCache()
    @State private var hover = ProgressHoverState()
    @State private var renderCache = ProgressRenderCache()

    var body: some View {
        let model = dataCache.model(history: history, period: selection.period, anchor: selection.anchor, today: history.currentDate)
        let snapshot = renderCache.snapshot(model: model, revision: history.historyRevision, japanese: settings.isJapanese,
                                             locale: settings.locale, historyID: ObjectIdentifier(history))
        VStack(spacing: 10) {
            SquatSegmentedControl(options: [ProgressPeriod.week, .month], selected: selection.period,
                title: { $0 == .week ? "Weekly" : "Monthly" }, identifier: { "progress-tab-\($0.rawValue)" }, select: changePeriod)
                .frame(width: 132, height: 24)
            HStack {
                Button { navigate(-1, model) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
                    .accessibilityLabel(settings.t("前の期間", "Previous period"))
                Spacer(minLength: 0)
                if selection.period == .week { Text(snapshot.title).font(SquatDesign.number(12)).foregroundStyle(.black).lineLimit(1) }
                else {
                    let parts = snapshot.title.split(separator: " ")
                    (Text(String(parts.first ?? "")).font(SquatDesign.text(11)) + Text(" " + String(parts.last ?? "")).font(SquatDesign.number(12)))
                        .foregroundStyle(.black).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { navigate(1, model) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28) }
                    .disabled(!model.canAdvance).accessibilityLabel(settings.t("次の期間", "Next period"))
            }.buttonStyle(.plain).foregroundStyle(SquatDesign.muted)
            Group {
                if selection.period == .week {
                    ProgressWeekChart(snapshot: snapshot, selectedDate: selection.selectedDate, hover: hover, select: select)
                } else {
                    ProgressMonthGrid(snapshot: snapshot, selectedDate: selection.selectedDate, hover: hover,
                                      select: select, move: { move($0, model) })
                }
            }.frame(height: 148, alignment: .top)
                .coordinateSpace(name: "progress-chart")
                .overlay(alignment: .topLeading) { ProgressHoverDetail(hover: hover) }
        }.padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 20)
            .frame(maxWidth: .infinity).frame(height: 240, alignment: .top)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain).accessibilityIdentifier("squat-progress-card")
            .accessibilityValue(diagnostics)
            .onChange(of: history.historyRevision) { _ in hover.clear() }
    }
    private var diagnostics: String {
        guard CommandLine.arguments.contains("--ui-test") || Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27" else { return "" }
        return "models=\(dataCache.modelBuildCount), labels=\(renderCache.snapshotBuildCount), dates=\(renderCache.dayLabelBuildCount)"
    }
    private func changePeriod(_ period: ProgressPeriod) {
        guard period != selection.period else { return }
        hover.clear()
        let model = dataCache.model(history: history, period: period, anchor: selection.anchor, today: history.currentDate)
        selection.update(period: period, selectedDate: model.clampedSelection(selection.selectedDate))
    }
    private func navigate(_ amount: Int, _ model: ProgressCalendarModel) {
        guard amount < 0 || model.canAdvance else { return }
        hover.clear()
        let anchor = model.shifted(by: amount)
        selection.update(anchor: anchor, selectedDate: min(model.today, ProgressCalendarModel.bounds(period: model.period, anchor: anchor, calendar: model.calendar).0))
    }
    private func select(_ date: Date) { selection.update(selectedDate: date) }
    private func move(_ direction: MoveCommandDirection, _ model: ProgressCalendarModel) {
        let date = progressMovedDate(direction, model: model, selected: selection.selectedDate)
        selection.update(anchor: date < model.start || date > model.end ? date : nil, selectedDate: date)
    }
}
