import XCTest

/// Saves real web pages through the in-app browser. Needs network access.
final class CaptureFlowTests: XCTestCase {
    private var shotsDir: String? { ProcessInfo.processInfo.environment["SHOTS_DIR"] }

    @MainActor
    private func shot(_ name: String) {
        guard let dir = shotsDir else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    @MainActor
    private func save(_ address: String, in app: XCUIApplication) {
        app.buttons["Add"].tap()
        let item = app.descendants(matching: .any).matching(identifier: "Save Web Page…").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        let field = app.textFields["Search or paste a link"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(address + "\n")
        // Wait for the page to finish loading before saving.
        let save = app.buttons["Save PDF"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 0"),
            object: app.progressIndicators)
        _ = XCTWaiter.wait(for: [loaded], timeout: 30)
        save.tap()
        // The browser closes once the PDF is in the library.
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 60), .completed)
    }

    @MainActor
    func testCaptureArticleAndPaper() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["MARGINALIA_RESET"] = "1"
        app.launch()

        save("paulgraham.com/greatwork.html", in: app)
        save("arxiv.org/abs/1706.03762", in: app)

        app.staticTexts["All"].firstMatch.tap()
        shot("10-captured-library")

        let article = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Great Work'")).firstMatch
        XCTAssertTrue(article.waitForExistence(timeout: 10))
        article.tap()
        XCTAssertTrue(app.buttons["Notebook"].waitForExistence(timeout: 10))
        shot("11-captured-article")
    }
}
