import SwiftUI

struct FeedbackView: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var showComposer = false
    @State private var error: String?
    private let reportConcern: Bool
    private let supportRequest: Bool

    init(reportConcern: Bool = false, supportRequest: Bool = false) {
        self.reportConcern = reportConcern
        self.supportRequest = supportRequest
        _showComposer = State(initialValue: reportConcern || supportRequest)
    }

    var body: some View {
        List {
            if store.feedbackThreads.isEmpty {
                ContentUnavailableView {
                    Label("No conversations yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Send feedback, ask a question, or tell us what would make Nestic better.")
                } actions: {
                    Button("Send feedback") { showComposer = true }
                }
            } else {
                ForEach(store.feedbackThreads) { thread in
                    NavigationLink {
                        FeedbackThreadView(thread: thread)
                    } label: {
                        FeedbackThreadRow(thread: thread)
                    }
                }
            }
        }
        .formStyle()
        .navigationTitle("Feedback")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showComposer = true } label: {
                    Label("New feedback", systemImage: "plus.bubble")
                }
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showComposer) {
            FeedbackComposerView(reportConcern: reportConcern, supportRequest: supportRequest)
        }
        .alert("Couldn’t load feedback", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func refresh() async {
        do { try await store.loadFeedback() }
        catch let caughtError { error = caughtError.localizedDescription }
    }
}

struct FeedbackThreadRow: View {
    let thread: NestFeedbackThread

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(thread.subject)
                    .font(.headline)
                Spacer()
                Text(thread.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            Text(thread.lastMessagePreview ?? "No messages yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Text(thread.category.capitalized)
                Spacer()
                Text(thread.lastActivityAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }

    private var statusColor: Color {
        switch thread.status {
        case .open: .orange
        case .inProgress: NesticTheme.forest
        case .resolved: .secondary
        }
    }
}

private struct FeedbackComposerView: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var category = "idea"
    @State private var message = ""
    @State private var busy = false
    @State private var error: String?

    init(reportConcern: Bool = false, supportRequest: Bool = false) {
        _subject = State(initialValue: reportConcern ? "Report a safety concern" : "")
        _category = State(initialValue: reportConcern ? "safety" : (supportRequest ? "support" : "idea"))
        _message = State(initialValue: reportConcern ? "Nest: \nMember or content involved: \nWhat happened: " : "")
    }

    private let categories = [
        ("idea", "Feature idea"),
        ("bug", "Something isn’t working"),
        ("question", "Question"),
        ("support", "Support"),
        ("safety", "Safety concern"),
        ("account", "Account or billing"),
        ("other", "Something else")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Subject", text: $subject)
                    Picker("Type", selection: $category) {
                        ForEach(categories, id: \.0) { value, title in
                            Text(title).tag(value)
                        }
                    }
                    .accessibilityIdentifier("feedback.category")
                    TextEditor(text: $message)
                        .frame(minHeight: 150)
                        .overlay(alignment: .topLeading) {
                            if message.isEmpty {
                                Text("Tell us what happened or what you would like to see next.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                } footer: {
                    Text(category == "safety"
                         ? "Safety reports go directly to the Nestic team. If you feel unsafe, leave the nest from Your nest immediately."
                         : "A member of the Nestic team will reply here. You can continue the conversation from this screen.")
                }
            }
            .formStyle()
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .disabled(busy || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay { if busy { ProgressView("Sending…") } }
            .alert("Couldn’t send feedback", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func send() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.createFeedback(subject: subject, category: category, message: message)
                dismiss()
            } catch let caughtError { error = caughtError.localizedDescription }
        }
    }
}

struct FeedbackThreadView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var thread: NestFeedbackThread
    @State private var reply = ""
    @State private var busy = false
    @State private var error: String?
    private let isAdmin: Bool

    init(thread: NestFeedbackThread, isAdmin: Bool = false) {
        _thread = State(initialValue: thread)
        self.isAdmin = isAdmin
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isAdmin {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.userDisplayName).font(.headline)
                            Text(thread.userEmail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Menu {
                            ForEach(NestFeedbackStatus.allCases) { status in
                                Button(status.title) { changeStatus(status) }
                            }
                        } label: {
                            Label("Status: " + thread.status.title, systemImage: "slider.horizontal.3")
                        }
                        .disabled(busy)
                    }
                    HStack {
                        Label(thread.category.capitalized, systemImage: "tag")
                        Spacer()
                        Text(thread.status.title).foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.semibold))
                    ForEach(thread.messages) { message in
                        FeedbackMessageBubble(message: message, isCurrentUser: message.authorUserId == store.currentUser?.id)
                            .id(message.id)
                    }
                    if thread.messages.isEmpty {
                        Text("Loading conversation…").foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Reply…", text: $reply, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                    Button { sendReply(proxy: proxy) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(busy || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle(thread.subject)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .alert("Couldn’t update feedback", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func load() async {
        do { thread = try await store.loadFeedbackThread(thread, asAdmin: isAdmin) }
        catch let caughtError { error = caughtError.localizedDescription }
    }

    private func sendReply(proxy: ScrollViewProxy) {
        let value = reply
        reply = ""
        busy = true
        Task {
            defer { busy = false }
            do {
                if isAdmin {
                    thread = try await store.replyToAdminFeedback(thread, message: value)
                } else {
                    try await store.replyToFeedback(thread, message: value)
                    if let updated = store.feedbackThreads.first(where: { $0.id == thread.id }) {
                        thread = updated
                    }
                }
                if let last = thread.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            } catch let caughtError {
                reply = value
                error = caughtError.localizedDescription
            }
        }
    }

    private func changeStatus(_ status: NestFeedbackStatus) {
        busy = true
        Task {
            defer { busy = false }
            do { thread = try await store.updateAdminFeedback(thread, status: status) }
            catch let caughtError { error = caughtError.localizedDescription }
        }
    }
}

private struct FeedbackMessageBubble: View {
    let message: NestFeedbackMessage
    let isCurrentUser: Bool

    var body: some View {
        HStack {
            if isCurrentUser { Spacer(minLength: 30) }
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 5) {
                Text(message.isAdmin ? "Nestic team" : (isCurrentUser ? "You" : message.authorDisplayName))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.body)
                    .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
                    .padding(12)
                    .background(isCurrentUser ? NesticTheme.forest.opacity(0.14) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                if let createdAt = message.createdAt {
                    Text(createdAt, style: .date).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if !isCurrentUser { Spacer(minLength: 30) }
        }
    }
}
