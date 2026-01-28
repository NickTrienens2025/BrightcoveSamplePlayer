//
//  VideoPlayerControlsConfiguration.swift
//  SwiftUIPlayer
//
//  Configuration system for reusable video player controls.
//

import AVFoundation
import SwiftUI

// MARK: - Control Actions

/// Actions that can be triggered by video player controls
enum VideoPlayerControlAction: Equatable {
    case play
    case pause
    case togglePlayPause
    case mute
    case unmute
    case toggleMute
    case seek(to: TimeInterval)
    case skipBackward(TimeInterval)
    case skipForward(TimeInterval)
    case skipAd
    case toggleClosedCaptions
    case close
    case share
}

// MARK: - Controls Delegate

/// Protocol for objects that handle video player control actions
@MainActor
protocol VideoPlayerControlsDelegate: AnyObject {
    /// Handle a control action
    func handleControlAction(_ action: VideoPlayerControlAction)

    // Playback state
    var isPlaying: Bool { get }
    var isMuted: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var playbackProgress: Double { get }

    // Capabilities
    var canSeek: Bool { get }
    var canSkip: Bool { get }

    // Closed captions
    var closedCaptionsEnabled: Bool { get }
    var availableClosedCaptions: [AVMediaSelectionOption] { get }

    // Ad-specific
    var adProgress: AdProgressInfo? { get }
}

/// Ad progress information (independent of ViewModel implementation)
struct AdProgressInfo: Equatable {
    let currentAdNumber: Int
    let totalAds: Int
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isSkippable: Bool
    let skipTimeRemaining: TimeInterval?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }
}


// MARK: - Configuration Structs

/// Main configuration for video player controls
struct VideoPlayerControlsConfiguration {
    /// Layout configuration (which sections to show)
    let layout: ControlLayout

    /// Button visibility and positioning
    let buttons: ButtonConfiguration

    /// Progress bar configuration
    let progress: ProgressConfiguration

    /// Styling options
    let style: ControlsStyle
}

/// Defines which control sections are visible
struct ControlLayout: Equatable {
    let showTopBar: Bool
    let showCenterButton: Bool
    let showBottomBar: Bool
    let showTimeLabels: Bool
}

/// Button visibility and configuration
struct ButtonConfiguration: Equatable {
    // Top bar buttons
    let closeButton: ButtonPosition?
    let shareButton: ButtonPosition?
    let ccButton: ButtonPosition?
    let muteButton: ButtonPosition?

    // Center button
    let playPauseButton: PlayPauseStyle?

    // Bottom transport controls
    let skipBackward: TimeInterval?  // nil = hidden, value = skip duration
    let skipForward: TimeInterval?
    let skipAd: Bool
}

/// Button position in horizontal layout
enum ButtonPosition: String, Equatable {
    case leading
    case trailing
}

/// Play/pause button style
enum PlayPauseStyle: String, Equatable {
    case large   // 60pt for center
    case medium  // 44pt for transport row
    case small   // 32pt compact
}

/// Progress bar configuration
struct ProgressConfiguration: Equatable {
    let showSeekBar: Bool              // Interactive seek bar
    let showNonInteractiveProgress: Bool  // Read-only progress indicator
    let showAdProgress: Bool           // Ad-specific progress info
}

/// Visual styling options
struct ControlsStyle: Equatable {
    let primaryColor: Color
    let backgroundColor: Color
    let gradientBackground: Bool
    let buttonBackdrop: Bool  // Semi-transparent circle behind buttons

    static func == (lhs: ControlsStyle, rhs: ControlsStyle) -> Bool {
        // Compare all properties except Color (which isn't Equatable)
        lhs.gradientBackground == rhs.gradientBackground &&
        lhs.buttonBackdrop == rhs.buttonBackdrop
    }
}

// MARK: - Preset Configurations

extension VideoPlayerControlsConfiguration {
    /// Full controls for main video playback
    ///
    /// Includes: CC, mute, play/pause, seek bar, time labels, skip forward/backward
    static let fullMainVideo = VideoPlayerControlsConfiguration(
        layout: ControlLayout(
            showTopBar: true,
            showCenterButton: false,  // Use bottom transport instead
            showBottomBar: true,
            showTimeLabels: true
        ),
        buttons: ButtonConfiguration(
            closeButton: nil,  // Navigation handles close
            shareButton: nil,
            ccButton: .trailing,
            muteButton: .trailing,
            playPauseButton: .medium,  // In transport row
            skipBackward: 10,
            skipForward: 10,
            skipAd: false
        ),
        progress: ProgressConfiguration(
            showSeekBar: true,
            showNonInteractiveProgress: false,
            showAdProgress: false
        ),
        style: ControlsStyle(
            primaryColor: .white,
            backgroundColor: .clear,
            gradientBackground: true,
            buttonBackdrop: true
        )
    )

    /// Limited controls for ad playback
    ///
    /// Includes: Mute, play/pause (bottom right), ad counter, skip ad button
    static let adPlayback = VideoPlayerControlsConfiguration(
        layout: ControlLayout(
            showTopBar: true,
            showCenterButton: false,
            showBottomBar: true,
            showTimeLabels: false
        ),
        buttons: ButtonConfiguration(
            closeButton: nil,
            shareButton: nil,
            ccButton: nil,  // Ads don't support CC
            muteButton: .trailing,
            playPauseButton: .small,  // Small button bottom right
            skipBackward: nil,
            skipForward: nil,
            skipAd: true
        ),
        progress: ProgressConfiguration(
            showSeekBar: false,
            showNonInteractiveProgress: true,
            showAdProgress: true
        ),
        style: ControlsStyle(
            primaryColor: .white,
            backgroundColor: .clear,
            gradientBackground: true,
            buttonBackdrop: true
        )
    )

    /// Minimal overlay (close + mute + play/pause only)
    ///
    /// Useful for embedded players or picture-in-picture mode
    static let minimal = VideoPlayerControlsConfiguration(
        layout: ControlLayout(
            showTopBar: true,
            showCenterButton: true,
            showBottomBar: false,
            showTimeLabels: false
        ),
        buttons: ButtonConfiguration(
            closeButton: .leading,
            shareButton: nil,
            ccButton: nil,
            muteButton: .trailing,
            playPauseButton: .large,  // Large center button
            skipBackward: nil,
            skipForward: nil,
            skipAd: false
        ),
        progress: ProgressConfiguration(
            showSeekBar: false,
            showNonInteractiveProgress: false,
            showAdProgress: false
        ),
        style: ControlsStyle(
            primaryColor: .white,
            backgroundColor: .clear,
            gradientBackground: false,
            buttonBackdrop: true
        )
    )
}
