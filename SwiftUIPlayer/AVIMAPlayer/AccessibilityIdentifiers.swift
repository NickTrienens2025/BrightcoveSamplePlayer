//
//  AccessibilityIdentifiers.swift
//  SwiftUIPlayer
//
//  Centralized accessibility identifiers for UI testing.
//  Used by XCUITests to locate elements for rotation and fullscreen behavior tests.
//

import Foundation

/// Accessibility identifiers for the AVIMA player UI, organized by component.
///
/// **Naming convention:** `{component}.{element}`
///
/// **Usage in views:**
/// ```swift
/// .accessibilityIdentifier(AccessibilityID.Player.container)
/// ```
///
/// **Usage in UI tests:**
/// ```swift
/// let player = app.otherElements[AccessibilityID.Player.container]
/// XCTAssertTrue(player.exists)
/// ```
enum AccessibilityID {

    // MARK: - Player Container

    enum Player {
        /// The main player view (AVIMAPlayerView root).
        /// Present in both embedded and fullscreen contexts.
        static let container = "player.container"

        /// The embedded inline player (AVIMAEmbeddedPlayerView).
        static let embedded = "player.embedded"

        /// The fullscreen player presented via .fullScreenCover.
        static let fullscreen = "player.fullscreen"

        /// The AVPlayerViewController wrapper for main video.
        static let videoSurface = "player.videoSurface"

        /// Ad playback state — visible when playbackMode == .advertisement.
        static let adPlayback = "player.adPlayback"

        /// Main video playback state — visible when playbackMode == .mainVideo.
        static let mainVideoPlayback = "player.mainVideoPlayback"

        /// Loading/idle state indicator.
        static let loadingIndicator = "player.loading"

        /// Error state view with retry button.
        static let errorView = "player.error"

        /// Buffering overlay shown during rebuffering.
        static let bufferingOverlay = "player.buffering"
    }

    // MARK: - Controls

    enum Controls {
        /// The controls overlay container (wraps all control buttons).
        static let overlay = "controls.overlay"

        /// Expand to fullscreen button.
        static let expandButton = "controls.expand"

        /// Close/dismiss button (fullscreen → embedded or dismiss).
        static let closeButton = "controls.close"

        /// Center play/pause toggle.
        static let playPauseButton = "controls.playPause"

        /// Skip backward button.
        static let skipBackwardButton = "controls.skipBackward"

        /// Skip forward button.
        static let skipForwardButton = "controls.skipForward"

        /// Skip ad button.
        static let skipAdButton = "controls.skipAd"

        /// Closed captions toggle.
        static let ccButton = "controls.cc"

        /// Mute/unmute toggle.
        static let muteButton = "controls.mute"

        /// Share button.
        static let shareButton = "controls.share"

        /// Seek/progress slider.
        static let seekBar = "controls.seekBar"

        /// Time display (current / duration).
        static let timeDisplay = "controls.timeDisplay"

        /// Ad progress banner ("Ad 1 of 3").
        static let adProgressBanner = "controls.adProgress"
    }

    // MARK: - List

    enum VideoList {
        /// The video list navigation stack.
        static let container = "videoList.container"

        /// The embedded player section in the list.
        static let embeddedSection = "videoList.embeddedSection"

        /// A video row in the "All Videos" section. Append video ID for uniqueness.
        static func videoRow(id: String) -> String {
            "videoList.row.\(id)"
        }
    }
}
