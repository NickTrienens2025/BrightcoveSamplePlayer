//
//  AVIMAPlayerUITests.swift
//  SwiftUIPlayerUITests
//
//  UI tests for the AVIMA Player embedded → fullscreen flow and rotation behavior.
//

import XCTest

final class AVIMAPlayerUITests: XCTestCase {

    // MARK: - Accessibility ID Mirror

    // Mirror of AccessibilityID from the app target (UI tests can't import app code).
    private enum ID {
        enum Player {
            static let container = "player.container"
            static let embedded = "player.embedded"
            static let fullscreen = "player.fullscreen"
            static let videoSurface = "player.videoSurface"
            static let adPlayback = "player.adPlayback"
            static let mainVideoPlayback = "player.mainVideoPlayback"
            static let loadingIndicator = "player.loading"
            static let bufferingOverlay = "player.buffering"
        }

        enum Controls {
            static let overlay = "controls.overlay"
            static let expandButton = "controls.expand"
            static let closeButton = "controls.close"
            static let playPauseButton = "controls.playPause"
            static let muteButton = "controls.mute"
        }

        enum VideoList {
            static let container = "videoList.container"
            static let embeddedSection = "videoList.embeddedSection"
        }
    }

    // MARK: - Properties

    private var app: XCUIApplication!

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        // Reset orientation to portrait before each test
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        // Reset orientation after each test
        XCUIDevice.shared.orientation = .portrait
        app = nil
    }

    // MARK: - Helpers

    /// Navigates to the AVIMA Player tab and waits for the video list to load.
    private func navigateToIMATab() {
        app.tabBars.buttons["AVIMA Player"].tap()

        let listContainer = app.otherElements[ID.VideoList.container]
        XCTAssertTrue(
            listContainer.waitForExistence(timeout: 10),
            "Video list should appear after tapping IMA tab"
        )
    }

    /// Waits for the embedded player section to appear (videos loaded).
    @discardableResult
    private func waitForEmbeddedPlayer() -> XCUIElement {
        let embedded = app.otherElements[ID.Player.embedded]
        XCTAssertTrue(
            embedded.waitForExistence(timeout: 15),
            "Embedded player should appear after videos load"
        )
        return embedded
    }

    /// Taps the expand button on the embedded player to enter fullscreen.
    private func expandToFullscreen() {
        let expandButton = app.buttons[ID.Controls.expandButton]

        // Controls may need a tap on the player to show first.
        if !expandButton.waitForExistence(timeout: 5) {
            let embedded = app.otherElements[ID.Player.embedded]
            embedded.tap()
            XCTAssertTrue(
                expandButton.waitForExistence(timeout: 5),
                "Expand button should appear after tapping player"
            )
        }

        expandButton.tap()
    }

    /// Waits for fullscreen player to appear.
    @discardableResult
    private func waitForFullscreen() -> XCUIElement {
        let fullscreen = app.otherElements[ID.Player.fullscreen]
        XCTAssertTrue(
            fullscreen.waitForExistence(timeout: 5),
            "Fullscreen player should appear"
        )
        return fullscreen
    }

    /// Taps the close button to dismiss fullscreen.
    private func dismissFullscreen() {
        let closeButton = app.buttons[ID.Controls.closeButton]

        // Show controls if hidden
        if !closeButton.waitForExistence(timeout: 3) {
            let fullscreen = app.otherElements[ID.Player.fullscreen]
            fullscreen.tap()
            XCTAssertTrue(
                closeButton.waitForExistence(timeout: 5),
                "Close button should appear after tapping fullscreen player"
            )
        }

        closeButton.tap()
    }

    /// Takes a named screenshot and attaches it to the test report.
    private func takeScreenshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Tests

    /// Tests the full embedded → fullscreen → rotate → dismiss flow.
    ///
    /// 1. Navigate to IMA tab
    /// 2. Wait for embedded player to load
    /// 3. Expand to fullscreen
    /// 4. Verify fullscreen is presented
    /// 5. Rotate to landscape
    /// 6. Verify player container still exists in landscape
    /// 7. Rotate back to portrait
    /// 8. Dismiss fullscreen
    /// 9. Verify embedded player is back
    @MainActor
    func testEmbeddedToFullscreenWithRotation() throws {
        // 1. Navigate to IMA tab
        navigateToIMATab()
        takeScreenshot("01-IMA-Tab-List")

        // 2. Wait for embedded player
        waitForEmbeddedPlayer()
        takeScreenshot("02-Embedded-Player-Loaded")

        // 3. Expand to fullscreen
        expandToFullscreen()

        // 4. Verify fullscreen
        waitForFullscreen()
        takeScreenshot("03-Fullscreen-Portrait")

        // Verify the player container is present inside fullscreen
        let playerContainer = app.otherElements[ID.Player.container]
        XCTAssertTrue(playerContainer.exists, "Player container should exist in fullscreen")

        // 5. Rotate to landscape
        XCUIDevice.shared.orientation = .landscapeLeft
        // Allow time for rotation animation
        sleep(1)
        takeScreenshot("04-Fullscreen-Landscape")

        // Verify player container still exists after rotation
        XCTAssertTrue(
            playerContainer.waitForExistence(timeout: 5),
            "Player container should persist after rotation to landscape"
        )

        // 6. Rotate back to portrait
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        takeScreenshot("05-Fullscreen-Portrait-Again")

        XCTAssertTrue(
            playerContainer.waitForExistence(timeout: 5),
            "Player container should persist after rotation back to portrait"
        )

        // 7. Dismiss fullscreen
        dismissFullscreen()

        // 8. Verify embedded player is back
        let embedded = app.otherElements[ID.Player.embedded]
        XCTAssertTrue(
            embedded.waitForExistence(timeout: 5),
            "Embedded player should reappear after dismissing fullscreen"
        )

        // Verify fullscreen is gone
        let fullscreen = app.otherElements[ID.Player.fullscreen]
        XCTAssertFalse(fullscreen.exists, "Fullscreen should be dismissed")

        takeScreenshot("06-Back-To-Embedded")
    }

    /// Tests that rotating while in embedded (non-fullscreen) mode doesn't break the player.
    @MainActor
    func testEmbeddedPlayerRotation() throws {
        navigateToIMATab()
        waitForEmbeddedPlayer()
        takeScreenshot("01-Embedded-Portrait")

        // Rotate to landscape while embedded
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        takeScreenshot("02-Embedded-Landscape")

        // Embedded player should still exist
        let embedded = app.otherElements[ID.Player.embedded]
        XCTAssertTrue(
            embedded.waitForExistence(timeout: 5),
            "Embedded player should persist after rotation"
        )

        // Rotate back
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        takeScreenshot("03-Embedded-Portrait-Again")

        XCTAssertTrue(
            embedded.waitForExistence(timeout: 5),
            "Embedded player should persist after rotating back"
        )
    }

    /// Tests fullscreen rotation through all four orientations.
    @MainActor
    func testFullscreenAllOrientations() throws {
        navigateToIMATab()
        waitForEmbeddedPlayer()
        expandToFullscreen()
        waitForFullscreen()

        let playerContainer = app.otherElements[ID.Player.container]

        let orientations: [(UIDeviceOrientation, String)] = [
            (.landscapeLeft, "LandscapeLeft"),
            (.portraitUpsideDown, "PortraitUpsideDown"),
            (.landscapeRight, "LandscapeRight"),
            (.portrait, "Portrait"),
        ]

        for (orientation, name) in orientations {
            XCUIDevice.shared.orientation = orientation
            sleep(1)
            takeScreenshot("Fullscreen-\(name)")

            XCTAssertTrue(
                playerContainer.waitForExistence(timeout: 5),
                "Player container should exist in \(name) orientation"
            )
        }

        // Dismiss and verify return to embedded
        dismissFullscreen()
        let embedded = app.otherElements[ID.Player.embedded]
        XCTAssertTrue(
            embedded.waitForExistence(timeout: 5),
            "Should return to embedded player after fullscreen rotation test"
        )
    }

    /// Tests that rotating during fullscreen doesn't duplicate or lose the close button.
    @MainActor
    func testControlsPersistAfterRotation() throws {
        navigateToIMATab()
        waitForEmbeddedPlayer()
        expandToFullscreen()
        waitForFullscreen()

        // Show controls
        let fullscreen = app.otherElements[ID.Player.fullscreen]
        fullscreen.tap()

        let closeButton = app.buttons[ID.Controls.closeButton]
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 5),
            "Close button should be visible"
        )

        // Rotate to landscape
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)

        // Tap to show controls again (they may have auto-hidden during rotation)
        fullscreen.tap()

        // Close button should still be findable
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 5),
            "Close button should exist after rotation to landscape"
        )
        takeScreenshot("Controls-After-Rotation")

        // Verify we can still dismiss
        closeButton.tap()

        let embedded = app.otherElements[ID.Player.embedded]
        XCTAssertTrue(
            embedded.waitForExistence(timeout: 5),
            "Should dismiss fullscreen via close button after rotation"
        )
    }
}
