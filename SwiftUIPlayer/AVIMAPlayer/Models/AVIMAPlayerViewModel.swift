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
/// **Playback Modes:**
/// - `.idle`: No content loaded
/// - `.mainVideo`: Playing main content
/// - `.advertisement`: Playing IMA ad content
///
/// **Control Restrictions:**
/// - During ads: Only pause/play and mute allowed
/// - During main content: Full controls available
@MainActor
class AVIMAPlayerViewModel: ObservableObject {

    // MARK: - Nested Types

    /// Represents the current playback mode
    enum PlaybackMode: Equatable {
        /// No content is loaded
        case idle

        /// Playing main video content
        case mainVideo

        /// Playing advertisement content
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
    struct AdProgress: Equatable {
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

    /// Time observer for main player
    private var mainTimeObserver: Any?

    /// Time observer for ad player
    private var adTimeObserver: Any?

    /// Combine cancellables
    private var cancellables = Set<AnyCancellable>()

    /// Whether playback was active before backgrounding
    private var wasPlayingBeforeBackground = false

    // MARK: - Initialization

    init() {
        setupMuteObserver()
        setupLifecycleObservers()
    }

    deinit {
        cleanup()
        removeLifecycleObservers()
    }

    // MARK: - Public API (Called by View)

    /// Loads a video and initializes the player.
    ///
    /// This creates the dual-player setup with proper IMA integration.
    /// Main video begins buffering while IMA ads are loaded.
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
        switch playbackMode {
        case .mainVideo:
            mainPlayer?.play()
            mainVideoState = .playing

        case .advertisement:
            adsManager?.resume()
            adState = .playing

        case .idle:
            break
        }
    }

    /// Pauses playback.
    ///
    /// Works in both ad and main video modes.
    func pause() {
        switch playbackMode {
        case .mainVideo:
            mainPlayer?.pause()
            mainVideoState = .paused

        case .advertisement:
            adsManager?.pause()
            adState = .paused

        case .idle:
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

    /// Called when the view disappears.
    ///
    /// Pauses playback to conserve resources.
    func onDisappear() {
        pause()
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
        let playbackController = BCOVPlayerSDKManager.shared().createPlaybackController()
        playbackController.delegate = self
        playbackController.isAutoPlay = false
        playbackController.isAutoAdvance = false
        self.mainPlaybackController = playbackController

        // Set video
        playbackController.setVideos([video.video] as NSFastEnumeration)

        // Set up time observer
        setupMainPlayerTimeObserver()

        mainVideoState = .ready
    }

    /// Initializes the IMA ads loader and manager.
    private func initializeIMAPlayer(with video: AVIMAVideoItem) async throws {
        guard let adTagURL = URL(string: video.adTagURL) else {
            throw PlayerError.invalidAdTagURL
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

        // Request ads
        let request = IMAAdsRequest(
            adTagUrl: adTagURL.absoluteString,
            adDisplayContainer: nil,
            contentPlayhead: nil,
            userContext: nil
        )

        adsLoader.requestAds(with: request)

        // Set up time observer for ad player
        setupAdPlayerTimeObserver()
    }

    /// Sets up time observation for main player.
    private func setupMainPlayerTimeObserver() {
        guard let player = mainPlayer else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        mainTimeObserver = player.addPeriodicTimeObserver(
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
    }

    /// Sets up time observation for ad player.
    private func setupAdPlayerTimeObserver() {
        guard let player = adPlayer else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        adTimeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self,
                  self.playbackMode == .advertisement else { return }

            self.currentTime = time.seconds
        }
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
    private func switchToAdMode() {
        playbackMode = .advertisement
        mainPlayer?.pause()
        adState = .playing
    }

    /// Switches playback mode back to main video.
    private func switchToMainVideoMode() {
        playbackMode = .mainVideo
        adState = .idle
        adProgress = nil
        mainPlayer?.play()
        mainVideoState = .playing
    }

    /// Cleans up players and observers.
    private func cleanup() {
        if let observer = mainTimeObserver {
            mainPlayer?.removeTimeObserver(observer)
            mainTimeObserver = nil
        }

        if let observer = adTimeObserver {
            adPlayer?.removeTimeObserver(observer)
            adTimeObserver = nil
        }

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
        // Main video session started
        if let player = session.player {
            self.mainPlayer = player
            player.isMuted = isMuted
        }
    }

    func playbackController(
        _ controller: BCOVPlaybackController!,
        playbackSession session: BCOVPlaybackSession!,
        didReceive lifecycleEvent: BCOVPlaybackSessionLifecycleEvent!
    ) {
        guard let eventType = lifecycleEvent.eventType else { return }

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
        let manager = adsLoadedData.adsManager
        manager.delegate = self
        manager.initialize(with: nil)
        self.adsManager = manager

        // Start ads
        manager.start()
        switchToAdMode()
    }

    func adsLoader(_ loader: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
        let errorMessage = adErrorData.adError.message ?? "Unknown ad error"
        adState = .error(errorMessage)
        playbackError = PlayerError.adLoadFailed(errorMessage)

        // Fall back to main video
        switchToMainVideoMode()
    }
}

// MARK: - IMAAdsManagerDelegate

extension AVIMAPlayerViewModel: IMAAdsManagerDelegate {

    func adsManager(_ adsManager: IMAAdsManager, didReceive event: IMAAdEvent) {
        switch event.type {
        case .LOADED:
            adState = .ready

        case .STARTED:
            adState = .playing
            if let ad = event.ad {
                updateAdProgress(from: ad, currentTime: 0)
            }

        case .PAUSE:
            adState = .paused

        case .RESUME:
            adState = .playing

        case .COMPLETE:
            adState = .completed
            adProgress = nil

        case .ALL_ADS_COMPLETED:
            switchToMainVideoMode()

        case .SKIPPED:
            switchToMainVideoMode()

        default:
            break
        }
    }

    func adsManager(_ adsManager: IMAAdsManager, didReceive error: IMAAdError) {
        let errorMessage = error.message ?? "Unknown ad error"
        adState = .error(errorMessage)
        playbackError = PlayerError.adLoadFailed(errorMessage)

        // Fall back to main video
        switchToMainVideoMode()
    }

    func adsManagerDidRequestContentPause(_ adsManager: IMAAdsManager) {
        mainPlayer?.pause()
    }

    func adsManagerDidRequestContentResume(_ adsManager: IMAAdsManager) {
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
