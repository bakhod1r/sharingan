import SwiftUI
import SharinganCore

/// The Board section: a segmented picker over the three local boards — the
/// weekly planner, the kanban board, and the project timeline. The last-used
/// tab is remembered across launches (`board.tab`), and callers can deep-link
/// straight to a tab through `AppRouter.openBoard(tab:)`.
struct BoardSectionView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var router = AppRouter.shared

    /// Last-selected tab, restored across launches.
    @AppStorage("board.tab") private var tabRaw = BoardTab.weekly.rawValue
    private var selection: BoardTab { BoardTab(rawValue: tabRaw) ?? .weekly }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSegmentedPicker(
                selection: Binding(get: { selection },
                                   set: { tabRaw = $0.rawValue }),
                cases: BoardTab.allCases, label: \.title)
                .frame(width: 300)

            // Every tab fills the same area, so switching tabs never resizes
            // the window.
            Group {
                switch selection {
                case .weekly:
                    WeeklyBoardView(timer: timer)
                case .kanban:
                    SharinganBoardView(timer: timer)
                case .timeline:
                    TimelineBoardView(timer: timer)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: consumeDeepLink)
        .onChange(of: router.pendingBoardTab) { consumeDeepLink() }
    }

    /// Applies a pending deep-link tab, if any.
    private func consumeDeepLink() {
        if let pending = router.pendingBoardTab {
            tabRaw = pending.rawValue
            router.pendingBoardTab = nil
        }
    }
}
