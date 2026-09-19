import CoreGraphics
import Testing
import IsletCore

struct HorizontalSwipeRecognizerTests {
    @Test func leftwardSwipeNavigatesForwardOncePerGesture() {
        var recognizer = HorizontalSwipeRecognizer(threshold: 40)
        #expect(recognizer.handle(phase: .began, deltaX: 0, deltaY: 0) == nil)
        #expect(recognizer.handle(phase: .changed, deltaX: -25, deltaY: 2) == nil)
        #expect(recognizer.handle(phase: .changed, deltaX: -25, deltaY: 2) == .forward)
        #expect(recognizer.handle(phase: .changed, deltaX: -80, deltaY: 0) == nil)
        #expect(recognizer.handle(phase: .ended, deltaX: 0, deltaY: 0) == nil)

        #expect(recognizer.handle(phase: .began, deltaX: 0, deltaY: 0) == nil)
        #expect(recognizer.handle(phase: .changed, deltaX: 50, deltaY: 0) == .backward)
    }

    @Test func endingAGestureDiscardsItsTravel() {
        var recognizer = HorizontalSwipeRecognizer(threshold: 40)
        recognizer.handle(phase: .began, deltaX: 0, deltaY: 0)
        #expect(recognizer.handle(phase: .changed, deltaX: 30, deltaY: 0) == nil)
        recognizer.handle(phase: .ended, deltaX: 0, deltaY: 0)
        recognizer.handle(phase: .began, deltaX: 0, deltaY: 0)
        #expect(recognizer.handle(phase: .changed, deltaX: 15, deltaY: 0) == nil)
        #expect(recognizer.handle(phase: .changed, deltaX: 30, deltaY: 0) == .backward)
    }

    @Test func verticalScrollsAndUntrackedDeltasAreIgnored() {
        var recognizer = HorizontalSwipeRecognizer(threshold: 40)
        #expect(recognizer.handle(phase: .changed, deltaX: -100, deltaY: 0) == nil)

        #expect(recognizer.handle(phase: .began, deltaX: 0, deltaY: 0) == nil)
        #expect(recognizer.handle(phase: .changed, deltaX: -50, deltaY: -120) == nil)
        #expect(recognizer.handle(phase: .changed, deltaX: -100, deltaY: 0) == .forward)
    }
}
