import Testing
@testable import SharinganCore

@Suite struct ExerciseMistakeTests {
    @Test func matchingGazeIsNoMistake() {
        #expect(ExerciseMistake.evaluate(gaze: .left, faceDetected: true,
                                         target: .left, tolerance: 0.4) == nil)
    }

    @Test func noFaceWins() {
        #expect(ExerciseMistake.evaluate(gaze: .left, faceDetected: false,
                                         target: .left, tolerance: 0.4) == .noFace)
    }

    @Test func wrongDirection() {
        let m = ExerciseMistake.evaluate(gaze: .right, faceDetected: true,
                                         target: .left, tolerance: 0.4)
        #expect(m == .wrongDirection(looked: "right", target: "left"))
        #expect(m?.title == "You looked RIGHT")
        #expect(m?.subtitle == "Look LEFT — follow the eyes")
    }

    @Test func diagonalLabelsUppercased() {
        let m = ExerciseMistake.evaluate(gaze: .down, faceDetected: true,
                                         target: .upLeft, tolerance: 0.4)
        #expect(m?.subtitle == "Look UP LEFT — follow the eyes")
    }

    @Test func centerGazeIsNotMoving() {
        let m = ExerciseMistake.evaluate(gaze: GazeDirection(dx: 0.1, dy: 0.1),
                                         faceDetected: true, target: .left, tolerance: 0.4)
        #expect(m == .notMoving(target: "left"))
        #expect(m?.title == "Move your eyes")
        #expect(m?.subtitle == "Look LEFT — not straight ahead")
    }

    @Test func arrowPointsToTarget() {
        #expect(ExerciseMistake.notMoving(target: "left").arrow(target: .left)?.dx == -1)
        #expect(ExerciseMistake.noFace.arrow(target: .left) == nil)
        #expect(ExerciseMistake.noFace.title == "Face the camera")
        #expect(ExerciseMistake.noFace.subtitle == "I can't see your eyes")
    }
}

@Suite struct ExerciseValidatorMistakeTests {
    @MainActor private func make(_ dir: String) -> ExerciseValidator {
        let v = ExerciseValidator()
        v.exercises = [BreakExercise(name: "t", steps: [
            .init(direction: dir, holdSeconds: 2), .init(direction: "right", holdSeconds: 2)])]
        v.start()
        return v
    }

    @Test @MainActor func appearsAfterGraceOnly() {
        let v = make("left"); defer { v.stop() }
        v.ingest(gaze: .right, isBlinking: false)
        #expect(v.mistake == nil)
        v.tick(0.7)
        v.ingest(gaze: .right, isBlinking: false)
        #expect(v.mistake == .wrongDirection(looked: "right", target: "left"))
    }

    @Test @MainActor func clearedOnMatch() {
        let v = make("left"); defer { v.stop() }
        v.tick(0.7)
        v.ingest(gaze: .right, isBlinking: false)
        v.ingest(gaze: .left, isBlinking: false)
        #expect(v.mistake == nil)
    }

    @Test @MainActor func noFaceReported() {
        let v = make("left"); defer { v.stop() }
        v.tick(0.7)
        v.ingest(gaze: .center, isBlinking: false, faceDetected: false)
        #expect(v.mistake == .noFace)
    }

    @Test @MainActor func nilForNonValidatableSteps() {
        for d in ["far", "center", "closed", "circle_cw", "blink"] {
            let v = make(d)
            v.tick(0.7)
            v.ingest(gaze: .right, isBlinking: false)
            #expect(v.mistake == nil, "\(d)")
            v.stop()
        }
    }

    @Test @MainActor func clearedOnStepChange() {
        let v = make("left"); defer { v.stop() }
        v.tick(0.7)
        v.ingest(gaze: .right, isBlinking: false)
        #expect(v.mistake != nil)
        v.ingest(gaze: .left, isBlinking: false)
        v.tick(2.0)
        #expect(v.currentStepIndex == 1)
        #expect(v.mistake == nil)
        v.tick(0.7)
        v.ingest(gaze: .left, isBlinking: false)
        #expect(v.mistake != nil)
        v.stop()
        #expect(v.mistake == nil)
    }
}
