import SwiftUI
import SharinganCore

/// The Jira sprint board: a horizontal row of frosted-glass columns holding the
/// active sprint's cards **assigned to me**. Drag a card to another column and
/// the model performs the matching Jira transition — the card lifts, the target
/// column glows, and it snaps back with a message if Jira refuses.
///
/// Deliberately shaped after `WeeklyBoardView`: same ~204pt columns, same
/// `.draggable`/`.dropDestination` idiom, the same drop-target glow and hover
/// lift, and the app's design-system helpers throughout. Navigation wiring lives
/// elsewhere; this view only needs a model and a project key.
struct JiraBoardView: View {
    @ObservedObject var model: JiraBoardModel
    /// The project whose board to show. Loaded on appear.
    let projectKey: String
    var accent: Color = .accentColor

    /// Card currently under the pointer — lifts slightly.
    @State private var hoveredCard: String?
    /// Column currently being dragged over — highlighted.
    @State private var targetedColumn: String?

    private let columnWidth: CGFloat = 204

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: projectKey) {
            if model.phase == .idle { await model.load(projectKey: projectKey) }
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading:
            loadingState
        case .chooseBoard:
            boardPicker
        case .error:
            errorState(model.errorMessage ?? "Something went wrong.")
        case .loaded:
            board
        }
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Loading board…")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.dsSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.dsSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await model.load(projectKey: projectKey) }
            }
            .buttonStyle(.pressableSubtle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var boardPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a board")
                .dsSectionLabel()
            ForEach(model.availableBoards, id: \.id) { board in
                Button {
                    Task { await model.selectBoard(board) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.split.3x1")
                            .foregroundStyle(accent)
                        Text(board.name)
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.dsSecondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(Color.dsFill))
                }
                .buttonStyle(.pressableSubtle)
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.sprintName ?? "Board")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                if model.phase == .loaded {
                    Text("\(model.doneCount) done / \(model.remainingCount) remaining")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .contentTransition(.opacity)
                }
            }
            Spacer()
            if let message = model.errorMessage, model.phase == .loaded {
                Label(message, systemImage: "arrow.uturn.backward")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: 280, alignment: .trailing)
                    .transition(.opacity)
            }
            if model.phase == .loaded {
                switchBoardButton
            }
        }
    }

    /// Forgets the remembered board and reloads, so a project with several
    /// boards re-shows the picker.
    private var switchBoardButton: some View {
        Button {
            model.forgetBoard()
            Task { await model.load(projectKey: projectKey) }
        } label: {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.pressableSubtle)
        .help("Switch board")
        .accessibilityLabel("Switch Jira board")
    }

    // MARK: - Board

    private var board: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(model.columns) { column in
                    columnView(column)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }

    private func columnView(_ column: JiraBoardModel.Column) -> some View {
        let targeted = targetedColumn == column.id
        return VStack(alignment: .leading, spacing: 12) {
            columnHeader(column)
            if column.cards.isEmpty {
                emptyDrop(targeted: targeted)
            } else {
                VStack(spacing: 9) {
                    ForEach(column.cards) { card in
                        cardView(card)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.88).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity)))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: columnWidth, alignment: .top)
        .frame(minHeight: 440, alignment: .top)
        .background(columnBackground(isOther: column.isOther, targeted: targeted))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(targeted ? accent.opacity(0.8) : Color.white.opacity(0.08),
                        lineWidth: targeted ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .scaleEffect(targeted ? 1.015 : 1)
        .animation(DS.Motion.standard, value: targeted)
        .dropDestination(for: String.self) { dropped, _ in
            guard let key = dropped.first else { return false }
            withAnimation(DS.Motion.standard) {
                Task { await model.move(issueKey: key, toColumnID: column.id) }
            }
            return true
        } isTargeted: { hovering in
            targetedColumn = hovering ? column.id : (targetedColumn == column.id ? nil : targetedColumn)
        }
    }

    private func columnHeader(_ column: JiraBoardModel.Column) -> some View {
        HStack(spacing: 8) {
            Text(column.name)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(column.isOther ? Color.dsSecondary : .white)
                .lineLimit(1)
            Spacer()
            Text("\(column.cards.count)")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(column.cards.isEmpty ? .white.opacity(0.3) : accent)
                .frame(minWidth: 20, minHeight: 20)
                .background(Circle().fill(Color.white.opacity(column.cards.isEmpty ? 0.03 : 0.08)))
        }
    }

    private func columnBackground(isOther: Bool, targeted: Bool) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(LinearGradient(
                        colors: targeted ? [accent.opacity(0.22), accent.opacity(0.05)]
                            : isOther ? [Color.white.opacity(0.015), .clear]
                            : [Color.white.opacity(0.07), .clear],
                        startPoint: .top, endPoint: .bottom))
            )
            .overlay( // top glass highlight
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.25), .clear],
                                           startPoint: .top, endPoint: .center),
                            lineWidth: 1)
                    .blendMode(.overlay)
            )
    }

    private func emptyDrop(targeted: Bool) -> some View {
        Group {
            if targeted {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(accent.opacity(0.8),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .overlay(
                        Text("Release to move")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(accent))
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .animation(DS.Motion.gentle, value: targeted)
    }

    // MARK: - Card

    private func cardView(_ card: JiraBoardModel.Card) -> some View {
        let hovered = hoveredCard == card.id
        return VStack(alignment: .leading, spacing: 7) {
            JiraIssueBadge(key: card.key, issueType: card.issueType)
            Text(card.summary)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if card.priorityName != nil || card.estimateSeconds != nil {
                HStack(spacing: 7) {
                    if let priority = card.priorityName {
                        Label(priority, systemImage: "flag.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    if let estimate = card.estimateSeconds {
                        Text(estimateLabel(estimate))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(hovered ? 0.15 : 0.09),
                             Color.white.opacity(hovered ? 0.08 : 0.04)],
                    startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(accent.opacity(hovered ? 0.5 : 0.18), lineWidth: 1)
        )
        .scaleEffect(hovered ? 1.035 : 1)
        .shadow(color: .black.opacity(hovered ? 0.3 : 0.12), radius: hovered ? 9 : 4, y: hovered ? 5 : 2)
        .animation(DS.Motion.standard, value: hovered)
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .onHover { inside in
            hoveredCard = inside ? card.id : (hoveredCard == card.id ? nil : hoveredCard)
        }
        .draggable(card.key) {
            Text(card.key)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.95)))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        }
    }

    /// Jira stores estimates in seconds; the card shows a compact hours/minutes.
    private func estimateLabel(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}

// MARK: - Preview

private struct PreviewTokens: JiraTokenProviding {
    func accessToken() async throws -> String { "preview" }
    func cloudID() async throws -> String { "cloud-preview" }
}

#Preview {
    JiraBoardView(
        model: JiraBoardModel(client: JiraClient(tokens: PreviewTokens()),
                              siteHost: "example.atlassian.net"),
        projectKey: "SHR",
        accent: .blue
    )
    .padding(24)
    .frame(width: 760, height: 560)
    .background(Color.black)
}
