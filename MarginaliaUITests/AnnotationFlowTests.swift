import XCTest

/// Drives the real UI end to end and writes screenshots to $SHOTS_DIR for review.
/// Run with: TEST_RUNNER_SHOTS_DIR=<dir> TEST_RUNNER_SAMPLES_DIR=<dir with PDFs> xcodebuild test …
final class AnnotationFlowTests: XCTestCase {
    private var shotsDir: String? { ProcessInfo.processInfo.environment["SHOTS_DIR"] }

    @MainActor
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MARGINALIA_RESET"] = "1"
        if let samples = ProcessInfo.processInfo.environment["SAMPLES_DIR"] {
            app.launchEnvironment["MARGINALIA_IMPORT_DIR"] = samples
        }
        app.launch()
        return app
    }

    @MainActor
    private func shot(_ name: String) {
        guard let dir = shotsDir else { return }
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    @MainActor
    private func dumpHierarchy(_ app: XCUIApplication) {
        guard let dir = shotsDir else { return }
        try? app.debugDescription.write(toFile: dir + "/hierarchy.txt", atomically: true, encoding: .utf8)
        shot("00-failure")
    }

    @MainActor
    func testReadAnnotateAndReview() throws {
        let app = launch()
        // Library
        let all = app.staticTexts["All"].firstMatch
        if all.waitForExistence(timeout: 5) { all.tap() }
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Attention Is All'")).firstMatch
        if !card.waitForExistence(timeout: 15) { dumpHierarchy(app) }
        XCTAssertTrue(card.exists)
        shot("01-library")

        // Reader
        card.tap()
        let notebookButton = app.buttons["Notebook"]
        XCTAssertTrue(notebookButton.waitForExistence(timeout: 10))
        shot("02-reader")

        // Finger selection is off by default, so a resting touch selects nothing and shows no menu.
        let canvas = app.windows.firstMatch
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.30)).press(forDuration: 1.0)
        let anyMenu = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN {'Highlight', 'Select All', 'Insert Space'}")).firstMatch
        XCTAssertFalse(anyMenu.waitForExistence(timeout: 1.5), "Long-press should not select text when finger selection is off")
        XCTAssertTrue(notebookButton.exists, "Long-press should not hide the reader controls")
        shot("02b-no-selection-by-default")

        // Turn finger selection on for the next step.
        app.buttons["Finger Text Selection"].tap()
        // Select a word by long-pressing on the first page's text, then highlight it.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.30)).press(forDuration: 1.0)
        shot("03-selection-menu")
        let highlight = app.descendants(matching: .any).matching(identifier: "Highlight").firstMatch
        if highlight.waitForExistence(timeout: 3) {
            highlight.tap()
        } else {
            dumpHierarchy(app)
            XCTFail("Highlight action missing from the selection menu")
        }
        shot("04-highlighted")

        // Smart highlighter with finger drawing: drag along a line of text.
        app.buttons["Smart Highlighter"].tap()
        app.buttons["Only Pencil draws"].tap()
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.40))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.40))
        start.press(forDuration: 0.05, thenDragTo: end)
        shot("05-smart-highlight")

        // Coloured pen: picking a swatch switches to the pen.
        for (ink, y) in [("Red ink", 0.50), ("Blue ink", 0.53), ("Black ink", 0.56)] {
            app.buttons[ink].tap()
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: y))
                .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: y + 0.01)))
        }
        shot("05b-pen-colours")

        // Add a note to the first highlight: tap the mark, Add Note, type, Done.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.30)).tap()
        let addNote = app.descendants(matching: .any).matching(identifier: "Add Note").firstMatch
        if addNote.waitForExistence(timeout: 3) {
            addNote.tap()
            app.textViews.firstMatch.typeText("Key idea: attention replaces recurrence entirely.")
            app.buttons["Done"].tap()
        }

        // Save the annotated copy, then save again: the second save replaces the first.
        app.buttons["Save Annotated PDF"].tap()
        XCTAssertTrue(app.staticTexts["Saved annotated PDF"].waitForExistence(timeout: 10))
        shot("05c-saved")
        app.buttons["Save Annotated PDF"].tap()
        XCTAssertTrue(app.staticTexts["Saved — replaced previous version"].waitForExistence(timeout: 10))

        // Notebook
        notebookButton.tap()
        shot("06-notebook")

        // Restore defaults for the next run.
        app.buttons["Finger draws"].tap()
        app.buttons["Pen"].tap()
    }
}
