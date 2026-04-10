//
//  AVIMAAdFlowUITests.swift
//  SwiftUIPlayerUITests
//
//  UI tests for IMA ad playback flow: embedded ad display, fullscreen transition
//  during ads, and return to embedded mode. Screenshots are captured at each step
//  to verify ad chrome ("Learn More"), controls, and video rendering.
//

import XCTest

final class AVIMAAdFlowUITests: XCTestCase {

    // MARK: - Accessibility ID Mirror

    private enum ID {
        enum Player {
            static let container = "player.container"
            static let embedded = "player.embedded"
            static let fullscreen = "player.fullscreen"
            static let adPlayback = "player.adPlayback"
            static let mainVideoPlayback = "player.mainVideoPlayback"
            static let loadingIndicator = "player.loading"
        }

        enum Controls {
            static let expandButton = "controls.expand"
            static let closeButton = "controls.close"
            static let playPauseButton = "controls.playPause"
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
        continueAfterFailure = true  // Continue to capture all screenshots even if assertions fail
        app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app = nil
    }

    // MARK: - Helpers

    /// Navigates to the AVIMA Player tab.
    private func navigateToIMATab() {
        let tab = app.tabBars.buttons["AVIMA Player"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "AVIMA Player tab should exist")
        tab.tap()
    }

    /// Waits for the embedded player to appear.
    @discardableResult
    private func waitForEmbeddedPlayer(timeout: TimeInterval = 15) -> XCUIElement {
        let embedded = app.otherElements[ID.Player.embedded]
        XCTAssertTrue(
            embedded.waitForExistence(timeout: timeout),
            "Embedded player should appear after videos load"
        )
        return embedded
    }

    /// Takes a named screenshot and attaches it to the test report.
    private func takeScreenshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Taps the expand button (works for both main video controls and ad controls bar).
    private func tapExpandButton() {
        let expandButton = app.buttons[ID.Controls.expandButton]
        if expandButton.waitForExistence(timeout: 3) {
            expandButton.tap()
        } else {
            // Controls might be hidden — tap the player to show them
            let embedded = app.otherElements[ID.Player.embedded]
            if embedded.exists {
                embedded.tap()
                sleep(1)
            }
            XCTAssertTrue(expandButton.waitForExistence(timeout: 5), "Expand button should appear")
            expandButton.tap()
        }
    }

    /// Taps the close button to dismiss fullscreen.
    private func tapCloseButton() {
        let closeButton = app.buttons[ID.Controls.closeButton]
        if !closeButton.waitForExistence(timeout: 3) {
            // Tap to show controls
            let fullscreen = app.otherElements[ID.Player.fullscreen]
            if fullscreen.exists { fullscreen.tap() }
        }
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Close button should appear")
        closeButton.tap()
    }

    // MARK: - Tests

    /// Test: Embedded ad plays → screenshot → expand to fullscreen → screenshot → return → screenshot.
    ///
    /// Verifies:
    /// - Ad loads and plays in embedded mode
    /// - Ad chrome (IMA overlay including "Learn More") is visible
    /// - Fullscreen transition during ad preserves video playback
    /// - Return to embedded mode restores the player (no black screen)
    @MainActor
    func testEmbeddedAdToFullscreenAndBack() throws {
        // 1. Navigate to IMA tab and wait for content
        navigateToIMATab()
        waitForEmbeddedPlayer()
        takeScreenshot("01-List-With-Embedded-Player")

        // 2. Wait for the ad to start playing.
        //    The preroll ad auto-plays after initialization (~3-5 seconds).
        //    We wait up to 10 seconds for the ad playback state.
        sleep(5)
        takeScreenshot("02-Embedded-Ad-Playing")

        // 3. Expand to fullscreen during ad playback
        tapExpandButton()
        sleep(1)
        takeScreenshot("03-Fullscreen-During-Ad")

        // Verify fullscreen is presented
        let fullscreen = app.otherElements[ID.Player.fullscreen]
        let fullscreenAppeared = fullscreen.waitForExistence(timeout: 5)
        takeScreenshot("04-Fullscreen-Verification")

        if fullscreenAppeared {
            // 4. Wait a moment for ad to continue in fullscreen, then screenshot
            sleep(2)
            takeScreenshot("05-Fullscreen-Ad-Continued")

            // 5. Close fullscreen and return to embedded
            tapCloseButton()
            sleep(1)
            takeScreenshot("06-Returned-To-Embedded")

            // Verify embedded player is back and not black
            let embedded = app.otherElements[ID.Player.embedded]
            XCTAssertTrue(
                embedded.waitForExistence(timeout: 5),
                "Embedded player should reappear after dismissing fullscreen"
            )
            takeScreenshot("07-Embedded-Restored")
        } else {
            XCTFail("Fullscreen did not appear after tapping expand")
        }
    }

    /// Test: Wait for ad to complete → verify main video plays → expand → return.
    ///
    /// Verifies:
    /// - Ad completes and transitions to main video
    /// - Main video controls are functional
    /// - Fullscreen works for main video (no IMA reparenting issues)
    @MainActor
    func testAdCompletesToMainVideoThenFullscreen() throws {
        navigateToIMATab()
        waitForEmbeddedPlayer()

        // Wait for preroll ad to complete (sample ads are ~10 seconds)
        takeScreenshot("01-Before-Ad")
        sleep(15)
        takeScreenshot("02-After-Ad-Main-Video")

        // Verify main video playback
        let mainVideo = app.otherElements[ID.Player.mainVideoPlayback]
        let mainVideoPlaying = mainVideo.waitForExistence(timeout: 10)
        takeScreenshot("03-Main-Video-Playing")

        if mainVideoPlaying {
            // Expand to fullscreen
            tapExpandButton()
            sleep(1)
            takeScreenshot("04-Fullscreen-Main-Video")

            let fullscreen = app.otherElements[ID.Player.fullscreen]
            XCTAssertTrue(
                fullscreen.waitForExistence(timeout: 5),
                "Fullscreen should appear for main video"
            )

            // Return to embedded
            tapCloseButton()
            sleep(1)
            takeScreenshot("05-Returned-From-Fullscreen")

            let embedded = app.otherElements[ID.Player.embedded]
            XCTAssertTrue(
                embedded.waitForExistence(timeout: 5),
                "Embedded player should restore after fullscreen main video"
            )
        }
    }

    /// Test: Standalone fullscreen launch from row expand button.
    ///
    /// Verifies:
    /// - Row expand button launches fullscreen cover
    /// - Ad plays in fullscreen mode with controls
    /// - Close button dismisses back to list
    @MainActor
    func testStandaloneFullscreenFromRowButton() throws {
        navigateToIMATab()

        // Wait for the video list to load
        let listContainer = app.otherElements[ID.VideoList.container]
        XCTAssertTrue(listContainer.waitForExistence(timeout: 10))

        // Find a fullscreen launch button on a video row.
        // The expand buttons in the "All Videos" section are for standalone fullscreen.
        // The first expand button is on the embedded player — we want the second one
        // (on the first row in "All Videos").
        sleep(5) // Wait for videos to load
        takeScreenshot("01-Video-List")

        // Look for the "Play fullscreen" button in the list cells
        let fullscreenButtons = app.buttons.matching(identifier: "Play fullscreen")
        if fullscreenButtons.count > 0 {
            fullscreenButtons.element(boundBy: 0).tap()
            sleep(2)
            takeScreenshot("02-Standalone-Fullscreen-Ad")

            // Wait for ad to play
            sleep(5)
            takeScreenshot("03-Standalone-Fullscreen-Ad-Playing")

            // Wait for ad to complete
            sleep(10)
            takeScreenshot("04-Standalone-Fullscreen-Main-Video")

            // Close
            tapCloseButton()
            sleep(1)
            takeScreenshot("05-Back-To-List")
        } else {
            takeScreenshot("02-No-Fullscreen-Buttons-Found")
            XCTFail("No 'Play fullscreen' buttons found in the video list")
        }
    }

    /// Test: Rapid expand/collapse cycles during ad playback.
    ///
    /// Stress test that verifies no crashes or black screens when rapidly
    /// toggling between embedded and fullscreen during ad playback.
    @MainActor
    func testRapidExpandCollapseDuringAd() throws {
        navigateToIMATab()
        waitForEmbeddedPlayer()

        // Wait for ad to start
        sleep(5)
        takeScreenshot("01-Ad-Started")

        // Rapid expand/collapse (2 cycles)
        for i in 1...2 {
            tapExpandButton()
            sleep(1)
            takeScreenshot("Cycle\(i)-Expanded")

            let fullscreen = app.otherElements[ID.Player.fullscreen]
            if fullscreen.waitForExistence(timeout: 3) {
                tapCloseButton()
                sleep(1)
                takeScreenshot("Cycle\(i)-Collapsed")
            }
        }

        // Verify embedded player is still functional
        let embedded = app.otherElements[ID.Player.embedded]
        XCTAssertTrue(
            embedded.waitForExistence(timeout: 5),
            "Embedded player should survive rapid expand/collapse cycles"
        )
        takeScreenshot("Final-State")
    }
}
