import SwiftUI
import SharinganCore

/// The issue detail sheet: description, comments, full change history and
/// worklogs — everything readable without opening Jira.
///
/// Each section loads independently; an empty section reads "No … yet" while a
/// failed one shows the error, never the empty-state copy. Rich text goes
/// through the plain-text ADF bridge, and the editors carry a caption saying
/// that saving replaces Jira formatting with plain text.
struct JiraIssueDetailView: View {

    @ObservedObject var model: JiraIssueDetailModel
    var onClose: (() -> Void)? = nil

    private enum Section: String, CaseIterable, Identifiable {
        case details = "Details"
        case comments = "Comments"
        case history = "History"
        case worklogs = "Worklogs"
        var id: String { rawValue }
    }

    @State private var section: Section = .details
    @State private var draftComment = ""
    @State private var draftDescription = ""
    @State private var isEditingDescription = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            picker
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch section {
                    case .details:  detailsSection
                    case .comments: commentsSection
                    case .history:  historySection
                    case .worklogs: worklogsSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            if let message = model.actionErrorMessage {
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.9))
            }
        }
        .padding(16)
        .frame(minWidth: 440, minHeight: 420)
        .task { await model.load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            JiraIssueBadge(key: model.issueKey, issueType: model.issueTypeName, size: 11)

            Text(model.summaryText)
                .font(.system(.headline, design: .rounded))
                .lineLimit(2)

            Spacer(minLength: 8)

            if let status = model.statusName {
                Text(status)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.dsSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.dsSecondary.opacity(0.12)))
            }

            if let url = model.browseURL {
                Link("Open in Jira", destination: url)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }

            if let onClose {
                Button("Close", action: onClose)
                    .buttonStyle(.glass)
            }
        }
    }

    private var picker: some View {
        Picker("", selection: $section) {
            ForEach(Section.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsSection: some View {
        Text("Description").dsSectionLabel()

        switch model.details {
        case .idle, .loading:
            loadingRow
        case .failed:
            errorRow(model.details.errorMessage)
        case .loaded:
            if isEditingDescription {
                descriptionEditor
            } else {
                if model.descriptionText.isEmpty {
                    emptyRow("No description.")
                } else {
                    Text(model.descriptionText)
                        .font(.system(.callout, design: .rounded))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Edit description") {
                    draftDescription = model.descriptionText
                    isEditingDescription = true
                }
                .buttonStyle(.glass)
                adfCaption
            }
        }
    }

    @ViewBuilder
    private var descriptionEditor: some View {
        TextEditor(text: $draftDescription)
            .font(.system(.callout, design: .rounded))
            .frame(minHeight: 100)
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.dsSecondary.opacity(0.08)))
        HStack(spacing: 8) {
            Button("Save") {
                let text = draftDescription
                Task {
                    await model.saveDescription(text)
                    if model.actionErrorMessage == nil { isEditingDescription = false }
                }
            }
            .buttonStyle(.glass)
            .disabled(model.isSavingDescription)

            Button("Cancel") { isEditingDescription = false }
                .buttonStyle(.glass)

            if model.isSavingDescription {
                ProgressView().controlSize(.small)
            }
        }
        adfCaption
    }

    /// The plain-text ADF tradeoff, said out loud.
    private var adfCaption: some View {
        Text("Rich formatting from Jira is shown as plain text. Saving replaces the description's formatting with plain text.")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Color.dsSecondary)
    }

    // MARK: - Comments

    @ViewBuilder
    private var commentsSection: some View {
        switch model.comments {
        case .idle, .loading:
            loadingRow
        case .failed:
            errorRow(model.comments.errorMessage)
        case .loaded(let comments):
            if comments.isEmpty {
                emptyRow("No comments yet.")
            } else {
                ForEach(comments, id: \.id) { comment in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(comment.author.displayName)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                            Text(dateLabel(comment.created))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Color.dsSecondary)
                        }
                        Text(comment.plainTextBody)
                            .font(.system(.callout, design: .rounded))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }
            }
            commentComposer
        }
    }

    @ViewBuilder
    private var commentComposer: some View {
        TextEditor(text: $draftComment)
            .font(.system(.callout, design: .rounded))
            .frame(minHeight: 56)
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.dsSecondary.opacity(0.08)))
        HStack(spacing: 8) {
            Button("Add comment") {
                let text = draftComment
                Task {
                    await model.addComment(text)
                    if model.actionErrorMessage == nil { draftComment = "" }
                }
            }
            .buttonStyle(.glass)
            .disabled(model.isPostingComment ||
                      draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if model.isPostingComment {
                ProgressView().controlSize(.small)
            }
        }
        Text("Comments are posted as plain text.")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Color.dsSecondary)
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        switch model.history {
        case .idle, .loading:
            loadingRow
        case .failed:
            errorRow(model.history.errorMessage)
        case .loaded(let entries):
            if entries.isEmpty {
                emptyRow("No changes recorded yet.")
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.authorName)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                            Text("changed \(entry.field)")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.dsSecondary)
                            if let date = entry.date {
                                Text(date, style: .date)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color.dsSecondary)
                            }
                        }
                        Text("\(entry.from ?? "None") → \(entry.to ?? "None")")
                            .font(.system(.callout, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }
            }
        }
    }

    // MARK: - Worklogs

    @ViewBuilder
    private var worklogsSection: some View {
        switch model.worklogs {
        case .idle, .loading:
            loadingRow
        case .failed:
            errorRow(model.worklogs.errorMessage)
        case .loaded(let worklogs):
            if worklogs.isEmpty {
                emptyRow("No worklogs yet.")
            } else {
                ForEach(worklogs, id: \.id) { worklog in
                    HStack(spacing: 8) {
                        Text(worklog.author.displayName)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                        Text(worklog.timeSpent)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                        Spacer(minLength: 8)
                        Text(dateLabel(worklog.started))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.dsSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }
            }
        }
    }

    // MARK: - Shared rows

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading…")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color.dsSecondary)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(.callout, design: .rounded))
            .foregroundStyle(Color.dsSecondary)
    }

    private func errorRow(_ message: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
            Text(message ?? "Couldn't load this section.")
        }
        .font(.system(.callout, design: .rounded))
        .foregroundStyle(Color.red.opacity(0.9))
    }

    private func dateLabel(_ raw: String) -> String {
        guard let date = JiraIssueDetailModel.date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
