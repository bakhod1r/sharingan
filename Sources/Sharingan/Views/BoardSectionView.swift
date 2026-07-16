import SwiftUI
import SharinganCore

/// The Board section: a segmented picker over the two boards — the local
/// weekly planner and the Jira sprint board (formerly a sheet in Tasks).
/// The Jira model is created once on first visit and kept for the window's
/// lifetime so tab switches don't refetch (`JiraBoardView`'s `.task` guard
/// only loads while `phase == .idle`).
struct BoardSectionView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var router = AppRouter.shared

    /// Last-selected tab, restored across launches.
    @AppStorage("board.tab") private var tabRaw = BoardTab.weekly.rawValue
    private var tab: BoardTab { BoardTab(rawValue: tabRaw) ?? .weekly }

    /// Created lazily on the first switch to the Jira tab; nil while
    /// disconnected (the tab then shows the connect hint instead).
    @State private var jiraModel: JiraBoardModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSegmentedPicker(
                selection: Binding(get: { tab },
                                   set: { tabRaw = $0.rawValue }),
                cases: BoardTab.allCases, label: \.title)
                .frame(width: 220)

            switch tab {
            case .weekly:
                WeeklyBoardView(timer: timer)
            case .jira:
                jiraBoard
            }
        }
        .onAppear(perform: consumeDeepLink)
        .onChange(of: router.pendingBoardTab) { consumeDeepLink() }
    }

    @ViewBuilder
    private var jiraBoard: some View {
        if let model = jiraModel,
           let project = AppServices.jiraService?.boardProjectKey {
            JiraBoardView(model: model, projectKey: project,
                          accent: timer.settings.theme.accent)
        } else {
            connectHint
        }
    }

    /// Shown while Jira is disconnected (or has no browsable project).
    private var connectHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.dsTertiary)
            Text("Connect Jira in Settings to see your sprint board.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.dsSecondary)
            Button("Open Settings") { AppRouter.shared.openSettings() }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .onAppear(perform: resolveJiraModel)
    }

    /// Applies a pending deep-link tab, then re-resolves the Jira model so a
    /// connection made while the window was open is picked up.
    private func consumeDeepLink() {
        if let pending = router.pendingBoardTab {
            tabRaw = pending.rawValue
            router.pendingBoardTab = nil
        }
        if tab == .jira { resolveJiraModel() }
    }

    private func resolveJiraModel() {
        if jiraModel == nil {
            jiraModel = AppServices.jiraService?.makeBoardModel()
        }
    }
}
