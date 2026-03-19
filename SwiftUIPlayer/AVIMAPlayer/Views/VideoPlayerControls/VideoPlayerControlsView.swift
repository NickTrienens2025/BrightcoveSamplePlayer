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

    /// Optional expand/fullscreen action. When non-nil, an expand button is shown
    /// at the leading position of the top bar so it never overlaps trailing CC/Mute buttons.
    private let onExpandAction: (() -> Void)?

    /// Optional close action. When non-nil, a close (X) button is shown
    /// at the leading position of the top bar. Used for fullscreen dismiss.
    private let onCloseAction: (() -> Void)?

    // MARK: - Initialization

    init(
        configuration: VideoPlayerControlsConfiguration,
        delegate: VideoPlayerControlsDelegate,
        onExpandAction: (() -> Void)? = nil,
        onCloseAction: (() -> Void)? = nil
    ) {
        self.configuration = configuration
        self.stateProvider = VideoPlayerControlsStateProvider(delegate: delegate)
        self.onExpandAction = onExpandAction
        self.onCloseAction = onCloseAction
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 200

            VStack(spacing: 0) {
                // Top bar
                if configuration.layout.showTopBar {
                    topControlsBar
                        .padding(.horizontal, 12)
                        .padding(.top, isCompact ? 4 : 8)
                }

                Spacer()

                // Center transport: skip back / play-pause / skip forward
                if configuration.layout.showCenterButton || configuration.buttons.skipBackward != nil || configuration.buttons.skipForward != nil,
                   let style = configuration.buttons.playPauseButton {
                    centerTransportControls(style: style, compact: isCompact)
                }

                Spacer()

                // Bottom controls (seek bar + time)
                if configuration.layout.showBottomBar {
                    bottomControlsBar
                        .padding(.horizontal, 12)
                        .padding(.bottom, isCompact ? 4 : 12)
                }
            }
        }
        .background(backgroundGradient.allowsHitTesting(false))
    }

    // MARK: - Top Controls Bar

    @ViewBuilder
    private var topControlsBar: some View {
        HStack(spacing: 16) {
            // Close button — leading position for fullscreen dismiss.
            if let onCloseAction {
                closeOverlayButton(action: onCloseAction)
            }

            // Expand button — leading position so it never overlaps trailing CC/Mute buttons.
            if let onExpandAction {
                expandButton(action: onExpandAction)
            }

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

    // MARK: - Center Transport Controls

    /// Center row: skip backward / play-pause / skip forward
    /// Uses clean borderless icons for a modern look (YouTube/Netflix style).
    /// Scales down in compact mode (small embedded players).
    @ViewBuilder
    private func centerTransportControls(style: PlayPauseStyle, compact: Bool) -> some View {
        let playSize: CGFloat = {
            switch style {
            case .large: return compact ? 36 : 52
            case .medium: return compact ? 30 : 44
            case .small: return compact ? 22 : 30
            }
        }()

        let skipSize: CGFloat = compact ? 20 : 26
        let spacing: CGFloat = compact ? 28 : 40

        HStack(spacing: spacing) {
            // Skip backward
            if let skipDuration = configuration.buttons.skipBackward {
                Button {
                    stateProvider.handleAction(.skipBackward(skipDuration))
                } label: {
                    Image(systemName: "gobackward.\(Int(skipDuration))")
                        .font(.system(size: skipSize, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip back \(Int(skipDuration)) seconds")
                .accessibilityIdentifier(AccessibilityID.Controls.skipBackwardButton)
            }

            // Play / pause
            Button {
                stateProvider.handleAction(.togglePlayPause)
            } label: {
                Image(systemName: stateProvider.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: playSize, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(stateProvider.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier(AccessibilityID.Controls.playPauseButton)

            // Skip forward
            if let skipDuration = configuration.buttons.skipForward {
                Button {
                    stateProvider.handleAction(.skipForward(skipDuration))
                } label: {
                    Image(systemName: "goforward.\(Int(skipDuration))")
                        .font(.system(size: skipSize, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip forward \(Int(skipDuration)) seconds")
                .accessibilityIdentifier(AccessibilityID.Controls.skipForwardButton)
            }
        }
    }

    // MARK: - Bottom Controls Bar

    @ViewBuilder
    private var bottomControlsBar: some View {
        VStack(spacing: 8) {
            // Ad progress banner
            if configuration.progress.showAdProgress,
               let adProgress = stateProvider.adProgress {
                adProgressBanner(adProgress)
            }

            // Ad-specific bottom row (play/pause + skip ad)
            if configuration.buttons.skipAd {
                HStack(spacing: 16) {
                    // Small play/pause for ads
                    if let style = configuration.buttons.playPauseButton {
                        Button {
                            stateProvider.handleAction(.togglePlayPause)
                        } label: {
                            Image(systemName: stateProvider.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: style == .small ? 16 : 20))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(stateProvider.isPlaying ? "Pause" : "Play")
                    }

                    Spacer()

                    if stateProvider.canSkip {
                        skipAdButton
                    }
                }
            }

            // Seek bar — full width, above time row
            if configuration.progress.showSeekBar {
                seekProgressBar
            } else if configuration.progress.showNonInteractiveProgress {
                nonInteractiveProgressBar
            }

            // Time labels row — below seek bar
            if configuration.layout.showTimeLabels {
                timeRow
            }
        }
    }

    // MARK: - Individual Controls

    private func closeOverlayButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier(AccessibilityID.Controls.closeButton)
    }

    private func expandButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand to fullscreen")
        .accessibilityIdentifier(AccessibilityID.Controls.expandButton)
    }

    private var closeButton: some View {
        Button {
            stateProvider.handleAction(.close)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier(AccessibilityID.Controls.closeButton)
    }

    private var shareButton: some View {
        Button {
            stateProvider.handleAction(.share)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
        .accessibilityIdentifier(AccessibilityID.Controls.shareButton)
    }

    private var closedCaptionButton: some View {
        Button {
            stateProvider.handleAction(.toggleClosedCaptions)
        } label: {
            Image(systemName: stateProvider.closedCaptionsEnabled ?
                "captions.bubble.fill" : "captions.bubble")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Closed Captions")
        .accessibilityIdentifier(AccessibilityID.Controls.ccButton)
    }

    private var muteButton: some View {
        Button {
            stateProvider.handleAction(.toggleMute)
        } label: {
            Image(systemName: stateProvider.isMuted ?
                "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stateProvider.isMuted ? "Unmute" : "Mute")
        .accessibilityIdentifier(AccessibilityID.Controls.muteButton)
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
        .accessibilityIdentifier(AccessibilityID.Controls.skipAdButton)
    }

    // MARK: - Progress Bars

    @ViewBuilder
    private var seekProgressBar: some View {
        // Slider with midroll markers overlaid.
        // Uses .overlay instead of ZStack+GeometryReader to avoid
        // the greedy GeometryReader expanding and stealing Spacer space.
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
        .accessibilityIdentifier(AccessibilityID.Controls.seekBar)
        .overlay {
            // Midroll marker dots on the slider track
            if !stateProvider.midrollMarkerPositions.isEmpty {
                GeometryReader { geometry in
                    ForEach(stateProvider.midrollMarkerPositions, id: \.self) { position in
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 8, height: 8)
                            .position(
                                x: geometry.size.width * position,
                                y: geometry.size.height / 2
                            )
                    }
                }
                .allowsHitTesting(false)
            }
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

    /// Time row below the seek bar: current time left, remaining/total right
    @ViewBuilder
    private var timeRow: some View {
        HStack {
            Text(formatTime(stateProvider.currentTime))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Text(formatTime(stateProvider.duration))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityIdentifier(AccessibilityID.Controls.timeDisplay)
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
        .accessibilityIdentifier(AccessibilityID.Controls.adProgressBanner)
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
    @Published var midrollMarkerPositions: [Double] = []

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
        midrollMarkerPositions = delegate.midrollMarkerPositions
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
    var midrollMarkerPositions: [Double] = [0.5]

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
