import Testing
@testable import AgentsPlugin

struct QuestionAnswersTests {
    private func question(_ text: String, _ labels: [String], multi: Bool = false) -> PendingRequest.Question {
        PendingRequest.Question(text: text, options: labels.map { PendingRequest.Question.Option(label: $0) }, multiSelect: multi)
    }

    @Test func choosingALabelRecordsItAndAdvances() {
        var state = QuestionAnswers(questions: [question("Q1", ["A", "B"]), question("Q2", ["C"])])
        state.choose(1)
        #expect(state.answers == ["Q1": "B"])
        #expect(state.index == 1)
        #expect(!state.isComplete)
    }

    @Test func submittingOtherTextUsesItAsTheAnswer() {
        var state = QuestionAnswers(questions: [question("Q1", ["A", "B"])])
        state.submitOther("  my own  ")
        #expect(state.answers == ["Q1": "my own"])
        #expect(state.isComplete)
    }

    @Test func emptyOtherTextIsIgnored() {
        var state = QuestionAnswers(questions: [question("Q1", ["A"])])
        state.submitOther("   ")
        #expect(state.answers.isEmpty)
        #expect(!state.isComplete)
    }

    @Test func multiSelectJoinsLabelsAndOtherText() {
        var state = QuestionAnswers(questions: [question("Q1", ["A", "B", "C"], multi: true)])
        state.choose(2)
        state.choose(0)
        state.submitOther("extra")
        #expect(state.answers == ["Q1": "A, C, extra"])
    }

    @Test func multiSelectWithoutOtherText() {
        var state = QuestionAnswers(questions: [question("Q1", ["A", "B"], multi: true)])
        state.submitSelection()
        #expect(!state.isComplete)
        state.choose(1)
        state.choose(0)
        state.choose(1)
        state.submitSelection()
        #expect(state.answers == ["Q1": "A"])
    }

    @Test func backRemovesThePreviousAnswer() {
        var state = QuestionAnswers(questions: [question("Q1", ["A"]), question("Q2", ["B"])])
        #expect(!state.canGoBack)
        state.choose(0)
        #expect(state.canGoBack)
        state.back()
        #expect(state.index == 0)
        #expect(state.answers.isEmpty)
        state.submitOther("typed")
        #expect(state.answers == ["Q1": "typed"])
    }

    @Test func completionProducesAnswersKeyedByQuestionText() {
        var state = QuestionAnswers(questions: [question("Q1", ["A"]), question("Q2", ["B", "C"])])
        state.choose(0)
        state.choose(1)
        #expect(state.isComplete)
        #expect(state.answers == ["Q1": "A", "Q2": "C"])
    }
}
