struct QuestionAnswers: Equatable {
    let questions: [PendingRequest.Question]
    private(set) var recorded: [String] = []
    private(set) var selection: [Int] = []

    init(questions: [PendingRequest.Question]) {
        self.questions = questions
    }

    var index: Int { min(recorded.count, questions.count - 1) }
    var question: PendingRequest.Question { questions[index] }
    var isComplete: Bool { recorded.count == questions.count }
    var isLast: Bool { index + 1 == questions.count }
    var canGoBack: Bool { !recorded.isEmpty && !isComplete }

    var answers: [String: String] {
        var result: [String: String] = [:]
        for (offset, answer) in recorded.enumerated() {
            result[questions[offset].text] = answer
        }
        return result
    }

    mutating func choose(_ offset: Int) {
        guard !isComplete, question.options.indices.contains(offset) else { return }
        if question.multiSelect {
            if let position = selection.firstIndex(of: offset) {
                selection.remove(at: position)
            } else {
                selection.append(offset)
            }
        } else {
            record(question.options[offset].label)
        }
    }

    mutating func submitSelection() {
        guard !isComplete, question.multiSelect, !selection.isEmpty else { return }
        record(selectedLabels.joined(separator: ", "))
    }

    mutating func submitOther(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isComplete, !trimmed.isEmpty else { return }
        let parts = question.multiSelect ? selectedLabels + [trimmed] : [trimmed]
        record(parts.joined(separator: ", "))
    }

    mutating func back() {
        guard canGoBack else { return }
        recorded.removeLast()
        selection = []
    }

    private var selectedLabels: [String] {
        selection.sorted().map { question.options[$0].label }
    }

    private mutating func record(_ answer: String) {
        recorded.append(answer)
        selection = []
    }
}
