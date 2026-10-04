import SwiftUI

struct RequestView: View {
    let request: PendingRequest
    let showTerminal: () -> Void
    let decide: (PermissionDecision) -> Void

    var body: some View {
        switch request.kind {
        case .permission(_, let detail):
            VStack(alignment: .leading, spacing: AgentsPlugin.requestSpacing) {
                Text(detail ?? request.toolName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: AgentsPlugin.requestDetailHeight, maxHeight: AgentsPlugin.requestDetailHeight, alignment: .topLeading)
                HStack(spacing: AgentsPlugin.requestSpacing) {
                    RequestButton("Allow", systemImage: "checkmark", tint: .green) { decide(.allow) }
                    if request.alwaysAllowRule != nil {
                        RequestButton("Always allow", systemImage: "checkmark.circle", tint: .green) { decide(.allowAlways) }
                            .help(request.alwaysAllowDescription ?? "")
                    }
                    RequestButton("Deny", systemImage: "xmark", tint: .red) { decide(.deny) }
                }
            }
            .padding(.vertical, AgentsPlugin.requestPadding)
        case .question(let questions):
            QuestionView(questions: questions, answerInTerminal: request.isAnswerable ? nil : showTerminal) { decide(.answers($0)) }
                .padding(.vertical, AgentsPlugin.requestPadding)
        }
    }
}

private struct QuestionView: View {
    let answerInTerminal: (() -> Void)?
    let submit: ([String: String]) -> Void
    @State private var state: QuestionAnswers
    @State private var isTyping = false
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    init(questions: [PendingRequest.Question], answerInTerminal: (() -> Void)? = nil, submit: @escaping ([String: String]) -> Void) {
        self.answerInTerminal = answerInTerminal
        self.submit = submit
        _state = State(initialValue: QuestionAnswers(questions: questions))
    }

    private var question: PendingRequest.Question { state.question }
    private var detailHeight: CGFloat { AgentsPlugin.questionDetailHeight(for: state.questions) }
    private var canSubmitText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var confirmTitle: String { state.isLast ? "Submit" : "Next" }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentsPlugin.requestSpacing) {
            HStack(alignment: .top, spacing: 6) {
                if state.canGoBack {
                    Button {
                        state.back()
                        closeTyping()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Previous question")
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let header = question.header {
                        Text(state.questions.count > 1 ? "\(header) · \(state.index + 1) of \(state.questions.count)" : header)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                    }
                    Text(question.text)
                        .font(.system(size: 12))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: detailHeight, maxHeight: detailHeight, alignment: .topLeading)
            if isTyping {
                TextField("Your answer", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .frame(height: AgentsPlugin.requestButtonHeight)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
                    .focused($fieldFocused)
                    .onAppear { fieldFocused = true }
                    .onSubmit(submitText)
                HStack(spacing: AgentsPlugin.requestSpacing) {
                    RequestButton(confirmTitle, systemImage: "checkmark", tint: .green, action: submitText)
                        .disabled(!canSubmitText)
                        .opacity(canSubmitText ? 1 : 0.4)
                    RequestButton("Cancel", systemImage: "xmark", tint: .red, action: closeTyping)
                }
            } else {
                ForEach(Array(question.options.enumerated()), id: \.offset) { offset, option in
                    RequestButton(
                        option.label,
                        subtitle: option.description,
                        systemImage: question.multiSelect ? (state.selection.contains(offset) ? "checkmark.square.fill" : "square") : "arrow.turn.down.right",
                        tint: .accentColor,
                        fullWidth: true
                    ) { choose(offset) }
                    .disabled(answerInTerminal != nil)
                    .opacity(answerInTerminal == nil ? 1 : 0.6)
                }
                if let answerInTerminal {
                    RequestButton("Answer in terminal", systemImage: "terminal", tint: .accentColor, fullWidth: true, action: answerInTerminal)
                } else {
                    RequestButton("Other…", systemImage: "pencil", tint: .accentColor, fullWidth: true) {
                        isTyping = true
                    }
                }
                if question.multiSelect {
                    RequestButton(confirmTitle, systemImage: "checkmark", tint: .green) {
                        state.submitSelection()
                        finishStep()
                    }
                    .disabled(state.selection.isEmpty)
                    .opacity(state.selection.isEmpty ? 0.4 : 1)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func choose(_ offset: Int) {
        state.choose(offset)
        finishStep()
    }

    private func submitText() {
        guard canSubmitText else { return }
        state.submitOther(text)
        closeTyping()
        finishStep()
    }

    private func closeTyping() {
        isTyping = false
        fieldFocused = false
        text = ""
    }

    private func finishStep() {
        if state.isComplete { submit(state.answers) }
    }
}

private struct RequestButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let fullWidth: Bool
    let action: () -> Void

    init(_ title: String, subtitle: String? = nil, systemImage: String, tint: Color, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
                .padding(.horizontal, 10)
                .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
                .frame(height: AgentsPlugin.requestButtonHeight)
                .background(Capsule().fill(tint.opacity(0.18)))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
