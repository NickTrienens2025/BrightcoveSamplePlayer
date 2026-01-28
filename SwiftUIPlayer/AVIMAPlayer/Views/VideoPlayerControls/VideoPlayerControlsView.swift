//
//  VideoPlayerControlsView.swift
//  SwiftUIPlayer
//
//  Reusable, configurable video player controls component.
//  Clean isolation - no business logic, purely presentational.
//

import AVFoundation
import SwiftUI

/// Reusable video player controls with configuration-based visibility
///
/// **Design Principles:**
/// - Fully configurable via `VideoPlayerControlsConfiguration`
/// - No business logic (purely presentational)
/// - Delegate pattern for actions
/// - Accessibility built-in
/// - Clean isolation from player implementation
///
/// **Usage:**
/// ```swift
/// VideoPlayerControlsView(
///     configuration: .fullMainVideo,
///     delegate: viewModel
/// )
/// ```
struct VideoPlayerControlsView: View {

    // MARK: - Properties

    /// Configuration defining which controls to show
    let configuration: VideoPlayerControlsConfiguration

    /// State provider for reactive updates
    @ObservedObject var stateProvider: VideoPlayerControlsStateProvider

    // MARK: - Initialization

    init(
        configuration: VideoPlayerControlsConfiguration,
        delegate: VideoPlayerControlsDelegate
    ) {
        self.configuration = configuration
        self.stateProvider = VideoPlayerControlsStateProvider(delegate: delegate)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            if configuration.layout.showTopBar {
                topControlsBar
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            Spacer()

            // Center play/pause
            if configuration.layout.showCenterButton,
               let style = configuration.buttons.playPauseButton {
                centerPlayPauseButton(style: style)
            }

            Spacer()

            // Bottom controls
            if configuration.layout.showBottomBar {
                bottomControlsBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(backgroundGradient)
    }

    // MARK: - Top Controls Bar

    @ViewBuilder
    private var topControlsBar: some View {
        HStack(spacing: 16) {
            // Leading buttons
            if let closePosition = configuration.buttons.closeButton,
               closePosition == .leading {
                closeButton
            }

            if let sharePosition = configuration.buttons.shareButton,
               sharePosition == .leading {
                shareButton
            }

            Spacer()

            // Trailing buttons
            if let ccPosition = configuration.buttons.ccButton,
               ccPosition == .trailing {
                closedCaptionButton
            }

            if let mutePosition = configuration.buttons.muteButton,
               mutePosition == .trailing {
                muteButton
            }

            if let closePosition = configuration.buttons.closeButton,
               closePosition == .trailing {
                closeButton
            }

            if let sharePosition = configuration.buttons.shareButton,
               sharePosition == .trailing {
                shareButton
            }
        }
    }

    // MARK: - Center Play/Pause

    @ViewBuilder
    private func centerPlayPauseButton(style: PlayPauseStyle) -> some View {
        let size: CGFloat = {
            switch style {
            case .large: return 60
            case .medium: return 44
            case .small: return 32
            }
        }()

        ControlButton(
            systemImage: stateProvider.isPlaying ? "pause.fill" : "play.fill",
            size: size,
            accessibilityLabel: stateProvider.isPlaying ? "Pause" : "Play"
        ) {
            stateProvider.handleAction(.togglePlayPause)
        }
    }

    // MARK: - Bottom Controls Bar

    @ViewBuilder
    private var bottomControlsBar: some View {
        VStack(spacing: 12) {
            // Ad progress banner
            if configuration.progress.showAdProgress,
               let adProgress = stateProvider.adProgress {
                adProgressBanner(adProgress)
            }

            // Progress bar
            if configuration.progress.showSeekBar {
                seekProgressBar
            } else if configuration.progress.showNonInteractiveProgress {
                nonInteractiveProgressBar
            }

            // Transport controls
            HStack(spacing: 24) {
                // Time labels
                if configuration.layout.showTimeLabels {
                    timeLabels
                    Spacer()
                }

                // Skip backward
                if let skipDuration = configuration.buttons.skipBackward {
                    skipBackwardButton(duration: skipDuration)
                }

                // Play/pause (if not centered)
                if configuration.layout.showCenterButton == false,
                   let style = configuration.buttons.playPauseButton {
                    centerPlayPauseButton(style: style)
                }

                // Skip forward
                if let skipDuration = configuration.buttons.skipForward {
                    skipForwardButton(duration: skipDuration)
                }

                // Skip ad button
                if configuration.buttons.skipAd,
                   stateProvider.canSkip {
                    skipAdButton
                }

                if !configuration.layout.showTimeLabels {
                    Spacer()
                }
            }
        }
    }

    // MARK: - Individual Controls

    private var closeButton: some View {
        ControlButton(
            systemImage: "xmark",
            size: 24,
            accessibilityLabel: "Close"
        ) {
            stateProvider.handleAction(.close)
        }
    }

    private var shareButton: some View {
        ControlButton(
            systemImage: "square.and.arrow.up",
            size: 24,
            accessibilityLabel: "Share"
        ) {
            stateProvider.handleAction(.share)
        }
    }

    private var closedCaptionButton: some View {
        ControlButton(
            systemImage: stateProvider.closedCaptionsEnabled ?
                "captions.bubble.fill" : "captions.bubble",
            size: 24,
            accessibilityLabel: "Closed Captions"
        ) {
            stateProvider.handleAction(.toggleClosedCaptions)
        }
    }

    private var muteButton: some View {
        ControlButton(
            systemImage: stateProvider.isMuted ?
                "speaker.slash.fill" : "speaker.wave.2.fill",
            size: 24,
            accessibilityLabel: stateProvider.isMuted ? "Unmute" : "Mute"
        ) {
            stateProvider.handleAction(.toggleMute)
        }
    }

    private func skipBackwardButton(duration: TimeInterval) -> some View {
        ControlButton(
            systemImage: "gobackward.\(Int(duration))",
            size: 32,
            accessibilityLabel: "Skip back \(Int(duration)) seconds"
        ) {
            stateProvider.handleAction(.skipBackward(duration))
        }
    }

    private func skipForwardButton(duration: TimeInterval) -> some View {
        ControlButton(
            systemImage: "goforward.\(Int(duration))",
            size: 32,
            accessibilityLabel: "Skip forward \(Int(duration)) seconds"
        ) {
            stateProvider.handleAction(.skipForward(duration))
        }
    }

    private var skipAdButton: some View {
        Button {
            stateProvider.handleAction(.skipAd)
        } label: {
            HStack(spacing: 4) {
                Text("Skip")
                    .font(.caption.weight(.semibold))
                Image(systemName: "forward.fill")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.3))
            )
        }
        .accessibilityLabel("Skip Ad")
    }

    // MARK: - Progress Bars

    @ViewBuilder
    private var seekProgressBar: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { stateProvider.currentTime },
                    set: { newValue in
                        stateProvider.handleAction(.seek(to: newValue))
                    }
                ),
                in: 0...max(stateProvider.duration, 1)
            )
            .tint(.white)
            .disabled(!stateProvider.canSeek)
        }
    }

    @ViewBuilder
    private var nonInteractiveProgressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.3))
                    .frame(height: 4)

                // Progress
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white)
                    .frame(
                        width: geometry.size.width * stateProvider.playbackProgress,
                        height: 4
                    )
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder
    private var timeLabels: some View {
        HStack(spacing: 8) {
            Text(formatTime(stateProvider.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)

            Text("/")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            Text(formatTime(stateProvider.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func adProgressBanner(_ adProgress: AdProgressInfo) -> some View {
        HStack {
            Text("Ad \(adProgress.currentAdNumber) of \(adProgress.totalAds)")
                .font(.caption)
                .foregroundStyle(.yellow)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.black.opacity(0.7))
                )

            Spacer()
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundGradient: some View {
        if configuration.style.gradientBackground {
            LinearGradient(
                colors: [
                    .black.opacity(0.7),
                    .clear,
                    .clear,
                    .black.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else { return "0:00" }

        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - State Provider

/// Observable wrapper for delegate state to enable reactive UI updates
@MainActor
class VideoPlayerControlsStateProvider: ObservableObject {

    // MARK: - Properties

    weak var delegate: VideoPlayerControlsDelegate?

    // Mirror delegate properties as @Published for reactivity
    @Published var isPlaying: Bool = false
    @Published var isMuted: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackProgress: Double = 0
    @Published var canSeek: Bool = false
    @Published var canSkip: Bool = false
    @Published var closedCaptionsEnabled: Bool = false
    @Published var adProgress: AdProgressInfo?

    private var updateTimer: Timer?

    // MARK: - Initialization

    init(delegate: VideoPlayerControlsDelegate) {
        self.delegate = delegate
        startPolling()
    }

//    deinit {
//        stopPolling()
//    }

    // MARK: - Actions

    func handleAction(_ action: VideoPlayerControlAction) {
        delegate?.handleControlAction(action)
    }

    // MARK: - State Sync

    private func startPolling() {
        // Poll delegate state at 10 Hz for smooth updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateState()
        }
        updateState()  // Initial update
    }

    private func stopPolling() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateState() {
        guard let delegate = delegate else { return }

        isPlaying = delegate.isPlaying
        isMuted = delegate.isMuted
        currentTime = delegate.currentTime
        duration = delegate.duration
        playbackProgress = delegate.playbackProgress
        canSeek = delegate.canSeek
        canSkip = delegate.canSkip
        closedCaptionsEnabled = delegate.closedCaptionsEnabled
        adProgress = delegate.adProgress
    }
}

// MARK: - Preview

#if DEBUG
// Mock delegate for previews
class MockVideoPlayerControlsDelegate: VideoPlayerControlsDelegate {
    var isPlaying: Bool = false
    var isMuted: Bool = false
    var currentTime: TimeInterval = 45
    var duration: TimeInterval = 180
    var playbackProgress: Double { currentTime / duration }
    var canSeek: Bool = true
    var canSkip: Bool = true
    var closedCaptionsEnabled: Bool = false
    var availableClosedCaptions: [AVMediaSelectionOption] = []
    var adProgress: AdProgressInfo? = AdProgressInfo(
        currentAdNumber: 1,
        totalAds: 2,
        currentTime: 5,
        duration: 15,
        isSkippable: false,
        skipTimeRemaining: nil
    )

    func handleControlAction(_ action: VideoPlayerControlAction) {
        print("Action: \(action)")
    }
}

struct VideoPlayerControlsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Full main video controls
            ZStack {
                Color.black.ignoresSafeArea()
                ControlsOverlay(aspectRatio: 16/9) {
                    VideoPlayerControlsView(
                        configuration: .fullMainVideo,
                        delegate: MockVideoPlayerControlsDelegate()
                    )
                }
            }
            .previewDisplayName("Full Main Video")

            // Ad playback controls
            ZStack {
                Color.black.ignoresSafeArea()
                ControlsOverlay(aspectRatio: 16/9) {
                    VideoPlayerControlsView(
                        configuration: .adPlayback,
                        delegate: MockVideoPlayerControlsDelegate()
                    )
                }
            }
            .previewDisplayName("Ad Playback")

            // Minimal controls
            ZStack {
                Color.black.ignoresSafeArea()
                ControlsOverlay(aspectRatio: 16/9) {
                    VideoPlayerControlsView(
                        configuration: .minimal,
                        delegate: MockVideoPlayerControlsDelegate()
                    )
                }
            }
            .previewDisplayName("Minimal")
        }
    }
}
#endif
