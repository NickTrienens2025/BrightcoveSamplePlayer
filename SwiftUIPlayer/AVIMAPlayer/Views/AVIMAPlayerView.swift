//
//  AVIMAPlayerView.swift
//  SwiftUIPlayer
//
//  Main video player view with IMA ad integration and dual-player architecture.
//

import AVFoundation
import AVKit
import SwiftUI

/// Main video player view with integrated IMA ads support.
///
/// **Architecture:**
/// - Dual player setup (main video + ad player)
/// - Main video buffers while ad plays
/// - Unified controls adapt to playback mode
/// - Complete state management via ViewModel
///
/// **State Management:**
/// Uses LoadResult pattern from Shared utilities for initialization state.
/// All player state is managed in `AVIMAPlayerViewModel` with closed loops.
///
/// **User Experience:**
/// - Consistent controls in both playback modes
/// - Clear visual feedback for ad vs main content
/// - Loading states with progress indicators
/// - Error handling with retry capability
struct AVIMAPlayerView: View {

    // MARK: - Properties

    @StateObject private var viewModel: AVIMAPlayerViewModel

    /// Video ID or full video item
    private let videoSource: VideoSource

    /// Whether fullscreen is allowed
    private let allowsFullscreen: Bool

    @Environment(\.dismiss) private var dismiss

    // MARK: - Nested Types

    /// Represents the source of the video (either ID or full item)
    private enum VideoSource {
        case id(String)
        case item(AVIMAVideoItem)

        var displayName: String {
            switch self {
            case .id:
                return "Loading..."
            case .item(let video):
                return video.name
            }
        }
    }

    // MARK: - Initialization

    /// Creates a player view for the specified video ID.
    ///
    /// The video will be fetched from Brightcove using the ID.
    ///
    /// Uses nil default pattern to avoid Swift 6 concurrency errors with
    /// @MainActor ViewModels (per CLAUDE.md standards).
    ///
    /// - Parameter videoId: The Brightcove video ID
    /// - Parameter allowsFullscreen: Whether fullscreen mode is allowed (default: false)
    /// - Parameter viewModel: Optional ViewModel for testing
    init(videoId: String, allowsFullscreen: Bool = false, viewModel: AVIMAPlayerViewModel? = nil) {
        self.videoSource = .id(videoId)
        self.allowsFullscreen = allowsFullscreen
        _viewModel = StateObject(wrappedValue: viewModel ?? AVIMAPlayerViewModel())
    }

    /// Creates a player view for the specified video item.
    ///
    /// Uses the full video item directly without fetching from Brightcove.
    ///
    /// Uses nil default pattern to avoid Swift 6 concurrency errors with
    /// @MainActor ViewModels (per CLAUDE.md standards).
    ///
    /// - Parameter video: The video to play
    /// - Parameter allowsFullscreen: Whether fullscreen mode is allowed (default: false)
    /// - Parameter viewModel: Optional ViewModel for testing
    init(video: AVIMAVideoItem, allowsFullscreen: Bool = false, viewModel: AVIMAPlayerViewModel? = nil) {
        self.videoSource = .item(video)
        self.allowsFullscreen = allowsFullscreen
        _viewModel = StateObject(wrappedValue: viewModel ?? AVIMAPlayerViewModel())
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Ad container view - always present for IMA SDK (positioned in back)
            AdContainerView(
                viewModel: viewModel,
                showAdContainer: viewModel.playbackMode == .advertisement,
                aspectRatio: viewModel.videoAspectRatio
            ) {
                content
            }

            // Custom ad controls rendered OUTSIDE the ad container
            // so IMA's native UI doesn't cover them
            if viewModel.playbackMode == .advertisement {
                adControlsOverlay
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(displayTitle)
                        .font(.headline)
                        .foregroundStyle(.white)

                    if viewModel.playbackMode == .advertisement {
                        Text("Advertisement")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black.opacity(0.8), for: .navigationBar)
        .task {
            await loadVideoFromSource()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    // MARK: - Computed Properties

    /// The title to display in the navigation bar
    private var displayTitle: String {
        if let currentVideo = viewModel.currentVideo {
            return currentVideo.name
        }
        return videoSource.displayName
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.initializationStatus {
        case .notStarted:
            EmptyView()

        case .loading:
            loadingView

        case .error(let error):
            errorView(error: error)

        case .success:
            playerView
        }
    }

    // MARK: - Loading View

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)

            Text("Loading video...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(error: Error) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.yellow)

            VStack(spacing: 8) {
                Text("Playback Error")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task {
                    await loadVideoFromSource()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue)
                )
            }
        }
        .padding()
    }

    // MARK: - Player View

    @ViewBuilder
    private var playerView: some View {
        GeometryReader { geometry in
            // Player content area with native controls
            playerContent(in: geometry.size)
        }
    }

    // MARK: - Player Content

    @ViewBuilder
    private func playerContent(in size: CGSize) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                // Mutually exclusive player states using switch
                playerStateView

                // Buffering overlay (can appear over any state except idle)
                if viewModel.isLoading && viewModel.playbackMode != .idle {
                    bufferingOverlay
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// Mutually exclusive player state view
    @ViewBuilder
    private var playerStateView: some View {
        switch viewModel.playbackMode {
        case .idle:
            // Loading state - waiting for player initialization
            idleStateView

        case .advertisement:
            // Ad playback state - IMA renders directly in container, we just show controls
            // The AdContainerView already provides the UIView that IMA renders into
            adPlaybackView

        case .mainVideo:
            // Main video playback state - native controls
            if let player = viewModel.getMainPlayer() {
                mainVideoPlayerView(player: player)
            } else {
                // Fallback if main player not ready
                errorStateView(message: "Video player unavailable")
            }
        }
    }

    /// Idle state view
    @ViewBuilder
    private var idleStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)

            Text("Loading advertisement...")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    /// Ad playback view - IMA renders in container
    @ViewBuilder
    private var adPlaybackView: some View {
        // IMA is already rendering into the AdContainerView (UIKit layer below)
        // This layer should not block touches to the ad
        // Controls are rendered at top-level ZStack
        Color.clear
            .allowsHitTesting(false)  // Don't block touches to IMA ad below
    }

    /// Custom controls for ad playback - rendered OUTSIDE ad container
    /// Constrained to match the video aspect ratio
    @ViewBuilder
    private var adControlsOverlay: some View {
        ControlsOverlay(aspectRatio: viewModel.videoAspectRatio) {
            VideoPlayerControlsView(
                configuration: .adPlayback,
                delegate: viewModel
            )
        }
        .allowsHitTesting(true)
    }

    /// Main video player view with native controls
    @ViewBuilder
    private func mainVideoPlayerView(player: AVPlayer) -> some View {
        ZStack {
            // Player without native controls
            PlayerViewRepresentable(
                player: player,
                viewModel: viewModel,
                isAdPlayer: false,
                allowsFullscreen: allowsFullscreen
            )

            // Custom controls overlay
            ControlsOverlay(aspectRatio: viewModel.videoAspectRatio) {
                VideoPlayerControlsView(
                    configuration: .fullMainVideo,
                    delegate: viewModel
                )
            }
        }
    }

    /// Error state view
    @ViewBuilder
    private func errorStateView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.yellow)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    /// Buffering overlay
    @ViewBuilder
    private var bufferingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)

            Text("Buffering...")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.7))
        )
    }

    // MARK: - Helper Methods

    /// Loads the video based on the source type
    private func loadVideoFromSource() async {
        switch videoSource {
        case .id(let videoId):
            await viewModel.loadVideo(videoId: videoId)
        case .item(let video):
            await viewModel.loadVideo(video)
        }
    }
}

// MARK: - Ad Container View

/// Container view that provides the UIView and UIViewController needed for IMA ads.
///
/// This view wraps the content and extracts the view controller from the SwiftUI
/// hierarchy to provide to the IMA SDK for ad rendering.
private struct AdContainerView<Content: View>: UIViewControllerRepresentable {

    let viewModel: AVIMAPlayerViewModel
    let showAdContainer: Bool
    let aspectRatio: Double
    let content: () -> Content

    func makeUIViewController(context: Context) -> AdContainerViewController<Content> {
        let controller = AdContainerViewController(
            viewModel: viewModel,
            aspectRatio: aspectRatio,
            content: content()
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: AdContainerViewController<Content>, context: Context) {
        uiViewController.updateContent(content())
        uiViewController.setAdContainerVisible(showAdContainer)
        uiViewController.updateAspectRatio(aspectRatio)
    }
}

/// View controller that hosts SwiftUI content and provides IMA ad container.
private class AdContainerViewController<Content: View>: UIViewController {

    let viewModel: AVIMAPlayerViewModel
    var hostingController: UIHostingController<Content>

    /// Container view specifically for IMA ad rendering (sized to video aspect ratio)
    private let imaContainerView = UIView()

    /// Aspect ratio constraint for IMA container
    private var aspectRatioConstraint: NSLayoutConstraint?

    init(viewModel: AVIMAPlayerViewModel, aspectRatio: Double, content: Content) {
        self.viewModel = viewModel
        self.hostingController = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Add IMA container view first (behind everything)
        imaContainerView.backgroundColor = .clear
        imaContainerView.isHidden = true  // Hidden by default, shown during ads
        view.addSubview(imaContainerView)

        // Disable autoresizing mask so we can use constraints
        imaContainerView.translatesAutoresizingMaskIntoConstraints = false

        // Constrain IMA container to center
        NSLayoutConstraint.activate([
            imaContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imaContainerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            imaContainerView.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])

        // Set initial aspect ratio (will be updated when video loads)
        updateAspectRatio(16.0/9.0)

        // Add hosting controller as child on top (full screen)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.view.backgroundColor = .clear  // Transparent so IMA shows through
        hostingController.view.isOpaque = false  // Ensure transparency works properly
        hostingController.didMove(toParent: self)

        // Set IMA container (not the full view)
        viewModel.setAdContainer(containerView: imaContainerView, viewController: self)
    }

    func updateAspectRatio(_ aspectRatio: Double) {
        // Remove old aspect ratio constraint if it exists
        if let oldConstraint = aspectRatioConstraint {
            oldConstraint.isActive = false
        }

        // Create new aspect ratio constraint (height = width / aspectRatio)
        let newConstraint = imaContainerView.heightAnchor.constraint(
            equalTo: imaContainerView.widthAnchor,
            multiplier: 1.0 / aspectRatio
        )
        newConstraint.isActive = true
        aspectRatioConstraint = newConstraint

        debugPrintWithTimestamp("📐 Updated IMA container aspect ratio to \(aspectRatio) (multiplier: \(1.0/aspectRatio))")
    }

    func setAdContainerVisible(_ visible: Bool) {
        debugPrintWithTimestamp("📺 Setting IMA container visible: \(visible)")
        debugPrintWithTimestamp("   Container frame: \(imaContainerView.frame)")
        debugPrintWithTimestamp("   Container hidden before: \(imaContainerView.isHidden)")

        imaContainerView.isHidden = !visible

        if visible {
            // Bring IMA container to front when showing ads
            view.bringSubviewToFront(imaContainerView)
            debugPrintWithTimestamp("   Brought IMA container to front")
        } else {
            // Send IMA container to back when not showing ads
            view.sendSubviewToBack(imaContainerView)
            debugPrintWithTimestamp("   Sent IMA container to back")
        }

        debugPrintWithTimestamp("   Container hidden after: \(imaContainerView.isHidden)")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Update hosting controller frame
        hostingController.view.frame = view.bounds
    }

    func updateContent(_ content: Content) {
        hostingController.rootView = content
    }
}

// MARK: - Player View Representable

/// UIViewRepresentable wrapper for AVPlayerViewController.
///
/// Displays an AVPlayer in SwiftUI using native UIKit player controls.
/// Includes support for closed captioning, AirPlay, and fullscreen mode.
private struct PlayerViewRepresentable: UIViewControllerRepresentable {

    let player: AVPlayer
    let viewModel: AVIMAPlayerViewModel
    let isAdPlayer: Bool
    let allowsFullscreen: Bool

    init(player: AVPlayer, viewModel: AVIMAPlayerViewModel, isAdPlayer: Bool = false, allowsFullscreen: Bool = false) {
        self.player = player
        self.viewModel = viewModel
        self.isAdPlayer = isAdPlayer
        self.allowsFullscreen = allowsFullscreen
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.videoGravity = .resizeAspect

        // Hide native controls - we use custom VideoPlayerControlsView
        controller.showsPlaybackControls = false

        // Enable AirPlay and Picture-in-Picture
        controller.allowsPictureInPicturePlayback = true

        // Disable fullscreen button if not allowed
        // Note: This doesn't actually hide the button, but we block it in the delegate
        // There's no public API to hide individual control buttons in AVPlayerViewController
        if !allowsFullscreen {
            // Try requiresLinearPlayback - removes some controls but not fullscreen
            // controller.requiresLinearPlayback = true
            // Unfortunately even this doesn't remove the fullscreen button
        }

        // Store reference for fullscreen control
        viewModel.currentPlayerViewController = controller

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Update player if changed
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, allowsFullscreen: allowsFullscreen)
    }

    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let viewModel: AVIMAPlayerViewModel
        let allowsFullscreen: Bool
        private var wasPlayingBeforeFullscreen = false
        private var playbackModeBeforeFullscreen: AVIMAPlayerViewModel.PlaybackMode?

        init(viewModel: AVIMAPlayerViewModel, allowsFullscreen: Bool) {
            self.viewModel = viewModel
            self.allowsFullscreen = allowsFullscreen
        }

        @MainActor func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            // Block fullscreen if not allowed
            guard allowsFullscreen else {
                debugPrintWithTimestamp("🔲 Fullscreen blocked - not allowed")
                return
            }

            debugPrintWithTimestamp("🔲 Entering fullscreen")

            // Save current state
            wasPlayingBeforeFullscreen = viewModel.isPlaying
            playbackModeBeforeFullscreen = viewModel.playbackMode
            debugPrintWithTimestamp("   Was playing: \(wasPlayingBeforeFullscreen), Mode: \(playbackModeBeforeFullscreen ?? .idle)")

            // Resume playback immediately to prevent pause
            if wasPlayingBeforeFullscreen {
                viewModel.play()
            }

            // Also resume after transition completes
            coordinator.animate(alongsideTransition: { _ in
                // Keep playing during animation
                if self.wasPlayingBeforeFullscreen {
                    self.viewModel.play()
                }
            }, completion: { _ in
                // Ensure playback continues after transition
                if self.wasPlayingBeforeFullscreen {
                    DispatchQueue.main.async {
                        self.viewModel.play()
                        debugPrintWithTimestamp("   ✅ Fullscreen entered - playback resumed")
                    }
                }
            })
        }

        @MainActor func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            // Should not happen if fullscreen was blocked, but handle gracefully
            guard allowsFullscreen else {
                debugPrintWithTimestamp("🔲 Fullscreen exit blocked - not allowed")
                return
            }

            debugPrintWithTimestamp("🔲 Exiting fullscreen")
            debugPrintWithTimestamp("   Was playing: \(wasPlayingBeforeFullscreen), Mode: \(playbackModeBeforeFullscreen ?? .idle)")

            // Resume playback immediately to prevent pause
            if wasPlayingBeforeFullscreen {
                viewModel.play()
            }

            // Also resume after transition completes
            coordinator.animate(alongsideTransition: { _ in
                // Keep playing during animation
                if self.wasPlayingBeforeFullscreen {
                    self.viewModel.play()
                }
            }, completion: { _ in
                // Ensure playback continues after transition
                if self.wasPlayingBeforeFullscreen {
                    DispatchQueue.main.async {
                        self.viewModel.play()
                        debugPrintWithTimestamp("   ✅ Fullscreen exited - playback resumed")
                    }
                }
            })
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AVIMAPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AVIMAPlayerView(video: AVIMAVideoItem.samples[0])
        }
        .preferredColorScheme(.dark)
    }
}
#endif
