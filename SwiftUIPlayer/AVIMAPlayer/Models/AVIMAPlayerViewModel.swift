//
//  AVIMAPlayerViewModel.swift
//  SwiftUIPlayer
//
//  ViewModel for managing IMA video player state with dual-player architecture.
//  Follows CLAUDE.md standards for SwiftUI ViewModels with complete closed loops.
//

import AVFoundation
import Foundation
import GoogleInteractiveMediaAds
import UIKit
import SwiftUI
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
final class AVIMAPlayerViewModel: NSObject, ObservableObject {

    // MARK: - Nested Types

    /// Represents the current playback mode (mutually exclusive states)
    enum PlaybackMode: Equatable, Sendable {
        /// No content is loaded - initializing
        case idle

        /// Playing main video content (ad player is idle)
        case mainVideo

        /// Playing advertisement content (main player is paused)
        case advertisement
    }

    /// Represents the state of a player
    enum PlayerState: Equatable, Sendable {
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
    struct AdProgress: Equatable, Sendable, CustomStringConvertible {
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
    @Published private(set) var currentAdProgress: AdProgress?

    /// Whether audio is muted
    @Published var isMuted: Bool = false {
        didSet {
            mainPlayer?.isMuted = isMuted
            adsManager?.volume = isMuted ? 0 : 1
        }
    }

    /// Current playback error (nil when no error)
    @Published private(set) var playbackError: Error?

    /// Initialization status for the player
    @Published private(set) var initializationStatus: LoadStatus = .notStarted

    /// Whether closed captions are currently enabled
    @Published private(set) var closedCaptionsEnabled: Bool = false

    /// Ad cue points for the current video session.
    /// Tracks which cue points have been played so midrolls fire only once.
    @Published private(set) var adCuePoints: [AdCuePoint] = []

    /// Whether player controls are currently visible
    @Published var showingControls: Bool = true

    /// Timer for auto-hiding controls
    private var controlsTimer: Timer?

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
            return currentAdProgress?.isSkippable ?? false
        case .idle:
            return false
        }
    }

    /// Whether the user can seek through the content.
    /// Blocked during midroll triggering to prevent the slider from
    /// overwriting the seek-to-cue-point position while IMA loads.
    var canSeek: Bool {
        playbackMode == .mainVideo && !isTriggeringMidroll
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

    // MARK: - Shared IMA Container

    /// Shared UIView that IMA renders its ad content into.
    ///
    /// Owned by the ViewModel so it can be **reparented** between the embedded and
    /// fullscreen `AdContainerViewController` instances when the user expands to
    /// fullscreen while an ad is playing. Each VC's `viewWillAppear` moves this view
    /// into its own UIKit hierarchy with `insertSubview`, which automatically removes
    /// it from the previous parent.
    ///
    /// Manual frame layout (not NSLayoutConstraint) is used so there are no stale
    /// constraints when the view moves between parents.
    let imaContainerView: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.isHidden = true
        return v
    }()

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

    /// Continuation that `initializeIMAPlayer` awaits until `setAdContainer` is called.
    /// Resolves the timing race between `.task { loadVideo() }` and `viewWillAppear`.
    private var adContainerContinuation: CheckedContinuation<Void, Never>?

    /// Current player view controller for fullscreen control
    weak var currentPlayerViewController: AVPlayerViewController?

    /// Time observer for main player with its owning player instance
    private var mainTimeObserver: (observer: Any, player: AVPlayer)?

    /// Time observer for ad player with its owning player instance
    private var adTimeObserver: (observer: Any, player: AVPlayer)?

    /// Task monitoring app lifecycle events (background/foreground transitions).
    /// Cancelled in cleanup() to stop monitoring when the player is torn down.
    private var lifecycleTask: Task<Void, Never>?

    /// Whether playback was active before backgrounding
    private var wasPlayingBeforeBackground = false

    /// Whether a midroll ad is currently being triggered (prevents re-entrance)
    private var isTriggeringMidroll = false

    /// Whether the user is actively dragging the seek bar.
    /// When true, the periodic time observer skips updating `currentTime`
    /// so the slider doesn't snap back during a drag.
    private var isSeeking = false

    /// The position to resume from after a midroll completes
    private var resumePositionAfterMidroll: TimeInterval?

    /// Whether the current ad session is a midroll (vs initial pre-roll)
    private var isMidrollAdSession = false

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
        startLifecycleMonitoring()
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

        // Resume initializeIMAPlayer if it's waiting for the container.
        adContainerContinuation?.resume()
        adContainerContinuation = nil
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
        // Prevent duplicate/redundant loads — skip if already loading or successfully initialized.
        // The .success guard is critical for the shared-ViewModel embedded+fullscreen pattern:
        // the fullscreen view's .task calls this but must not re-initialize the running player.
        guard initializationStatus != .loading, initializationStatus != .success else { return }

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
        // Prevent duplicate/redundant loads — see loadVideo(videoId:) comment.
        guard initializationStatus != .loading, initializationStatus != .success else { return }

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
        showControls()

        switch playbackMode {
        case .mainVideo:
            // Drive AVPlayer directly — BCOVPlaybackController's internal session
            // can be invalidated during IMA ad flow, causing EXC_BAD_ACCESS.
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
        showControls()

        switch playbackMode {
        case .mainVideo:
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
        showControls()
        isMuted.toggle()
        mainPlayer?.isMuted = isMuted
        adsManager?.volume = isMuted ? 0 : 1
    }

    /// Seeks to a specific time in the main video.
    ///
    /// If the seek jumps forward past an unplayed midroll cue point, the midroll
    /// ad is triggered first. After the ad completes, playback resumes at the
    /// user's original target position.
    ///
    /// - Parameter time: Target time in seconds
    /// - Note: Only works during main video playback, not during ads
    func seek(to time: TimeInterval) {
        showControls()
        guard canSeek else {
            debugPrintWithTimestamp("⏩ Seek blocked — canSeek=false, mode=\(playbackMode)")
            return
        }

        debugPrintWithTimestamp("⏩ Seek requested: \(String(format: "%.1f", currentTime))s → \(String(format: "%.1f", time))s")

        // Check if seeking forward past an unplayed midroll
        if time > currentTime,
           let cuePointIndex = firstUnplayedMidrollBetween(start: currentTime, end: time) {
            debugPrintWithTimestamp("⏩ Seek crosses midroll at \(adCuePoints[cuePointIndex].position)s — triggering ad first")
            // Store the user's intended target for after the midroll
            resumePositionAfterMidroll = time
            let cuePosition = adCuePoints[cuePointIndex].position
            let cmTime = CMTime(seconds: cuePosition, preferredTimescale: 600)
            isSeeking = true
            mainPlayer?.seek(to: cmTime) { [weak self] _ in
                self?.isSeeking = false
            }
            currentTime = cuePosition
            triggerMidrollAd(atIndex: cuePointIndex)
            return
        }

        // Normal seek — set isSeeking so the periodic time observer doesn't
        // overwrite currentTime with the stale pre-seek position.
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        isSeeking = true
        mainPlayer?.seek(to: cmTime) { [weak self] _ in
            self?.isSeeking = false
        }
        currentTime = time
    }

    /// Attempts to skip the current ad.
    ///
    /// - Returns: `true` if skip was successful, `false` otherwise
    @discardableResult
    func skipAd() -> Bool {
        showControls()
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
        showControls()
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

    /// Shows player controls and starts auto-hide timer.
    func showControls() {
        showingControls = true
        resetControlsTimer()
    }

    /// Hides player controls and invalidates timer.
    /// No-op during ad playback — controls must remain visible throughout an ad.
    func hideControls() {
        guard playbackMode != .advertisement else { return }
        withAnimation {
            showingControls = false
        }
        controlsTimer?.invalidate()
        controlsTimer = nil
    }

    /// Toggles player controls visibility.
    func toggleControls() {
        if showingControls {
            hideControls()
        } else {
            showControls()
        }
    }

    /// Resets the auto-hide timer.
    /// Call this whenever user interacts with controls.
    private func resetControlsTimer() {
        controlsTimer?.invalidate()

        // Never auto-hide during ads — controls must stay visible for the full ad.
        guard playbackMode != .advertisement else { return }

        // Only auto-hide if playing
        guard isPlaying else { return }

        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.hideControls()
        }
    }

    /// Called when the view disappears.
    ///
    /// Pauses playback and cleans up resources.
    func onDisappear() {
        pause()
        cleanup()
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
        currentAdProgress = nil
        playbackError = nil
        initializationStatus = .notStarted
        adCuePoints = []
        resumePositionAfterMidroll = nil
        isTriggeringMidroll = false
        isMidrollAdSession = false
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

        // Build ad cue points for this session
        var cuePoints: [AdCuePoint] = [
            AdCuePoint(position: 0, type: .preRoll)
        ]
        for position in video.midRollPositions {
            cuePoints.append(AdCuePoint(position: position, type: .midRoll))
        }
        self.adCuePoints = cuePoints
        debugPrintWithTimestamp("📋 Ad cue points: \(cuePoints.map { "\($0.type)@\($0.position)s" })")

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
        guard let adTagURL = URL(string: video.preRollAdTagURL) else {
            throw PlayerError.invalidAdTagURL
        }

        // Wait for the ad container if it hasn't been set yet.
        // This resolves the timing race: .task { loadVideo() } can fire before
        // AdContainerViewController.viewWillAppear calls setAdContainer().
        if adContainerView == nil || adViewController == nil {
            debugPrintWithTimestamp("⏳ Waiting for ad container to be set...")
            await withCheckedContinuation { continuation in
                self.adContainerContinuation = continuation
            }
            debugPrintWithTimestamp("✅ Ad container is now available")
        }

        guard let containerView = adContainerView,
              let viewController = adViewController else {
            debugPrintWithTimestamp("⚠️ Ad container view or view controller not set. Skipping ads.")
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
            guard let self = self else { return }

            let secs = time.seconds

            // Log mode every 10s so we can diagnose the time observer state
            if Int(secs) % 10 == 0, secs.truncatingRemainder(dividingBy: 10) < 0.15 {
                debugPrintWithTimestamp("🕐 TimeObserver: t=\(String(format: "%.1f", secs))s mode=\(self.playbackMode) triggering=\(self.isTriggeringMidroll) cuePoints=\(self.adCuePoints.count)")
            }

            guard self.playbackMode == .mainVideo,
                  !self.isTriggeringMidroll,
                  !self.isSeeking else { return }

            self.currentTime = secs

            if let duration = player.currentItem?.duration.seconds,
               duration.isFinite {
                self.duration = duration
            }

            // Check if playback crossed a midroll cue point
            self.checkForMidrollCuePoint(at: secs)
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

    // MARK: - Lifecycle Monitoring

    /// Starts a Task that monitors app lifecycle notifications via AsyncSequence.
    ///
    /// Handles:
    /// - **Background**: Pauses playback, tracks state for resume
    /// - **Foreground**: Resumes ad playback if an ad was interrupted (e.g., by
    ///   tapping IMA's "Learn More" which opens Safari). Main video stays paused
    ///   so audio doesn't surprise the user.
    ///
    /// Uses `NotificationCenter.notifications(named:)` instead of Combine `.sink`
    /// or `@objc` selectors — Sendable-safe and cancelled automatically via the Task.
    private func startLifecycleMonitoring() {
        lifecycleTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                        guard let self, !Task.isCancelled else { return }
                        await self.handleDidEnterBackground()
                    }
                }
                group.addTask { [weak self] in
                    for await _ in NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification) {
                        guard let self, !Task.isCancelled else { return }
                        await self.handleWillEnterForeground()
                    }
                }
            }
        }
    }

    /// Pauses playback and records state so we can resume correctly on return.
    private func handleDidEnterBackground() {
        wasPlayingBeforeBackground = isPlaying
        debugPrintWithTimestamp("📱 Background — wasPlaying: \(wasPlayingBeforeBackground), mode: \(playbackMode)")

        if isPlaying {
            pause()
        }
    }

    /// Resumes playback when returning from background.
    ///
    /// - **Ads**: Resume via `adsManager.resume()` directly — IMA manages its own
    ///   playback state internally. Using our `play()` would reset IMA's state and
    ///   restart the ad from the beginning.
    /// - **Main video**: Stay paused — unexpected audio on foreground is jarring.
    ///   The user can tap play to continue.
    private func handleWillEnterForeground() {
        debugPrintWithTimestamp("📱 Foreground — wasPlaying: \(wasPlayingBeforeBackground), mode: \(playbackMode)")

        if wasPlayingBeforeBackground {
            switch playbackMode {
            case .advertisement:
                // Resume via IMA directly — preserves ad position.
                adsManager?.resume()
                adState = .playing
                debugPrintWithTimestamp("   ▶️ Ad resumed via adsManager.resume()")

            case .mainVideo:
                // Stay paused — user can tap play when ready.
                debugPrintWithTimestamp("   ⏸️ Main video stays paused")

            case .idle:
                break
            }
        }

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
        mainPlayer?.pause()

        // Unhide the IMA container immediately — don't wait for SwiftUI's
        // rendering pass. After preroll the container was hidden; IMA's
        // manager.start() renders into it synchronously, so it must be
        // visible before playbackMode triggers a SwiftUI update.
        imaContainerView.isHidden = false

        // Activate ad mode
        playbackMode = .advertisement
        adState = .playing

        debugPrintWithTimestamp("   ✅ Ad mode active, imaContainer visible")
    }

    /// Switches playback mode back to main video and starts playback.
    ///
    /// Ensures clean state transition by stopping ads and activating main video.
    private func switchToMainVideoMode() {
        debugPrintWithTimestamp("    🔄 Switching to main video mode")

        // Validate state — prevent double-transition
        guard playbackMode != .mainVideo else {
            debugPrintWithTimestamp("   ⚠️ Already in main video mode")
            return
        }

        guard let player = mainPlayer else {
            debugPrintWithTimestamp("   ⚠️ Main player not available, cannot switch to main video")
            playbackMode = .idle
            return
        }

        // Clean up ad state
        adState = .idle
        currentAdProgress = nil

        // Activate main video mode BEFORE calling play — ensures any
        // delegate callbacks see the correct mode.
        playbackMode = .mainVideo

        // Resume via AVPlayer directly — BCOVPlaybackController's internal session
        // can be invalidated during IMA ad playback, causing EXC_BAD_ACCESS.
        player.play()
        mainVideoState = .playing

        debugPrintWithTimestamp("   ✅ Main video mode active")

        // Update closed caption state
        updateCaptionState()
    }

    // MARK: - Midroll Ad Logic

    /// Checks if playback has naturally reached an unplayed midroll cue point.
    ///
    /// Called from the main player time observer at 10Hz. Uses a 1.0s tolerance
    /// window to avoid missing cue points between polling intervals.
    private func checkForMidrollCuePoint(at currentTime: TimeInterval) {
        guard !isTriggeringMidroll else { return }
        guard playbackMode == .mainVideo else { return }

        let tolerance: TimeInterval = 1.0

        // Log every 30 seconds so we can verify the check is running
        if Int(currentTime) % 30 == 0, currentTime.truncatingRemainder(dividingBy: 30) < 0.2 {
            let cuePointSummary = adCuePoints.map { "[\($0.type == .midRoll ? "mid" : "pre")@\($0.position)s played=\($0.hasPlayed)]" }.joined(separator: ", ")
            debugPrintWithTimestamp("⏱️ Midroll check at \(String(format: "%.1f", currentTime))s — cuePoints: \(cuePointSummary)")
        }

        guard let cuePointIndex = adCuePoints.firstIndex(where: { cuePoint in
            cuePoint.type == .midRoll
            && !cuePoint.hasPlayed
            && currentTime >= cuePoint.position
            && currentTime <= cuePoint.position + tolerance
        }) else { return }

        debugPrintWithTimestamp("🎯 Midroll cue point HIT at \(String(format: "%.1f", currentTime))s — cuePoint position: \(adCuePoints[cuePointIndex].position)s")
        triggerMidrollAd(atIndex: cuePointIndex)
    }

    /// Returns the index of the first unplayed midroll between two playback times.
    ///
    /// Used by `seek(to:)` to detect when the user seeks past a midroll cue point.
    ///
    /// - Parameters:
    ///   - start: The current playback position (exclusive)
    ///   - end: The target seek position (inclusive)
    /// - Returns: Index into `adCuePoints` of the first unplayed midroll, or nil
    private func firstUnplayedMidrollBetween(start: TimeInterval, end: TimeInterval) -> Int? {
        adCuePoints.firstIndex { cuePoint in
            cuePoint.type == .midRoll
            && !cuePoint.hasPlayed
            && cuePoint.position > start
            && cuePoint.position <= end
        }
    }

    /// Triggers a midroll ad at the given cue point index.
    ///
    /// Pauses main video, marks the cue point as played, destroys the old
    /// ads manager, and requests a fresh IMA ad. If the ad fails to load,
    /// main video resumes automatically (closed loop).
    ///
    /// - Parameter index: Index into `adCuePoints`
    private func triggerMidrollAd(atIndex index: Int) {
        guard index < adCuePoints.count else { return }
        guard !isTriggeringMidroll else { return }

        isTriggeringMidroll = true
        isMidrollAdSession = true

        // Mark cue point as played (prevents re-triggering)
        adCuePoints[index].hasPlayed = true

        // Store resume position if not already set by seek(to:)
        if resumePositionAfterMidroll == nil {
            resumePositionAfterMidroll = currentTime
        }

        debugPrintWithTimestamp("🎯 Triggering midroll ad at \(adCuePoints[index].position)s")

        // Pause main video
        mainPlayer?.pause()

        // Destroy previous ads manager (it's one-shot per ad break)
        adsManager?.destroy()
        adsManager = nil

        // Request new ad
        guard let containerView = adContainerView,
              let viewController = adViewController else {
            debugPrintWithTimestamp("⚠️ No ad container for midroll — containerView=\(adContainerView != nil), viewController=\(adViewController != nil), resuming main video")
            resumeAfterMidroll()
            return
        }

        guard let video = currentVideo else {
            resumeAfterMidroll()
            return
        }

        let adDisplayContainer = IMAAdDisplayContainer(
            adContainer: containerView,
            viewController: viewController
        )

        // Append a unique correlator so IMA treats this as a fresh ad request
        // (the default ad tag ends with &correlator= which is empty)
        let adTagWithCorrelator = video.midRollAdTagURL + "\(Int(Date().timeIntervalSince1970))"

        let request = IMAAdsRequest(
            adTagUrl: adTagWithCorrelator,
            adDisplayContainer: adDisplayContainer,
            contentPlayhead: nil,
            userContext: nil
        )

        // Ensure loader delegate is still set (it should be, but safety check)
        adsLoader?.delegate = self

        debugPrintWithTimestamp("📺 Requesting midroll ad — adsLoader nil? \(adsLoader == nil), adTag: \(adTagWithCorrelator)")
        adsLoader?.requestAds(with: request)

        // If adsLoader is nil, we can't request ads — fall back to resume
        if adsLoader == nil {
            debugPrintWithTimestamp("❌ adsLoader is nil — cannot request midroll ad, resuming")
            resumeAfterMidroll()
        }
    }

    /// Resumes main video after a midroll ad completes or fails.
    ///
    /// If the user had seeked past the midroll, jumps to their original target position.
    private func resumeAfterMidroll() {
        let resumePosition = resumePositionAfterMidroll

        isTriggeringMidroll = false
        isMidrollAdSession = false
        resumePositionAfterMidroll = nil

        switchToMainVideoMode()

        // If the user seeked past the midroll, jump to their target
        if let resumePosition {
            let cmTime = CMTime(seconds: resumePosition, preferredTimescale: 600)
            mainPlayer?.seek(to: cmTime)
            currentTime = resumePosition
        }
    }

    /// Applies the current closed caption state to AVFoundation.
    ///
    /// Uses `closedCaptionsEnabled` as the source of truth rather than reading
    /// the player's current selection. This prevents system accessibility settings
    /// from auto-enabling CC against the app default (off).
    /// Should be called when playback mode changes or video loads.
    private func updateCaptionState() {
        guard let player = mainPlayer,
              let asset = player.currentItem?.asset,
              let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
              let currentItem = player.currentItem else {
            closedCaptionsEnabled = false
            return
        }

        if closedCaptionsEnabled, let firstOption = group.options.first {
            currentItem.select(firstOption, in: group)
        } else {
            currentItem.select(nil, in: group)
            closedCaptionsEnabled = false
        }
    }

    /// Cleans up players and observers.
    ///
    /// Should be called from View's onDisappear.
    func cleanup() {
        // Resume any pending ad container continuation to avoid leaked continuation.
        adContainerContinuation?.resume()
        adContainerContinuation = nil

        // Stop lifecycle monitoring
        lifecycleTask?.cancel()
        lifecycleTask = nil

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

        // Reset playback state so the view shows idle (not "unavailable")
        // and initializationStatus allows re-initialization when the view reappears.
        playbackMode = .idle
        initializationStatus = .notStarted
    }

    // MARK: - Error Types

    enum PlayerError: LocalizedError, Sendable {
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
        debugPrintWithTimestamp("✅ Ads loaded successfully (\(isMidrollAdSession ? "midroll" : "pre-roll"))")

        guard let manager = adsLoadedData.adsManager else {
            debugPrintWithTimestamp("❌ Failed to get ads manager")
            adState = .error("Failed to get ads manager")
            if isMidrollAdSession {
                resumeAfterMidroll()
            } else {
                switchToMainVideoMode()
            }
            return
        }

        debugPrintWithTimestamp("📺 Initializing ads manager")
        manager.delegate = self

        // Provide rendering settings with linkOpenerPresentingController so IMA
        // can present its in-app browser when the user taps "Learn More".
        // Without this, IMA has no VC to present from and click-throughs fail silently.
        let renderSettings = IMAAdsRenderingSettings()
        renderSettings.linkOpenerPresentingController = adViewController
        manager.initialize(with: renderSettings)

        self.adsManager = manager

        // Mark pre-roll as played
        if !isMidrollAdSession,
           let preRollIndex = adCuePoints.firstIndex(where: { $0.type == .preRoll && !$0.hasPlayed }) {
            adCuePoints[preRollIndex].hasPlayed = true
        }

        // Start ads
        debugPrintWithTimestamp("▶️ Starting ad playback")
        manager.start()
        switchToAdMode()
    }

    func adsLoader(_ loader: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
        let errorMessage = adErrorData.adError.message ?? "Unknown ad error"
        debugPrintWithTimestamp("❌ Ad loading failed: \(errorMessage)")
        debugPrintWithTimestamp("   Error code: \(adErrorData.adError.code), session: \(isMidrollAdSession ? "midroll" : "preroll")")

        adState = .error(errorMessage)

        if isMidrollAdSession {
            // Midroll failed — resume main video silently (non-fatal)
            debugPrintWithTimestamp("⏩ Midroll ad failed, resuming main video")
            resumeAfterMidroll()
        } else {
            // Pre-roll failed — show error, skip to main video
            playbackError = PlayerError.adLoadFailed(errorMessage)
            debugPrintWithTimestamp("⏩ Pre-roll failed, skipping to main video")
            switchToMainVideoMode()
        }
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
                debugPrintWithTimestamp("   Ad info: \(currentAdProgress?.description ?? "no progress")")
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
            currentAdProgress = nil
            currentAd = nil

        case .ALL_ADS_COMPLETED:
            debugPrintWithTimestamp("   All ads completed (\(isMidrollAdSession ? "midroll" : "pre-roll"))")
            currentAd = nil
            // adsManagerDidRequestContentResume typically fires before this event
            // and already handles the mode switch. Only act if still in ad mode.
            if playbackMode == .advertisement {
                if isMidrollAdSession {
                    resumeAfterMidroll()
                } else {
                    switchToMainVideoMode()
                }
            }

        case .SKIPPED:
            debugPrintWithTimestamp("   Ad skipped (\(isMidrollAdSession ? "midroll" : "pre-roll"))")
            currentAd = nil
            if playbackMode == .advertisement {
                if isMidrollAdSession {
                    resumeAfterMidroll()
                } else {
                    switchToMainVideoMode()
                }
            }

        case .TAPPED:
            // User tapped "Learn More" or the ad click-through area.
            // IMA handles pause/resume and browser presentation internally —
            // do NOT call adsManager.pause() here or it disrupts IMA's state.
            debugPrintWithTimestamp("   Ad tapped — click-through (IMA handles presentation)")

        case .FIRST_QUARTILE, .MIDPOINT, .THIRD_QUARTILE:
            // VAST quartile progress tracking — no action needed
            break

        default:
            debugPrintWithTimestamp("   Other event: \(event.type)")
            break
        }
    }

    func adsManager(_ adsManager: IMAAdsManager, didReceive error: IMAAdError) {
        let errorMessage = error.message ?? "Unknown ad error"
        adState = .error(errorMessage)

        if isMidrollAdSession {
            // Midroll error — resume silently
            debugPrintWithTimestamp("❌ Midroll ad error: \(errorMessage), resuming")
            resumeAfterMidroll()
        } else {
            playbackError = PlayerError.adLoadFailed(errorMessage)
            switchToMainVideoMode()
        }
    }

    func adsManagerDidRequestContentPause(_ adsManager: IMAAdsManager) {
        // Ad is starting, pause main video
        mainPlayer?.pause()
    }

    func adsManagerDidRequestContentResume(_ adsManager: IMAAdsManager) {
        if isMidrollAdSession {
            resumeAfterMidroll()
        } else {
            switchToMainVideoMode()
        }
    }

    /// Updates ad progress information.
    private func updateAdProgress(from ad: IMAAd, currentTime: TimeInterval) {
        let podInfo = ad.adPodInfo
        currentAdProgress = AdProgress(
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
        guard let progress = self.currentAdProgress else { return nil }

        return AdProgressInfo(
            currentAdNumber: progress.currentAdNumber,
            totalAds: progress.totalAds,
            currentTime: progress.currentTime,
            duration: progress.duration,
            isSkippable: progress.isSkippable,
            skipTimeRemaining: progress.skipTimeRemaining
        )
    }

    /// Normalized midroll cue point positions (0.0–1.0) for timeline markers.
    var midrollMarkerPositions: [Double] {
        guard duration > 0 else { return [] }
        return adCuePoints
            .filter { $0.type == .midRoll }
            .compactMap { $0.normalizedPosition(forDuration: duration) }
    }
}
