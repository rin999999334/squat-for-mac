import SwiftUI
import Combine

/// Charts retain this object without subscribing; only the overlaid tooltip observes it.
final class ProgressHoverState: ObservableObject {
    struct Feedback: Equatable { let day: ProgressDayPresentation; let point: CGPoint }
    @Published private(set) var feedback: Feedback?
    var day: ProgressDayPresentation? { feedback?.day }
    func show(_ day: ProgressDayPresentation, at point: CGPoint) {
        let next = Feedback(day: day, point: point)
        if feedback != next { feedback = next }
    }
    func clear(if date: Date? = nil) {
        if feedback != nil && (date == nil || day?.date == date) { feedback = nil }
    }
}

struct ProgressHoverDetail: View {
    @ObservedObject var hover: ProgressHoverState
    var body: some View {
        GeometryReader { geometry in
            if let feedback = hover.feedback {
                Text(feedback.day.detailLabel).font(SquatDesign.ui(11)).foregroundStyle(.black)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .frame(width: min(190, geometry.size.width))
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .position(x: min(max(95, feedback.point.x), max(95, geometry.size.width - 95)),
                              y: max(8, feedback.point.y - 18))
                    .accessibilityIdentifier("progress-day-detail")
            }
        }.allowsHitTesting(false).transaction { $0.animation = nil }
    }
}

private struct ActivityDayButton<Content: View>: View {
    let day: ProgressDayPresentation
    let hover: ProgressHoverState
    let select: (Date) -> Void
    @ViewBuilder let content: () -> Content
    @FocusState private var focused: Bool
    var body: some View {
        GeometryReader { geometry in
            Button { select(day.date); reveal(geometry) } label: { content().frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle()) }
                .buttonStyle(.plain).disabled(day.future).focused($focused)
                .accessibilityLabel(day.accessibilityLabel)
                .onHover { over in
                    if over || focused { reveal(geometry) } else { hover.clear(if: day.date) }
                }
                .onChange(of: focused) { value in if value { reveal(geometry) } else { hover.clear(if: day.date) } }
        }
    }
    private func reveal(_ geometry: GeometryProxy) {
        let rect = geometry.frame(in: .named("progress-chart"))
        hover.show(day, at: CGPoint(x: rect.midX, y: rect.minY))
    }
}

struct ProgressWeekChart: View {
    let snapshot: ProgressRenderSnapshot
    let selectedDate: Date
    let hover: ProgressHoverState
    let select: (Date) -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(snapshot.days) { day in
                VStack(spacing: 12) {
                    Text(day.weekdayLabel).font(SquatDesign.text(8)).foregroundStyle(SquatDesign.muted).frame(height: 14)
                    ActivityDayButton(day: day, hover: hover, select: select) {
                        ZStack(alignment: .bottom) {
                            Color.clear
                            if !day.future && day.count > 0 {
                                Rectangle().fill(SquatDesign.heat(day.level))
                                    .frame(width: 20, height: max(3, 84 * Double(day.count) / Double(snapshot.weeklyMaximum)))
                            } else if !day.future {
                                Rectangle().fill(.white).frame(width: 20, height: 2)
                            }
                        }
                    }.frame(height: 94)
                }.frame(maxWidth: .infinity)
            }
        }.transaction { $0.animation = nil }
    }
}

struct ProgressMonthGrid: View {
    let snapshot: ProgressRenderSnapshot
    let selectedDate: Date
    let hover: ProgressHoverState
    let select: (Date) -> Void
    let move: (MoveCommandDirection) -> Void
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { label in
                    Text(label).font(SquatDesign.text(8)).foregroundStyle(SquatDesign.muted).frame(maxWidth: .infinity)
                }
            }.frame(height: 14).accessibilityHidden(true)
            VStack(spacing: 6) {
                ForEach(0..<snapshot.model.weekColumns, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { column in
                            Group {
                                if let day = snapshot.day(at: row * 7 + column) {
                                    ActivityDayButton(day: day, hover: hover, select: select) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(day.future ? SquatDesign.heat(1).opacity(0.35) : SquatDesign.heat(day.level))
                                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(day.count == 0 && !day.future ? SquatDesign.track : .clear, lineWidth: 0.6))
                                            .frame(width: 14, height: 14)
                                    }
                                } else { Color.clear.accessibilityHidden(true) }
                            }.frame(maxWidth: .infinity).frame(height: 14)
                        }
                    }
                }
            }
        }.onMoveCommand(perform: move).transaction { $0.animation = nil }
            .accessibilityElement(children: .contain).accessibilityIdentifier("progress-month-grid")
    }
}

func progressMovedDate(_ direction: MoveCommandDirection, model: ProgressCalendarModel, selected: Date) -> Date {
    switch direction {
    case .left: return model.movedSelection(selected, horizontal: -1)
    case .right: return model.movedSelection(selected, horizontal: 1)
    case .up: return model.movedSelection(selected, vertical: -1)
    case .down: return model.movedSelection(selected, vertical: 1)
    default: return selected
    }
}
