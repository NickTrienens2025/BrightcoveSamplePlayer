# Investigation Log - BCOV IMA Integration

## Failed Attempt: Subclassing BCOVPUIPlayerViewController (Side Path)

**Date:** April 10, 2026
**Issue:** `UIViewControllerHierarchyInconsistency` crash during fullscreen transition.

### Strategy
To resolve the crash where the `IMAAdViewController` was not properly reparented during fullscreen transitions, the following approach was taken in `BCOVAdsPlayerViewControllerRepresentable.swift`:

1.  **Manual Reparenting via Super**: Overrode `playerView(_:willTransitionTo:)` and called `super` to allow the Brightcove SDK to handle the UIKit transition logic.
2.  **Delayed Initialization**: Moved the creation of the `BCOVPlaybackController` and IMA session provider into `viewDidLoad`. This ensured that `self.playerView` was already instantiated so that `playerView.contentOverlayView` could be passed as the ad container.
3.  **Base Class Property Usage**: Used the inherited `self.playbackController` property instead of a private shadow property, aiming to let the base class "own" the playback state.
4.  **Explicit ViewController Assignment**: Passed `self` (the `BCOVPUIPlayerViewController` subclass) as the `viewController` in `createIMASessionProvider`.

### Observed Outcome
*   **Playback Failure**: **TOTAL FAILURE**. Neither the IMA ads nor the main content video would play. The player remained in a permanent idle/black state.
*   **Crash Status**: **UNVERIFIED/NOT REACHED**. Because playback failed to start entirely, the ad-related code path was never executed. Consequently, we could not get to the point where the hierarchy crash would normally occur (which requires an active ad to be on screen during a transition).
*   **Logs**: `didAdvanceTo session` was called, but the `AVPlayer` layer never rendered content, and no ad events were triggered.

### Conclusion
Subclassing `BCOVPUIPlayerViewController` and attempting to wire the IMA plugin manually into its lifecycle via `viewDidLoad` is a broken pattern for the Brightcove SDK. The SDK likely requires the playback controller to be established and fully configured during `init`. By the time `viewDidLoad` runs, the internal bindings between the UI components and the playback engine are already missed if the controller is nil.

**Status:** Stashed and abandoned. This path is invalid as it breaks core playback.
