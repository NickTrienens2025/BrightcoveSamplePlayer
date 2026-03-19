//
//  BCOVPlayerViewControllerUITests.swift
//  SwiftUIPlayerUITests
//
//  UI tests for the BCOVPlayerViewControllerRepresentable using deep links
//  for player actions (fullscreen, seek) after manual UI navigation.
//

import XCTest

final class BCOVPlayerViewControllerUITests: XCTestCase {

    // MARK: - Properties

    private var app: XCUIApplication!

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app = nil
    }

    // MARK: - UI Navigation Helpers

    /// Selects the "BCOV IMA ViewController" control type from the segmented picker.
    private func selectControlType() {
        let segment = app.buttons["BCOV IMA ViewController"]
        XCTAssertTrue(
            segment.waitForExistence(timeout: 5),
            "BCOV IMA ViewController segment should exist"
        )
        segment.tap()
    }

    /// Taps the first video row in the list to navigate to the detail view.
    private func tapFirstVideo() {
        let firstCell = app.cells.firstMatch
        XCTAssertTrue(
            firstCell.waitForExistence(timeout: 10),
            "At least one video row should appear in the list"
        )
        firstCell.tap()
    }

    /// Selects the control type, taps the first video, and waits for it to load.
    private func navigateToFirstVideo() {
        selectControlType()
        tapFirstVideo()
        // Wait for the player to initialize and video to load
        sleep(15)
    }

    // MARK: - Deep Link Helpers

    /// Sends a deep link URL directly to the running simulator app
    /// via `xcrun simctl openurl`. Unlike `app.open(url)`, this delivers
    /// the URL without going through Springboard, so the app isn't
    /// backgrounded or restarted.
    private func sendDeepLink(_ path: String) {
        let urlString = "swiftuiplayer://\(path)"
        XCUIDevice.shared.system.open(URL(string: urlString)!)

    }

    /// Enters fullscreen via deep link.
    private func enterFullscreenViaDeepLink() {
        sendDeepLink("player/fullscreen")
    }

    /// Seeks to a time in seconds via deep link.
    private func seekTo(_ seconds: Double) {
        sendDeepLink("player/seek?time=\(seconds)")
    }

    /// Takes a named screenshot and attaches it to the test report.
    private func takeScreenshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Tests

    /// Tests navigating to a video and entering fullscreen via deep link.
    @MainActor
    func testNavigateAndFullscreenViaDeepLink() throws {
        navigateToFirstVideo()
        takeScreenshot("01-Video-Loaded")

        // Enter fullscreen via deep link
        enterFullscreenViaDeepLink()
        sleep(2)
        takeScreenshot("02-Fullscreen")
    }

    /// Tests seeking via deep link.
    @MainActor
    func testSeekViaDeepLink() throws {
        navigateToFirstVideo()
        takeScreenshot("01-Before-Seek")
        sleep(17)
        
        // Seek to 30 seconds
        seekTo(30)
        sleep(2)
        takeScreenshot("02-After-Seek-30s")

        // Seek to 60 seconds
        seekTo(60)
        sleep(2)
        takeScreenshot("03-After-Seek-60s")
    }

    /// Tests fullscreen + rotation via deep links.
    @MainActor
    func testFullscreenRotationViaDeepLink() throws {
        navigateToFirstVideo()
        sleep(17)

        // Enter fullscreen via deep link
        enterFullscreenViaDeepLink()

        seekTo(300)

        sleep(2)
        takeScreenshot("01-Fullscreen-Portrait")

        // Rotate to landscape
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        takeScreenshot("02-Fullscreen-Landscape")

        // Rotate back to portrait
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        takeScreenshot("03-Fullscreen-Portrait-Again")
    }
}
