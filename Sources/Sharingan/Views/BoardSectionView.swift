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

    /// Created lazily on the first switch to the Jira tab, kept for the
    /// window's lifetime so tab switches don't refetch.
    @State private var jiraModel: JiraBoardModel?

    /// Whether Jira is integrated — the Jira tab only exists when it is.
    private var jiraConnected: Bool { AppServices.jiraService?.isConnected == true }

    /// The tabs to offer right now: always Weekly + Board, plus Jira once
    /// integrated.
    private var availableTabs: [BoardTab] {
        jiraConnected ? BoardTab.allCases : BoardTab.alwaysAvailable
    }

    /// The effective selection — never the Jira tab while disconnected.
    private var selection: BoardTab {
        availableTabs.contains(tab) ? tab : .weekly
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSegmentedPicker(
                selection: Binding(get: { selection },
                                   set: { tabRaw = $0.rawValue }),
                cases: availableTabs, label: \.title)
                .frame(width: jiraConnected ? 300 : 220)

            switch selection {
            case .weekly:
                WeeklyBoardView(timer: timer)
            case .kanban:
                SharinganBoardView(timer: timer)
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

    /// Rare fallback: the tab is only shown while connected, but a board
    /// model or project key can still be momentarily unavailable.
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

    /// Applies a pending deep-link tab, then resolves the Jira model when the
    /// Jira tab is the effective selection.
    private func consumeDeepLink() {
        if let pending = router.pendingBoardTab {
            tabRaw = pending.rawValue
            router.pendingBoardTab = nil
        }
        if selection == .jira { resolveJiraModel() }
    }

    private func resolveJiraModel() {
        if jiraModel == nil {
            jiraModel = AppServices.jiraService?.makeBoardModel()
        }
    }
}
