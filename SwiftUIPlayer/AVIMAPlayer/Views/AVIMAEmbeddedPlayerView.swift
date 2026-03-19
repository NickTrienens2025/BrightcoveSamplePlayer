//
//  AVIMAEmbeddedPlayerView.swift
//  SwiftUIPlayer
//
//  Inline player that shares its ViewModel with a fullscreen cover for
//  seamless enter/exit transitions without restarting playback.
//

import SwiftUI

/// An inline (embedded) player for a single video that supports expanding to fullscreen.
///
/// **Fullscreen architecture:**
/// - Owns one `AVIMAPlayerViewModel` for the lifetime of this view
/// - The embedded player renders with `showNavigationChrome: false` so it doesn't
///   inject toolbar items into the parent NavigationStack
/// - Fullscreen is presented via `.fullScreenCover`, sharing the **same ViewModel**
///   so the in-progress playback (ad or main video) continues without restarting
/// - `AdContainerViewController.viewWillAppear` re-registers the IMA container when
///   the embedded view reappears after the fullscreen cover is dismissed
///
/// **Usage:**
/// ```swift
/// AVIMAEmbeddedPlayerView(video: videos.first!)
/// ```
struct AVIMAEmbeddedPlayerView: View {

    // MARK: - Properties

    let video: AVIMAVideoItem

    @StateObject private var viewModel: AVIMAPlayerViewModel
    @State private var isFullscreen = false

    // MARK: - Initialization

    init(video: AVIMAVideoItem, viewModel: AVIMAPlayerViewModel? = nil) {
        self.video = video
        _viewModel = StateObject(wrappedValue: viewModel ?? AVIMAPlayerViewModel())
    }

    // MARK: - Body

    var body: some View {
        AVIMAPlayerView(
            video: video,
            showNavigationChrome: false,
            cleanupOnDisappear: false,
            // Suppress AVPlayerViewController while fullscreen cover is open so the
            // shared AVPlayer is rendered only by the fullscreen's AVPlayerViewController.
            suppressPlayerView: isFullscreen,
            onExpand: {
                isFullscreen = true
            },
            viewModel: viewModel
        )
        .aspectRatio(video.aspectRatio, contentMode: .fit)
        .clipped()
        .accessibilityIdentifier(AccessibilityID.Player.embedded)
        .fullScreenCover(isPresented: $isFullscreen) {
            fullscreenPlayer
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    // MARK: - Fullscreen Player

    /// Full-screen presentation sharing the same ViewModel.
    ///
    /// Uses `cleanupOnDisappear: false` so dismissing this cover does NOT destroy
    /// the ViewModel — the embedded player continues using it immediately.
    ///
    /// No NavigationStack — the video fills the entire screen edge-to-edge.
    /// The close button lives inside the controls overlay and hides/shows with controls.
    ///
    /// `onAppear` shows controls immediately so they're visible the moment fullscreen opens.
    private var fullscreenPlayer: some View {
        AVIMAPlayerView(
            video: video,
            allowsFullscreen: false,
            showNavigationChrome: false,
            cleanupOnDisappear: false,
            onClose: {
                isFullscreen = false
            },
            viewModel: viewModel
        )
        .accessibilityIdentifier(AccessibilityID.Player.fullscreen)
        .background(Color.black.ignoresSafeArea())
        .onAppear { viewModel.showControls() }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - Preview

#if DEBUG
struct AVIMAEmbeddedPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            List {
                Section {
                    AVIMAEmbeddedPlayerView(video: AVIMAVideoItem.samples[0])
                        .listRowInsets(EdgeInsets())
                }
                Section("Videos") {
                    Text("More content below...")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Preview")
        }
        .preferredColorScheme(.dark)
    }
}
#endif
