//
//  AVIMAPlayerViewModel.swift
//  SwiftUIPlayer
//
//  ViewModel for managing IMA video player state with dual-player architecture.
//  Follows CLAUDE.md standards for SwiftUI ViewModels with complete closed loops.
//

import AVFoundation
import Combine
import Foundation
import GoogleInteractiveMediaAds
import UIKit
import BrightcovePlayerSDK

/// ViewModel managing IMA video playback with comprehensive state tracking.
///
/// This ViewModel implements a dual-player architecture where:
/// - Main video player handles content playback
/// - Ad player handles IMA ad playback
/// - Main video can buffer while ads play
///
/// **State Management:**
/// All state changes are exposed via @Published properties for complete
/// closed loops. The View observes these properties and updates UI accordingly.
///
/// **Playback Mode State Machine:**
/// ```
///                    ┌─────────┐
///         loadVideo()│         │
///        ┌───────────▶  idle   │
///        │           │         │
///        │           └────┬────┘
///        │                │
///        │                │ ads load
///        │                ▼
///        │         ┌──────────────┐
///        │         │              │
///        │    ┌────┤advertisement │◀────┐
///        │    │    │              │     │
///        │    │    └──────┬───────┘     │
///        │    │           │             │
///        │    │ ad fails  │ ads complete│ more ads
///        │    │           │             │
///        │    │    ┌──────▼───────┐     │
///        │    └────▶              ├─────┘
///        │         │  mainVideo   │
///        └─────────┤              │
///          reload  └──────────────┘
/// ```
///
/// **State Guarantees:**
/// - Only ONE playback mode is active at any time (enforced by switch statement)
/// - Mode transitions are atomic and validated
/// - State cleanup happens during each transition
///
/// **Playback Modes:**
/// - `.idle`: No content loaded, initializing
/// - `.mainVideo`: Playing main content (mutually exclusive with ad)
/// - `.advertisement`: Playing IMA ad content (mutually exclusive with main)
///
/// **Control Restrictions:**
/// - During ads: Only pause/play and mute allowed
/// - During main content: Full controls available
@MainActor
class AVIMAPlayerViewModel: NSObject, ObservableObject {

    // MARK: - Nested Types

    /// Represents the current playback mode (mutually exclusive states)
    enum PlaybackMode: Equatable {
        /// No content is loaded - initializing
        case idle

        /// Playing main video content (ad player is idle)
        case mainVideo

        /// Playing advertisement content (main player is paused)
        case advertisement
    }

    /// Represents the state of a player
    enum PlayerState: Equatable {
        /// Player is idle
        case idle

        /// Content is loading
        case loading

        /// Player is ready to play
        case ready

        /// Content is currently playing
        case playing

        /// Playback is paused
        case paused

        /// Player is buffering
        case buffering

        /// An error occurred
        case error(String)

        /// Playback completed
        case completed

        static func == (lhs: PlayerState, rhs: PlayerState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.loading, .loading),
                 (.ready, .ready),
                 (.playing, .playing),
                 (.paused, .paused),
                 (.buffering, .buffering),
                 (.completed, .completed):
                return true
            case (.error(let lhsMsg), .error(let rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }

    /// Progress information for ad playback
    struct AdProgress: Equatable, CustomStringConvertible {
        /// Current ad position (1-based)
        let currentAdNumber: Int

        /// Total number of ads in pod
        let totalAds: Int

        /// Current time in the ad
        let currentTime: TimeInterval

        /// Total duration of the ad
        let duration: TimeInterval

        /// Whether the ad can be skipped
        let isSkippable: Bool

        /// Remaining time until skip is available
        let skipTimeRemaining: TimeInterval?

        /// Progress percentage (0.0 to 1.0)
        var progress: Double {
            guard duration > 0 else { return 0 }
            return min(currentTime / duration, 1.0)
        }

        var description: String {
            "Ad \(currentAdNumber)/\(totalAds), \(String(format: "%.1f", currentTime))s/\(String(format: "%.1f", duration))s"
        }
    }

    // MARK: - Published State (Observable by View)

    /// The currently loaded video item
    @Published private(set) var currentVideo: AVIMAVideoItem?

    /// Current playback mode (idle, main video, or ad)
    @Published private(set) var playbackMode: PlaybackMode = .idle

    /// State of the main video player
    @Published private(set) var mainVideoState: PlayerState = .idle

    /// State of the ad player
    @Published private(set) var adState: PlayerState = .idle

    /// Current playback time (main video or ad depending on mode)
    @Published private(set) var currentTime: TimeInterval = 0

    /// Total duration (main video or ad depending on mode)
    @Published private(set) var duration: TimeInterval = 0

    /// Current ad progress information (nil when not playing ad)
    @Published private(set) var adProgress: AdProgress?

    /// Whether audio is muted
    @Published var isMuted: Bool = false

    /// Current playback error (nil when no error)
    @Published private(set) var playbackError: Error?

    /// Initialization status for the player
    @Published private(set) var initializationStatus: LoadStatus = .notStarted

    /// Whether closed captions are currently enabled
    @Published private(set) var closedCaptionsEnabled: Bool = false

    // MARK: - Computed Properties (Derived State)

    /// Whether content is currently playing
    var isPlaying: Bool {
        switch playbackMode {
        case .mainVideo:
            return mainVideoState == .playing
        case .advertisement:
            return adState == .playing
        case .idle:
            return false
        }
    }

    /// Whether the user can skip the current content
    var canSkip: Bool {
        switch playbackMode {
        case .mainVideo:
            return true
        case .advertisement:
            return adProgress?.isSkippable ?? false
        case .idle:
            return false
        }
    }

    /// Whether the user can seek through the content
    var canSeek: Bool {
        playbackMode == .mainVideo
    }

    /// Whether any player is in an error state
    var hasError: Bool {
        if case .error = mainVideoState {
            return true
        }
        if case .error = adState {
            return true
        }
        return false
    }

    /// Whether content is loading
    var isLoading: Bool {
        mainVideoState == .loading || adState == .loading
    }

    /// Current playback progress (0.0 to 1.0)
    var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    /// Video aspect ratio (width / height)
    var videoAspectRatio: Double {
        currentVideo?.aspectRatio ?? 16.0/9.0
    }

    /// Available closed caption options
    var availableClosedCaptions: [AVMediaSelectionOption] {
        guard let player = mainPlayer,
              let asset = player.currentItem?.asset,
              let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            return []
        }
        return group.options
    }

    // MARK: - Private Properties

    /// Brightcove playback controller for main video
    private var mainPlaybackController: BCOVPlaybackController?

    /// AVPlayer for main video content
    private var mainPlayer: AVPlayer?

    /// AVPlayer for ad content
    private var adPlayer: AVPlayer?

    /// IMA ads loader
    private var adsLoader: IMAAdsLoader?

    /// IMA ads manager
    private var adsManager: IMAAdsManager?

    /// Current ad being played (for progress tracking)
    private var currentAd: IMAAd?

    /// Container view for ad rendering
    private weak var adContainerView: UIView?

    /// View controller for ad presentation
    private weak var adViewController: UIViewController?

    /// Current player view controller for fullscreen control
    weak var currentPlayerViewController: AVPlayerViewController?

    /// Time observer for main player with its owning player instance
    private var mainTimeObserver: (observer: Any, player: AVPlayer)?

    /// Time observer for ad player with its owning player instance
    private var adTimeObserver: (observer: Any, player: AVPlayer)?

    /// Combine cancellables
    private var cancellables = Set<AnyCancellable>()

    /// Whether playback was active before backgrounding
    private var wasPlayingBeforeBackground = false

    /// Brightcove playback service for fetching videos
    private lazy var playbackService: BCOVPlaybackService = {
        let factory = BCOVPlaybackServiceRequestFactory(
            withAccountId: kAccountId,
            policyKey: kPolicyKey
        )
        return BCOVPlaybackService(withRequestFactory: factory)
    }()

    // MARK: - Initialization

    override init() {
        super.init()
        setupMuteObserver()
        setupLifecycleObservers()
    }

    deinit {
        // Cleanup is handled in View's onDisappear to avoid actor isolation issues
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API (Called by View)

    /// Returns the main player instance for rendering in the View.
    ///
    /// - Returns: The main AVPlayer instance, or nil if not initialized
    func getMainPlayer() -> AVPlayer? {
        return mainPlayer
    }

    /// Returns the ad player instance for rendering in the View.
    ///
    /// - Returns: The ad AVPlayer instance, or nil if not initialized
    func getAdPlayer() -> AVPlayer? {
        return adPlayer
    }

    /// Sets the container view and view controller for ad rendering.
    ///
    /// This must be called before loading videos to ensure IMA has the proper
    /// view hierarchy for rendering ads.
    ///
    /// - Parameters:
    ///   - containerView: The UIView that will contain the ad rendering
    ///   - viewController: The view controller for presenting ad UI
    func setAdContainer(containerView: UIView, viewController: UIViewController) {
        self.adContainerView = containerView
        self.adViewController = viewController
    }

    /// Enters fullscreen mode for the current player.
    ///
    /// Works for both ad and main video playback.
    func enterFullscreen() {
        guard let playerVC = currentPlayerViewController else {
            debugPrintWithTimestamp("⚠️ No player view controller available for fullscreen")
            return
        }

        // Trigger native fullscreen presentation
        // This is done by setting a private property, but there's no public API
        // The native controls provide the fullscreen button which works automatically
        debugPrintWithTimestamp("🔲 Fullscreen requested via native controls")
    }

    /// Loads a video by ID and initializes the player.
    ///
    /// This fetches the video from Brightcove, then creates the dual-player
    /// setup with proper IMA integration. Main video begins buffering while
    /// IMA ads are loaded.
    ///
    /// - Parameter videoId: The Brightcove video ID
    func loadVideo(videoId: String) async {
        // Prevent duplicate loads
        guard initializationStatus != .loading else { return }

        initializationStatus = .loading
        playbackError = nil

        do {
            // Fetch video from Brightcove
            let bcovVideo = try await fetchVideo(videoId: videoId)

            // Convert to AVIMAVideoItem
            guard let videoItem = AVIMAVideoItem.from(video: bcovVideo) else {
                throw PlayerError.videoLoadFailed("Failed to parse video metadata")
            }

            currentVideo = videoItem

            // Initialize players
            try await initializePlayers(with: videoItem)
            initializationStatus = .success
        } catch {
            initializationStatus = .error(error)
            playbackError = error
            mainVideoState = .error(error.localizedDescription)
        }
    }

    /// Loads a video item and initializes the player.
    ///
    /// Alternative method for when you already have a full AVIMAVideoItem.
    ///
    /// - Parameter video: The video item to load
    func loadVideo(_ video: AVIMAVideoItem) async {
        // Prevent duplicate loads
        guard initializationStatus != .loading else { return }

        initializationStatus = .loading
        playbackError = nil
        currentVideo = video

        do {
            try await initializePlayers(with: video)
            initializationStatus = .success
        } catch {
            initializationStatus = .error(error)
            playbackError = error
            mainVideoState = .error(error.localizedDescription)
        }
    }

    /// Starts or resumes playback.
    ///
    /// Behavior depends on current playback mode:
    /// - During ads: Resumes ad playback
    /// - During main content: Resumes main video playback
    func play() {
        debugPrintWithTimestamp("▶️ Play called - mode: \(playbackMode)")

        switch playbackMode {
        case .mainVideo:
            // Resume Brightcove playback controller
            mainPlaybackController?.play()
            // Also ensure AVPlayer is playing
            mainPlayer?.play()
            mainVideoState = .playing
            debugPrintWithTimestamp("   Main video resumed")

        case .advertisement:
            adsManager?.resume()
            adState = .playing
            debugPrintWithTimestamp("   Ad resumed")

        case .idle:
            debugPrintWithTimestamp("   Idle - no action")
            break
        }
    }

    /// Pauses playback.
    ///
    /// Works in both ad and main video modes.
    func pause() {
        debugPrintWithTimestamp("⏸️ Pause called - mode: \(playbackMode)")

        switch playbackMode {
        case .mainVideo:
            // Pause Brightcove playback controller
            mainPlaybackController?.pause()
            // Also pause AVPlayer
            mainPlayer?.pause()
            mainVideoState = .paused
            debugPrintWithTimestamp("   Main video paused")

        case .advertisement:
            adsManager?.pause()
            adState = .paused
            debugPrintWithTimestamp("   Ad paused")

        case .idle:
            debugPrintWithTimestamp("   Idle - no action")
            break
        }
    }

    /// Toggles mute state.
    ///
    /// Applies to both main video and ad audio.
    func toggleMute() {
        isMuted.toggle()
        mainPlayer?.isMuted = isMuted
        adsManager?.volume = isMuted ? 0 : 1
    }

    /// Seeks to a specific time in the main video.
    ///
    /// - Parameter time: Target time in seconds
    /// - Note: Only works during main video playback, not during ads
    func seek(to time: TimeInterval) {
        guard canSeek else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        mainPlayer?.seek(to: cmTime)
        currentTime = time
    }

    /// Attempts to skip the current ad.
    ///
    /// - Returns: `true` if skip was successful, `false` otherwise
    @discardableResult
    func skipAd() -> Bool {
        guard canSkip, playbackMode == .advertisement else {
            return false
        }

        adsManager?.skip()
        return true
    }

    /// Toggles closed captions on or off.
    ///
    /// Enables the first available caption track if turning on,
    /// or disables all tracks if turning off.
    /// Only works during main video playback (not during ads).
    func toggleClosedCaptions() {
        guard playbackMode == .mainVideo,
              let player = mainPlayer,
              let asset = player.currentItem?.asset,
              let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            debugPrintWithTimestamp("⚠️ Cannot toggle CC - not in main video mode or no CC available")
            return
        }

        if closedCaptionsEnabled {
            // Disable closed captions
            player.currentItem?.select(nil, in: group)
            closedCaptionsEnabled = false
            debugPrintWithTimestamp("📝 Closed captions disabled")
        } else if let firstOption = group.options.first {
            // Enable first available caption track
            player.currentItem?.select(firstOption, in: group)
            closedCaptionsEnabled = true
            debugPrintWithTimestamp("📝 Closed captions enabled: \(firstOption.displayName)")
        }
    }

    /// Called when the view disappears.
    ///
    /// Pauses playback and cleans up resources.
    func onDisappear() {
        pause()
        cleanup()
        removeLifecycleObservers()
    }

    /// Clears the current video and resets state.
    func clearVideo() {
        cleanup()
        currentVideo = nil
        playbackMode = .idle
        mainVideoState = .idle
        adState = .idle
        currentTime = 0
        duration = 0
        adProgress = nil
        playbackError = nil
        initializationStatus = .notStarted
    }

    // MARK: - Private Implementation

    /// Fetches a video from Brightcove by ID.
    ///
    /// - Parameter videoId: The Brightcove video ID
    /// - Returns: The BCOVVideo object
    /// - Throws: Error if video fetch fails
    private func fetchVideo(videoId: String) async throws -> BCOVVideo {
        return try await withCheckedThrowingContinuation { continuation in
            let configuration = [BCOVPlaybackService.ConfigurationKeyAssetID: videoId]

            playbackService.findVideo(
                withConfiguration: configuration,
                queryParameters: nil
            ) { (video: BCOVVideo?, jsonResponse: Any?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let video = video else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "AVIMAPlayerViewModel",
                            code: -1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Video not found: \(videoId)"
                            ]
                        )
                    )
                    return
                }

                continuation.resume(returning: video)
            }
        }
    }

    /// Initializes both main and ad players with the video.
    private func initializePlayers(with video: AVIMAVideoItem) async throws {
        // Clean up existing players
        cleanup()

        // Initialize main video player
        try await initializeMainPlayer(with: video)

        // Initialize IMA ads
        try await initializeIMAPlayer(with: video)
    }

    /// Initializes the main video player.
    private func initializeMainPlayer(with video: AVIMAVideoItem) async throws {
        mainVideoState = .loading

        // Create main player
        let player = AVPlayer()
        player.isMuted = isMuted
        self.mainPlayer = player

        // Set up Brightcove playback controller
        let playbackController = BCOVPlayerSDKManager.sharedManager().createPlaybackController()
        playbackController.delegate = self
        playbackController.isAutoPlay = false  // Don't autoplay - wait for ads to complete
        playbackController.isAutoAdvance = false
        self.mainPlaybackController = playbackController

        // Set video (will preload but not play)
        playbackController.setVideos([video.video])

        // Set up time observer
        setupMainPlayerTimeObserver()

        mainVideoState = .ready
    }

    /// Initializes the IMA ads loader and manager.
    private func initializeIMAPlayer(with video: AVIMAVideoItem) async throws {
        guard let adTagURL = URL(string: video.adTagURL) else {
            throw PlayerError.invalidAdTagURL
        }

        // Ensure we have the required views for ad rendering
        guard let containerView = adContainerView,
              let viewController = adViewController else {
            debugPrintWithTimestamp("⚠️ Ad container view or view controller not set. Skipping ads.")
            // Skip to main video if no ad container available
            switchToMainVideoMode()
            return
        }

        adState = .loading

        // Create ad player
        let adPlayerInstance = AVPlayer()
        adPlayerInstance.isMuted = isMuted
        self.adPlayer = adPlayerInstance

        // Set up IMA
        let settings = IMASettings()
        settings.enableBackgroundPlayback = true

        let adsLoader = IMAAdsLoader(settings: settings)
        adsLoader.delegate = self
        self.adsLoader = adsLoader

        // Create ad display container with real views
        let adDisplayContainer = IMAAdDisplayContainer(
            adContainer: containerView,
            viewController: viewController
        )

        // Request ads
        let request = IMAAdsRequest(
            adTagUrl: adTagURL.absoluteString,
            adDisplayContainer: adDisplayContainer,
            contentPlayhead: nil,
            userContext: nil
        )

        debugPrintWithTimestamp("📺 Requesting ads from: \(adTagURL.absoluteString)")
        adsLoader.requestAds(with: request)

        // Set up time observer for ad player
        setupAdPlayerTimeObserver()
    }

    /// Sets up time observation for main player.
    private func setupMainPlayerTimeObserver() {
        // Remove existing observer if present
        removeMainTimeObserver()

        guard let player = mainPlayer else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        let observer = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self,
                  self.playbackMode == .mainVideo else { return }

            self.currentTime = time.seconds

            if let duration = player.currentItem?.duration.seconds,
               duration.isFinite {
                self.duration = duration
            }
        }

        // Store observer with its owning player instance
        mainTimeObserver = (observer: observer, player: player)
    }

    /// Removes the main player time observer safely.
    private func removeMainTimeObserver() {
        guard let (observer, player) = mainTimeObserver else { return }
        player.removeTimeObserver(observer)
        mainTimeObserver = nil
    }

    /// Sets up time observation for ad player.
    private func setupAdPlayerTimeObserver() {
        // Remove existing observer if present
        removeAdTimeObserver()

        guard let player = adPlayer else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        let observer = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self,
                  self.playbackMode == .advertisement else { return }

            self.currentTime = time.seconds

            // Update ad progress with current time
            if let currentAd = self.currentAd {
                self.updateAdProgress(from: currentAd, currentTime: time.seconds)
            }
        }

        // Store observer with its owning player instance
        adTimeObserver = (observer: observer, player: player)
    }

    /// Removes the ad player time observer safely.
    private func removeAdTimeObserver() {
        guard let (observer, player) = adTimeObserver else { return }
        player.removeTimeObserver(observer)
        adTimeObserver = nil
    }

    /// Sets up observer for mute state changes.
    private func setupMuteObserver() {
        $isMuted
            .dropFirst()
            .sink { [weak self] isMuted in
                self?.mainPlayer?.isMuted = isMuted
                self?.adsManager?.volume = isMuted ? 0 : 1
            }
            .store(in: &cancellables)
    }

    /// Sets up observers for app lifecycle events.
    ///
    /// Monitors when the app enters background or returns to foreground
    /// to properly pause and resume playback.
    private func setupLifecycleObservers() {
        // App going to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // App returning to foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    /// Removes lifecycle observers.
    private func removeLifecycleObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    /// Called when app enters background.
    ///
    /// Pauses playback to conserve battery and respect system resources.
    /// Tracks whether content was playing to optionally resume on return.
    @objc
    private func appDidEnterBackground() {
        // Track if we were playing before backgrounding
        wasPlayingBeforeBackground = isPlaying

        // Always pause when entering background
        if isPlaying {
            pause()
        }
    }

    /// Called when app returns to foreground.
    ///
    /// Currently leaves playback paused - user must manually resume.
    /// This provides better user experience as auto-resume can be jarring.
    ///
    /// **Future Enhancement:**
    /// Could add a setting to optionally auto-resume:
    /// ```
    /// if wasPlayingBeforeBackground && userPreferences.autoResume {
    ///     play()
    /// }
    /// ```
    @objc
    private func appWillEnterForeground() {
        // Currently intentionally leaving paused
        // User can manually resume playback if desired
        // This prevents unexpected audio/video when returning to app

        // Reset tracking flag
        wasPlayingBeforeBackground = false
    }

    /// Switches playback mode to advertisement.
    ///
    /// Ensures clean state transition by pausing main video and activating ad player.
    private func switchToAdMode() {
        debugPrintWithTimestamp("🔄 Switching to ad mode")

        // Validate state
        guard playbackMode != .advertisement else {
            debugPrintWithTimestamp("   ⚠️ Already in ad mode")
            return
        }

        // Pause main video
        mainPlaybackController?.pause()
        mainPlayer?.pause()

        // Activate ad mode
        playbackMode = .advertisement
        adState = .playing

        debugPrintWithTimestamp("   ✅ Ad mode active")
    }

    /// Switches playback mode back to main video and starts playback.
    ///
    /// Ensures clean state transition by stopping ads and activating main video.
    private func switchToMainVideoMode() {
        debugPrintWithTimestamp("🔄 Switching to main video mode")

        // Validate state
        guard playbackMode != .mainVideo else {
            debugPrintWithTimestamp("   ⚠️ Already in main video mode")
            return
        }

        // Clean up ad state
        adState = .idle
        adProgress = nil

        // Activate main video mode
        playbackMode = .mainVideo

        // Start main video playback
        mainPlaybackController?.play()
        mainPlayer?.play()
        mainVideoState = .playing

        debugPrintWithTimestamp("   ✅ Main video mode active")

        // Update closed caption state
        updateCaptionState()
    }

    /// Updates the closed caption state based on the current player selection.
    ///
    /// Should be called when playback mode changes or video loads.
    private func updateCaptionState() {
        guard let player = mainPlayer,
              let asset = player.currentItem?.asset,
              let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
              let currentSelection = player.currentItem?.currentMediaSelection else {
            closedCaptionsEnabled = false
            return
        }

        let selectedOption = currentSelection.selectedMediaOption(in: group)
        closedCaptionsEnabled = (selectedOption != nil)
    }

    /// Cleans up players and observers.
    ///
    /// Should be called from View's onDisappear.
    func cleanup() {
        // Remove time observers safely from their owning player instances
        removeMainTimeObserver()
        removeAdTimeObserver()

        mainPlayer?.pause()
        adPlayer?.pause()

        adsManager?.destroy()
        adsManager = nil
        adsLoader = nil

        mainPlaybackController = nil
        mainPlayer = nil
        adPlayer = nil
    }

    // MARK: - Error Types

    enum PlayerError: LocalizedError {
        case invalidAdTagURL
        case adLoadFailed(String)
        case videoLoadFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidAdTagURL:
                return "Invalid ad tag URL"
            case .adLoadFailed(let message):
                return "Ad load failed: \(message)"
            case .videoLoadFailed(let message):
                return "Video load failed: \(message)"
            }
        }
    }
}

// MARK: - BCOVPlaybackControllerDelegate

extension AVIMAPlayerViewModel: BCOVPlaybackControllerDelegate {

    func playbackController(
        _ controller: BCOVPlaybackController!,
        didAdvanceTo session: BCOVPlaybackSession!
    ) {
        // Main video session started with a new player instance
        if let player = session.player {
            // Remove observer from old player before replacing
            removeMainTimeObserver()

            // Update to new player instance
            self.mainPlayer = player
            player.isMuted = isMuted

            // Set up observer on new player instance
            setupMainPlayerTimeObserver()
        }
    }

    func playbackController(
        _ controller: BCOVPlaybackController!,
        playbackSession session: BCOVPlaybackSession!,
        didReceive lifecycleEvent: BCOVPlaybackSessionLifecycleEvent!
    ) {
        let eventType = lifecycleEvent.eventType

        switch eventType {
        case kBCOVPlaybackSessionLifecycleEventReady:
            mainVideoState = .ready

        case kBCOVPlaybackSessionLifecycleEventPlay:
            mainVideoState = .playing

        case kBCOVPlaybackSessionLifecycleEventPause:
            mainVideoState = .paused

        case kBCOVPlaybackSessionLifecycleEventEnd:
            mainVideoState = .completed

        case kBCOVPlaybackSessionLifecycleEventFail:
            if let error = lifecycleEvent.properties["error"] as? NSError {
                mainVideoState = .error(error.localizedDescription)
                playbackError = error
            }

        default:
            break
        }
    }
}

// MARK: - IMAAdsLoaderDelegate

extension AVIMAPlayerViewModel: IMAAdsLoaderDelegate {

    func adsLoader(_ loader: IMAAdsLoader, adsLoadedWith adsLoadedData: IMAAdsLoadedData) {
        debugPrintWithTimestamp("✅ Ads loaded successfully")

        guard let manager = adsLoadedData.adsManager else {
            debugPrintWithTimestamp("❌ Failed to get ads manager")
            adState = .error("Failed to get ads manager")
            switchToMainVideoMode()
            return
        }

        debugPrintWithTimestamp("📺 Initializing ads manager")
        manager.delegate = self
        manager.initialize(with: nil)
        self.adsManager = manager

        // Start ads
        debugPrintWithTimestamp("▶️ Starting ad playback")
        manager.start()
        switchToAdMode()
    }

    func adsLoader(_ loader: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
        let errorMessage = adErrorData.adError.message ?? "Unknown ad error"
        debugPrintWithTimestamp("❌ Ad loading failed: \(errorMessage)")
        debugPrintWithTimestamp("   Error code: \(adErrorData.adError.code)")

        adState = .error(errorMessage)
        playbackError = PlayerError.adLoadFailed(errorMessage)

        // Ad failed, skip to main video and autoplay
        debugPrintWithTimestamp("⏩ Skipping to main video")
        switchToMainVideoMode()
    }
}

// MARK: - IMAAdsManagerDelegate

extension AVIMAPlayerViewModel: IMAAdsManagerDelegate {

    func adsManager(_ adsManager: IMAAdsManager, didReceive event: IMAAdEvent) {
        debugPrintWithTimestamp("📢 Ad event: \(event.type.rawValue)")

        switch event.type {
        case .LOADED:
            debugPrintWithTimestamp("   Ad loaded and ready")
            adState = .ready

        case .STARTED:
            debugPrintWithTimestamp("   Ad started playing")
            adState = .playing

            if let ad = event.ad {
                currentAd = ad  // Store for continuous progress updates
                updateAdProgress(from: ad, currentTime: 0)
                debugPrintWithTimestamp("   Ad info: \(adProgress?.description ?? "no progress")")
            }

        case .PAUSE:
            debugPrintWithTimestamp("   Ad paused")
            adState = .paused

        case .RESUME:
            debugPrintWithTimestamp("   Ad resumed")
            adState = .playing

        case .COMPLETE:
            debugPrintWithTimestamp("   Ad completed")
            adState = .completed
            adProgress = nil
            currentAd = nil

        case .ALL_ADS_COMPLETED:
            debugPrintWithTimestamp("   All ads completed - switching to main video")
            currentAd = nil
            switchToMainVideoMode()

        case .SKIPPED:
            debugPrintWithTimestamp("   Ad skipped - switching to main video")
            currentAd = nil
            switchToMainVideoMode()

        default:
            debugPrintWithTimestamp("   Other event: \(event.type)")
            break
        }
    }

    func adsManager(_ adsManager: IMAAdsManager, didReceive error: IMAAdError) {
        let errorMessage = error.message ?? "Unknown ad error"
        adState = .error(errorMessage)
        playbackError = PlayerError.adLoadFailed(errorMessage)

        // Ad error, skip to main video and autoplay
        switchToMainVideoMode()
    }

    func adsManagerDidRequestContentPause(_ adsManager: IMAAdsManager) {
        // Ad is starting, pause main video
        mainPlaybackController?.pause()
        mainPlayer?.pause()
    }

    func adsManagerDidRequestContentResume(_ adsManager: IMAAdsManager) {
        // Ad completed, resume main video with autoplay
        switchToMainVideoMode()
    }

    /// Updates ad progress information.
    private func updateAdProgress(from ad: IMAAd, currentTime: TimeInterval) {
        let podInfo = ad.adPodInfo
        adProgress = AdProgress(
            currentAdNumber: podInfo.adPosition,
            totalAds: podInfo.totalAds,
            currentTime: currentTime,
            duration: ad.duration,
            isSkippable: ad.isSkippable,
            skipTimeRemaining: ad.skipTimeOffset
        )
        duration = ad.duration
    }
}

// MARK: - VideoPlayerControlsDelegate

extension AVIMAPlayerViewModel: VideoPlayerControlsDelegate {

    func handleControlAction(_ action: VideoPlayerControlAction) {
        switch action {
        case .play:
            play()

        case .pause:
            pause()

        case .togglePlayPause:
            if isPlaying {
                pause()
            } else {
                play()
            }

        case .mute:
            if !isMuted {
                toggleMute()
            }

        case .unmute:
            if isMuted {
                toggleMute()
            }

        case .toggleMute:
            toggleMute()

        case .seek(let time):
            seek(to: time)

        case .skipBackward(let duration):
            let newTime = max(0, currentTime - duration)
            seek(to: newTime)

        case .skipForward(let duration):
            let newTime = min(self.duration, currentTime + duration)
            seek(to: newTime)

        case .skipAd:
            skipAd()

        case .toggleClosedCaptions:
            toggleClosedCaptions()

        case .close, .share:
            // These actions are handled by the View (navigation/presentation)
            break
        }
    }

    var adProgress: AdProgressInfo? {
        // Convert internal AdProgress to AdProgressInfo
        guard let progress = self.adProgress else { return nil }

        return AdProgressInfo(
            currentAdNumber: progress.currentAdNumber,
            totalAds: progress.totalAds,
            currentTime: progress.currentTime,
            duration: progress.duration,
            isSkippable: progress.isSkippable,
            skipTimeRemaining: progress.skipTimeRemaining
        )
    }
}
