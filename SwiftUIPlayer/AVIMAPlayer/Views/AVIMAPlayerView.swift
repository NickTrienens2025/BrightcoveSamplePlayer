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

    /// Whether to show the navigation bar title and toolbar chrome.
    /// Set to false when embedding the player inline (e.g. AVIMAEmbeddedPlayerView).
    private let showNavigationChrome: Bool

    /// Whether to clean up the ViewModel when this view disappears.
    /// Set to false when sharing a ViewModel with a fullscreen cover so the
    /// embedded player's ViewModel isn't destroyed on fullscreen dismissal.
    private let cleanupOnDisappear: Bool

    /// Callback invoked when the expand/fullscreen button is tapped.
    /// When non-nil, an expand button is rendered as the last element of the player
    /// ZStack so it wins UIKit hit-testing over IMA's content (including during ads).
    private let onExpand: (() -> Void)?

    /// Callback invoked when the close button in the controls overlay is tapped.
    /// When non-nil, a close (X) button is rendered at the top-leading position
    /// of the controls overlay. Used in fullscreen mode to dismiss without a nav bar.
    private let onClose: (() -> Void)?

    /// When true, suppresses AVPlayerViewController rendering to avoid the
    /// two-AVPlayerViewController-one-AVPlayer display conflict that occurs when
    /// a fullscreen cover shares the same AVPlayer as this embedded player.
    /// The embedded player renders Color.black as a placeholder while the
    /// fullscreen cover is visible.
    private let suppressPlayerView: Bool

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
    init(videoId: String, allowsFullscreen: Bool = false, showNavigationChrome: Bool = true, cleanupOnDisappear: Bool = true, suppressPlayerView: Bool = false, onExpand: (() -> Void)? = nil, onClose: (() -> Void)? = nil, viewModel: AVIMAPlayerViewModel? = nil) {
        self.videoSource = .id(videoId)
        self.allowsFullscreen = allowsFullscreen
        self.showNavigationChrome = showNavigationChrome
        self.cleanupOnDisappear = cleanupOnDisappear
        self.suppressPlayerView = suppressPlayerView
        self.onExpand = onExpand
        self.onClose = onClose
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
    init(video: AVIMAVideoItem, allowsFullscreen: Bool = false, showNavigationChrome: Bool = true, cleanupOnDisappear: Bool = true, suppressPlayerView: Bool = false, onExpand: (() -> Void)? = nil, onClose: (() -> Void)? = nil, viewModel: AVIMAPlayerViewModel? = nil) {
        self.videoSource = .item(video)
        self.allowsFullscreen = allowsFullscreen
        self.showNavigationChrome = showNavigationChrome
        self.cleanupOnDisappear = cleanupOnDisappear
        self.suppressPlayerView = suppressPlayerView
        self.onExpand = onExpand
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: viewModel ?? AVIMAPlayerViewModel())
    }

    // MARK: - Body

    var body: some View {
        if showNavigationChrome {
            playerCore
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
                .toolbarBackground(Color.black.opacity(0.5), for: .navigationBar)
        } else {
            playerCore
        }
    }

    // Core player ZStack, shared between embedded and fullscreen presentations.
    //
    // IMPORTANT: UIViewControllerRepresentable (AdContainerView) embeds its child
    // VC's view at the UIKit level, where it can end up on top of sibling SwiftUI
    // views regardless of ZStack order. All interactive controls (expand button,
    // ad controls, tap captures) must therefore live INSIDE AdContainerView's
    // content (HC2) to be reliably tappable.
    private var playerCore: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // All interactive controls are inside this content closure (HC2),
            // where UIKit hit-testing is reliable.
            AdContainerView(
                viewModel: viewModel,
                showAdContainer: viewModel.playbackMode == .advertisement,
                aspectRatio: viewModel.videoAspectRatio
            ) {
                content
            }
        }
        .task {
            await loadVideoFromSource()
        }
        .onDisappear {
            if cleanupOnDisappear { viewModel.onDisappear() }
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
                // During ad playback the background must be transparent so IMA's
                // imaContainerView (behind hostingController.view in UIKit) can show
                // through. For all other modes a black background is correct.
                if viewModel.playbackMode != .advertisement {
                    Color.black
                        .ignoresSafeArea()
                }

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

    /// Ad playback view — IMA renders in imaContainerView (behind hostingController.view).
    ///
    /// The transparent base passes touches through to IMA: UIHostingController's
    /// hitTest returns nil for allowsHitTesting(false) areas, so UIKit falls back
    /// to imaContainerView. Controls sit on top with allowsHitTesting(true).
    ///
    /// **Expand button placement:**
    /// The Button is placed directly in the ZStack (no VStack+Spacer wrapper).
    /// A plain Button's UIKit frame is exactly its visual size (~49×49 pt), so
    /// UIKit's hitTest returns nil for touches outside it and falls through to
    /// adControlsOverlay. A VStack+Spacer wrapper would make the entire VStack
    /// frame the UIKit hit target, routing all touches to the Button.
    @ViewBuilder
    private var adPlaybackView: some View {
        ZStack(alignment: .topLeading) {
            // Touch-absorbing base layer.
            //
            // SwiftUI ZStack hit-testing quirk: when no child in the ZStack claims
            // a touch, SwiftUI can route it to the ONLY interactive child (the expand
            // Button) regardless of whether the touch is within the Button's visual
            // frame. This Color.clear with .contentShape + .onTapGesture ensures the
            // base layer claims all uncaught taps, preventing them from reaching the
            // expand button. The tap toggles controls as a useful fallback action.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.toggleControls()
                }

            // Top-leading buttons BEFORE ad controls so controls get higher hit-test
            // priority (SwiftUI checks last ZStack child first). These buttons are
            // at top-leading, ad controls are at bottom — no visual overlap.
            // Visibility synced with controls (always visible during ads since
            // hideControls() guards against .advertisement mode).
            HStack(spacing: 8) {
                if let onClose {
                    Button(action: {
                        onClose()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                if let onExpand {
                    Button(action: {
                        onExpand()
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expand to fullscreen")
                }
            }
            .padding(10)
            .opacity(viewModel.showingControls ? 1 : 0)
            .allowsHitTesting(viewModel.showingControls)

            // Ad controls — last in ZStack so they win hit-testing over expand button.
            // showingControls is always true during ad playback
            // (hideControls() guards against the .advertisement mode).
            adControlsOverlay
        }
    }

    /// Custom controls for ad playback, constrained to the video aspect ratio.
    @ViewBuilder
    private var adControlsOverlay: some View {
        ControlsOverlay(aspectRatio: viewModel.videoAspectRatio) {
            AVIMAAdControlsView(viewModel: viewModel, showMute: false)
        }
        .opacity(viewModel.showingControls ? 1 : 0)
        .allowsHitTesting(viewModel.showingControls)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showingControls)
    }

    /// Main video player view with native controls
    @ViewBuilder
    private func mainVideoPlayerView(player: AVPlayer) -> some View {
        ZStack {
            // Suppress PlayerViewRepresentable while a fullscreen cover is active:
            // two AVPlayerViewController instances sharing one AVPlayer causes the
            // most-recently-created VC to take over display, leaving the other blank.
            // When suppressPlayerView=true the embedded player shows black and lets
            // the fullscreen cover's AVPlayerViewController hold the player display.
            if !suppressPlayerView {
                PlayerViewRepresentable(
                    player: player,
                    viewModel: viewModel,
                    isAdPlayer: false,
                    allowsFullscreen: allowsFullscreen
                )
            } else {
                Color.black.ignoresSafeArea()
            }

            // Tap-to-toggle-controls overlay.
            // Always active — tapping empty space shows or dismisses controls.
            // Sits behind ControlsOverlay so buttons get hit-test priority;
            // the gradient background has allowsHitTesting(false) so taps on
            // empty areas fall through to this layer.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.toggleControls()
                }

            // Custom controls overlay — expand button lives inside VideoPlayerControlsView
            // at the leading top position so it never overlaps trailing CC/Mute buttons.
            // Last in ZStack so buttons win hit-testing over the tap overlay above.
            ControlsOverlay(aspectRatio: viewModel.videoAspectRatio) {
                VideoPlayerControlsView(
                    configuration: .fullMainVideo,
                    delegate: viewModel,
                    onExpandAction: onExpand,
                    onCloseAction: onClose
                )
            }
            .opacity(viewModel.showingControls ? 1 : 0)
            .allowsHitTesting(viewModel.showingControls)
            .animation(.easeInOut(duration: 0.2), value: viewModel.showingControls)
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
///
/// **Shared imaContainerView:**
/// The IMA rendering surface (`viewModel.imaContainerView`) is owned by the ViewModel
/// so it survives fullscreen ↔ embedded transitions. `viewWillAppear` reparents it into
/// this VC's view via `insertSubview` (UIKit removes it from the previous parent automatically),
/// ensuring IMA always renders in whichever player is currently on screen — even when
/// the user opens fullscreen while an ad is playing.
private class AdContainerViewController<Content: View>: UIViewController {

    let viewModel: AVIMAPlayerViewModel
    var hostingController: UIHostingController<Content>

    /// Current aspect ratio, stored for manual frame layout in viewDidLayoutSubviews.
    private var currentAspectRatio: Double = 16.0 / 9.0

    init(viewModel: AVIMAPlayerViewModel, content: Content) {
        self.viewModel = viewModel
        self.hostingController = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let container = viewModel.imaContainerView

        // Reparent the shared IMA container into this VC's view if needed.
        // This fires on initial appearance AND when the embedded VC reappears after
        // a fullscreen cover is dismissed, smoothly claiming the IMA rendering surface
        // back from the (now-gone) fullscreen VC.
        if container.superview !== view {
            container.removeFromSuperview()
            view.insertSubview(container, at: 0)   // Behind hostingController.view
            view.setNeedsLayout()
        }

        viewModel.setAdContainer(containerView: container, viewController: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Add the SwiftUI hosting view on top. The shared imaContainerView (from the
        // ViewModel) is added in viewWillAppear so it can move between embedded and
        // fullscreen VCs without constraint conflicts.
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.view.backgroundColor = .clear  // Transparent so IMA shows through
        hostingController.view.isOpaque = false
        hostingController.didMove(toParent: self)
    }

    // MARK: - IMA Container Layout

    /// Aspect-fit layout for the shared IMA container, matching the original
    /// AutoLayout behavior (fill width when possible, constrained by view height).
    private func layoutIMAContainerIfNeeded() {
        let container = viewModel.imaContainerView
        guard container.superview === view,
              view.bounds.width > 0, view.bounds.height > 0 else { return }

        let ratio = currentAspectRatio
        let vw = view.bounds.width
        let vh = view.bounds.height

        // Aspect-fit: fill width unless that would exceed the height.
        let containerWidth: CGFloat
        let containerHeight: CGFloat
        if vw / vh >= ratio {
            // Wider than the aspect ratio → constrained by height
            containerHeight = vh
            containerWidth = vh * ratio
        } else {
            // Taller than the aspect ratio → fill width
            containerWidth = vw
            containerHeight = vw / ratio
        }

        container.frame = CGRect(
            x: (vw - containerWidth) / 2,
            y: (vh - containerHeight) / 2,
            width: containerWidth,
            height: containerHeight
        )
    }

    func updateAspectRatio(_ aspectRatio: Double) {
        guard aspectRatio != currentAspectRatio else { return }
        currentAspectRatio = aspectRatio
        view.setNeedsLayout()
        debugPrintWithTimestamp("📐 Updated IMA container aspect ratio to \(aspectRatio)")
    }

    func setAdContainerVisible(_ visible: Bool) {
        let currentlyHidden = viewModel.imaContainerView.isHidden
        let shouldHide = !visible
        guard currentlyHidden != shouldHide else { return }
        debugPrintWithTimestamp("📺 Setting IMA container visible: \(visible)")
        viewModel.imaContainerView.isHidden = shouldHide
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        hostingController.view.frame = view.bounds
        layoutIMAContainerIfNeeded()

        // Tell IMA to re-fit its internal subviews to the updated container bounds.
        let container = viewModel.imaContainerView
        if container.superview === view {
            container.setNeedsLayout()
            container.layoutIfNeeded()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        }, completion: { [weak self] _ in
            guard let self, self.viewModel.imaContainerView.superview === self.view else { return }
            self.viewModel.imaContainerView.setNeedsLayout()
            self.viewModel.imaContainerView.layoutIfNeeded()
        })
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

        // Disable Picture-in-Picture to remove the system PiP button overlay
        controller.allowsPictureInPicturePlayback = false

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
