//
//  PlayerModel.swift
//  SwiftUICustomControls
//
//  Copyright © 2024 Brightcove, Inc. All rights reserved.
//

import AVKit
import SwiftUI
import BrightcovePlayerSDK


final class PlayerModel: NSObject, ObservableObject {

    @Published
    var fullscreenEnabled = false

    @Published
    var pictureInPictureEnabled = false

    /// Reference to the active BCOVPUIPlayerViewController for fullscreen control.
    weak var playerViewController: BCOVPUIPlayerViewController?

    /// Reference to the active AVPlayer for seeking.
    var currentPlayer: AVPlayer?

    fileprivate(set) lazy var avpvc: AVPlayerViewController = {
        let avpvc = AVPlayerViewController()
        avpvc.delegate = self
        return avpvc
    }()

    fileprivate(set) lazy var playbackController: BCOVPlaybackController? = {
        let sdkManager = BCOVPlayerSDKManager.sharedManager()
        let authProxy = BCOVFPSBrightcoveAuthProxy(withPublisherId: nil,
                                                         applicationId: nil)

        let fps = sdkManager.createFairPlaySessionProvider(withApplicationCertificate: nil,
                                                           authorizationProxy: authProxy,
                                                           upstreamSessionProvider: nil)

        let playbackController = sdkManager.createPlaybackController(withSessionProvider: fps,
                                                                           viewStrategy: nil)

        playbackController.delegate = self
        playbackController.isAutoAdvance = true
        playbackController.isAutoPlay = true

        return playbackController
    }()

}


// MARK: - AVPlayerViewControllerDelegate

extension PlayerModel: AVPlayerViewControllerDelegate {

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate { [weak self] _ in
            self?.fullscreenEnabled = true
        }
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate { [weak self] _ in
            self?.fullscreenEnabled = false
        }
    }

    func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        pictureInPictureEnabled = true
    }

    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        pictureInPictureEnabled = false
    }
}


// MARK: - BCOVPlaybackControllerDelegate

extension PlayerModel: BCOVPlaybackControllerDelegate {

    func playbackController(_ controller: BCOVPlaybackController!,
                            didAdvanceTo session: BCOVPlaybackSession!) {
        currentPlayer = session?.player

        if let player = session?.player,
           let options = controller.options,
           let useNative = options[kBCOVAVPlayerViewControllerCompatibilityKey] as? Bool,
           useNative {
            avpvc.player = player
        }

        debugPrintWithTimestamp("PlayerModel - Advanced to new session.")
    }

    func playbackController(_ controller: BCOVPlaybackController!,
                            playbackSession session: BCOVPlaybackSession,
                            didReceive lifecycleEvent: BCOVPlaybackSessionLifecycleEvent!) {

        if kBCOVPlaybackSessionLifecycleEventFail == lifecycleEvent.eventType,
           let error = lifecycleEvent.properties["error"] as? NSError {
            // Report any errors that may have occurred with playback.
            debugPrintWithTimestamp("PlayerModel - Playback error: \(error.localizedDescription)")
        }
    }

}


// MARK: - Deep Link Actions

extension PlayerModel {

    func enterFullscreen() {
        playerViewController?.playerView?.performScreenTransition(with: .full)
    }

    func exitFullscreen() {
        playerViewController?.playerView?.performScreenTransition(with: .normal)
    }

    func seek(to seconds: TimeInterval) {
        let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
        currentPlayer?.seek(to: cmTime)
    }
}


// MARK: - BCOVPUIPlayerViewDelegate

extension PlayerModel: BCOVPUIPlayerViewDelegate {

    func playerView(_ playerView: BCOVPUIPlayerView!, willTransitionTo screenMode: BCOVPUIScreenMode) {
        fullscreenEnabled = screenMode == .full
    }

    func pictureInPictureControllerDidStartPicture(inPicture pictureInPictureController: AVPictureInPictureController!) {
        pictureInPictureEnabled = true
    }

    func pictureInPictureControllerDidStopPicture(inPicture pictureInPictureController: AVPictureInPictureController!) {
        pictureInPictureEnabled = false
    }
}
