//
//  BCOVAdsPlayerViewControllerRepresentable.swift
//  SwiftUIPlayer
//
//  Copyright © 2024 Brightcove, Inc. All rights reserved.
//

import SwiftUI
import BrightcovePlayerSDK
import BrightcoveIMA
import GoogleInteractiveMediaAds

// MARK: - Custom Player View Controller

/// Custom view controller that subclasses BCOVPUIPlayerViewController
/// Handles IMA ads integration and delegate callbacks
class BCOVPUIIMAPlayerViewController: BCOVPUIPlayerViewController {

    // MARK: - Properties

    weak var playerModel: PlayerModel?
    private var statusBarHidden = false
    private var videoToPlay: BCOVVideo?
    private var imaPlaybackController: BCOVPlaybackController?

    // MARK: - Status Bar

    override var prefersStatusBarHidden: Bool {
        return statusBarHidden
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        print("🎬 BCOVPUIIMAPlayerViewController - viewDidLoad called")

        // Setup IMA playback controller after view is loaded
        setupIMAPlaybackController()

        // Load video if one was set
        if let video = videoToPlay {
            print("📹 Loading video from viewDidLoad")
            imaPlaybackController?.setVideos([video])
        }
    }

    // MARK: - Public Methods

    func setVideo(_ video: BCOVVideo) {
        print("📹 setVideo called with video ID: \(video.properties[BCOVVideo.PropertyKeyId] ?? "unknown")")
        self.videoToPlay = video

        // If view is already loaded, set video immediately
        if isViewLoaded, let controller = imaPlaybackController {
            print("📹 View already loaded, setting video immediately")
            controller.setVideos([video])
        } else {
            print("📹 View not loaded yet, will set video in viewDidLoad")
        }
    }

    // MARK: - Initialization

    convenience init(playerModel: PlayerModel) {
        print("🎬 BCOVPUIIMAPlayerViewController - Starting initialization")

        // Configure player view options
        let options = BCOVPUIPlayerViewOptions()
        options.automaticControlTypeSelection = true
        options.showPictureInPictureButton = true

        // Initialize with nil playback controller - we'll set it up in viewDidLoad
        self.init(playbackController: nil, options: options, controlsView: nil)

        // Store reference to player model
        self.playerModel = playerModel
        self.delegate = playerModel

        print("🎬 BCOVPUIIMAPlayerViewController - Basic initialization complete")
    }

    private func setupIMAPlaybackController() {
        print("🎬 BCOVPUIIMAPlayerViewController - Setting up IMA playback controller")

        // Configure IMA settings
        let imaSettings = IMASettings()
        if #available(iOS 16.0, *) {
            imaSettings.language = Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            imaSettings.language = Locale.current.languageCode ?? "en"
        }
        print("🌐 IMA language set to: \(imaSettings.language) ")

        // Configure IMA rendering settings
        let renderSettings = IMAAdsRenderingSettings()
        renderSettings.linkOpenerPresentingController = nil // Will be set after initialization

        // Configure cue point policy
        let policy = BCOVCuePointProgressPolicy(processingCuePoints: .processFinalCuePoint,
                                                resumingPlaybackFrom: .fromContentPlayhead,
                                                ignoringPreviouslyProcessedCuePoints: false)
        print("⚙️ Cue point policy configured")

        // Configure ads request policy
        // This uses the same VAST ad tag URL for all cue points
        let adsRequestPolicy = BCOVIMAAdsRequestPolicy(fromCuePointPropertiesWithAdTag: kVASTAdTagURL,
                                                       adsCuePointProgressPolicy: policy)
        print("📺 VAST Ad Tag URL: \(kVASTAdTagURL)")

        // Setup session providers
        let sdkManager = BCOVPlayerSDKManager.sharedManager()

        // Create FairPlay session provider (upstream)
        let authProxy = BCOVFPSBrightcoveAuthProxy(withPublisherId: nil,
                                                   applicationId: nil)
        let fpsSessionProvider = sdkManager.createFairPlaySessionProvider(withAuthorizationProxy: authProxy,
                                                                          upstreamSessionProvider: nil)
        print("🔐 FairPlay session provider created")

        // Now we can access the ad container from the player view (viewDidLoad has been called)
        guard let adContainerView = self.playerView?.contentOverlayView else {
            print("❌ Error: Could not get ad container view from player view")
            print("   playerView exists: \(self.playerView != nil)")
            return
        }
        print("✅ Ad container view obtained: \(adContainerView)")

        // Create IMA session provider options
        let imaPlaybackSessionOptions: [String: Any] = [
            kBCOVIMAOptionIMAPlaybackSessionDelegateKey: self
        ]
        print("🎯 IMA playback session options configured with delegate")

        // Create IMA session provider with the proper ad container
        guard let imaSessionProvider = sdkManager.createIMASessionProvider(with: imaSettings,
                                                                           adsRenderingSettings: renderSettings,
                                                                           adsRequestPolicy: adsRequestPolicy,
                                                                           adContainer: adContainerView,
                                                                           viewController: self,
                                                                           companionSlots: nil,
                                                                           upstreamSessionProvider: fpsSessionProvider,
                                                                           options: imaPlaybackSessionOptions) else {
            print("❌ Error: Failed to create IMA session provider")
            return
        }
        print("✅ IMA session provider created successfully")

        // Create the IMA-enabled playback controller
        let playbackController = sdkManager.createPlaybackController(withSessionProvider: imaSessionProvider,
                                                                     viewStrategy: nil)
        playbackController.isAutoAdvance = true
        playbackController.isAutoPlay = true
        playbackController.delegate = self
        playbackController.options = [kBCOVAVPlayerViewControllerCompatibilityKey: false]
        print("✅ IMA-enabled playback controller created")

        // Store the controller
        self.imaPlaybackController = playbackController

        // Set the playback controller on the playerView (this is the key!)
        self.playerView?.playbackController = playbackController
        print("✅ Playback controller set on playerView")
        print("   playerView exists: \(self.playerView != nil)")
        print("   playerView.playbackController exists: \(self.playerView?.playbackController != nil)")

        // Update rendering settings with proper presenting controller
        renderSettings.linkOpenerPresentingController = self
        print("🎬 BCOVPUIIMAPlayerViewController - IMA setup complete")
    }
}

// MARK: - BCOVPlaybackControllerDelegate

extension BCOVPUIIMAPlayerViewController: BCOVPlaybackControllerDelegate {

    func playbackController(_ controller: BCOVPlaybackController!,
                            didAdvanceTo session: BCOVPlaybackSession!) {
        print("📹 BCOVPUIIMAPlayerViewController - Advanced to new session")
        print("   Session: \(String(describing: session))")
        print("   Video: \(String(describing: session?.video))")

        // The ad container is automatically configured by the IMA plugin
        if playerView?.contentOverlayView != nil {
            print("✅ BCOVPUIIMAPlayerViewController - Ad container configured")
        } else {
            print("❌ BCOVPUIIMAPlayerViewController - Ad container NOT configured")
        }

        // Check for cue points
        if let video = session?.video, let cuePoints = video.cuePoints {
            print("📍 Video has \(cuePoints.count) cue points:")
            for (index, cuePoint) in cuePoints.array.enumerated() {
                if let cp = cuePoint as? BCOVCuePoint {
                    print("   [\(index)] Type: \(cp.type ?? "unknown"), Position: \(cp.position.seconds)s, Properties: \(cp.properties)")
                }
            }
        } else {
            print("⚠️ Video has NO cue points - ads will not play!")
        }
    }

    func playbackController(_ controller: BCOVPlaybackController!,
                            playbackSession session: BCOVPlaybackSession,
                            didReceive lifecycleEvent: BCOVPlaybackSessionLifecycleEvent!) {

        let eventType = lifecycleEvent.eventType
        print("🔄 Lifecycle Event: \(eventType)")

        if kBCOVPlaybackSessionLifecycleEventFail == lifecycleEvent.eventType,
           let error = lifecycleEvent.properties["error"] as? NSError {
            print("❌ BCOVPUIIMAPlayerViewController - Playback error: \(error.localizedDescription)")
        }

        // Log IMA-specific events
        if eventType.contains("kBCOVIMA") {
            print("📺 IMA Event: \(eventType)")
            print("   Properties: \(lifecycleEvent.properties)")
        }
    }
}

// MARK: - BCOVPlaybackControllerAdsDelegate

extension BCOVPUIIMAPlayerViewController: BCOVPlaybackControllerAdsDelegate {

    func playbackController(_ controller: BCOVPlaybackController,
                            playbackSession session: BCOVPlaybackSession,
                            didEnterAdSequence adSequence: BCOVAdSequence) {
        print("📺 BCOVPUIIMAPlayerViewController - ⏯️ ENTERING AD SEQUENCE")
        print("   Ad sequence: \(adSequence)")
    }

    func playbackController(_ controller: BCOVPlaybackController,
                            playbackSession session: BCOVPlaybackSession,
                            didExitAdSequence adSequence: BCOVAdSequence) {
        print("📺 BCOVPUIIMAPlayerViewController - ⏹️ EXITING AD SEQUENCE")
    }

    func playbackController(_ controller: BCOVPlaybackController,
                            playbackSession session: BCOVPlaybackSession,
                            didEnterAd ad: BCOVAd) {
        print("📺 BCOVPUIIMAPlayerViewController - ▶️ ENTERING AD")
        print("   Ad: \(ad)")
    }

    func playbackController(_ controller: BCOVPlaybackController,
                            playbackSession session: BCOVPlaybackSession,
                            didExitAd ad: BCOVAd) {
        print("📺 BCOVPUIIMAPlayerViewController - ⏹️ EXITING AD")
    }
}

// MARK: - BCOVPUIPlayerViewDelegate

extension BCOVPUIIMAPlayerViewController {

    override func playerView(_ playerView: BCOVPUIPlayerView!,
                             willTransitionTo screenMode: BCOVPUIScreenMode) {
        statusBarHidden = screenMode == .full
        setNeedsStatusBarAppearanceUpdate()
    }
}

// MARK: - BCOVIMAPlaybackSessionDelegate

extension BCOVPUIIMAPlayerViewController: BCOVIMAPlaybackSessionDelegate {

    func willCallIMAAdsLoaderRequestAds(with adsRequest: IMAAdsRequest!,
                                        forPosition position: TimeInterval) {
        // Customize the ads request before loading
        // For demo purposes, increase the VAST ad load timeout
        adsRequest.vastLoadTimeout = 3000.0
        print("📺 BCOVPUIIMAPlayerViewController - 🎯 willCallIMAAdsLoaderRequestAds")
        print("   Position: \(position)s")
        print("   Ad Tag URL: \(adsRequest.adTagUrl ?? "nil")")
        print("   VAST Load Timeout: \(String(format: "%.1f", adsRequest.vastLoadTimeout))ms")
    }
}

// MARK: - IMALinkOpenerDelegate

extension BCOVPUIIMAPlayerViewController: IMALinkOpenerDelegate {

    func linkOpenerDidOpen(inAppLink linkOpener: NSObject) {
        print("BCOVPUIIMAPlayerViewController - Link opener did open in-app link")
    }

    func linkOpenerDidClose(inAppLink linkOpener: NSObject) {
        print("BCOVPUIIMAPlayerViewController - Link opener did close in-app link")

        // Resume ad playback after closing the in-app browser
        playbackController?.resumeAd()
    }
}

// MARK: - SwiftUI Representable

/// A SwiftUI view that wraps IMAPlayerViewController using UIViewControllerRepresentable.
///
/// This approach provides:
/// - IMA ads integration with proper view controller hierarchy
/// - Full compatibility with Google IMA SDK
/// - Proper handling of ad-related view controller presentations
///
/// **Why use a custom subclass of BCOVPUIPlayerViewController?**
///
/// By subclassing BCOVPUIPlayerViewController, we can:
/// - Implement all necessary delegate protocols (IMA, ads, playback)
/// - Provide a proper view controller for IMA's ad presentation
/// - Handle status bar visibility during fullscreen transitions
/// - Manage the complete lifecycle of ads and playback in one place
///
/// This prevents common issues like:
/// - "child view controller should have parent view controller" errors
/// - Ad container not being properly attached to the view hierarchy
/// - Link opener not having a presenting view controller
struct BCOVAdsPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    typealias UIViewControllerType = BCOVPUIIMAPlayerViewController

    let playerModel: PlayerModel
    let video: BCOVVideo

    func makeUIViewController(context: Context) -> BCOVPUIIMAPlayerViewController {
        print("🎬 BCOVAdsPlayerViewControllerRepresentable - makeUIViewController called")

        let playerViewController = BCOVPUIIMAPlayerViewController(playerModel: playerModel)
        print("✅ Player view controller created")

        // Update video with IMA ad cue points
        print("📹 Original video: \(video)")
        print("   Video ID: \(video.properties[BCOVVideo.PropertyKeyId] ?? "unknown")")
        print("   Original cue points: \(video.cuePoints?.count ?? 0)")

        let videoWithAds = video.updateVideo(useAdTagsInCuePoints: true)
        print("📹 Video updated with ads")
        print("   Updated cue points: \(videoWithAds.cuePoints?.count ?? 0)")

        if let cuePoints = videoWithAds.cuePoints {
            for (index, cuePoint) in cuePoints.array.enumerated() {
                if let cp = cuePoint as? BCOVCuePoint {
                    print("   [\(index)] Type: \(cp.type ?? "unknown"), Position: \(cp.position.seconds)s, Properties: \(cp.properties)")
                }
            }
        }

        // Set video using the new method - this will load it in viewDidLoad
        playerViewController.setVideo(videoWithAds)

        return playerViewController
    }

    func updateUIViewController(_ uiViewController: BCOVPUIIMAPlayerViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Preview

#if DEBUG
struct BCOVAdsPlayerViewControllerRepresentable_Previews: PreviewProvider {
    static var previews: some View {
        let playerModel = PlayerModel()
        let video = BCOVVideo(withSource: nil, cuePoints: nil, properties: nil)
        BCOVAdsPlayerViewControllerRepresentable(playerModel: playerModel, video: video)
    }
}
#endif
