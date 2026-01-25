//
//  AVIMAPlayerView.swift
//  SwiftUIPlayer
//
//  Main video player view with IMA ad integration and dual-player architecture.
//

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

    let video: AVIMAVideoItem

    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    /// Creates a player view for the specified video.
    ///
    /// Uses nil default pattern to avoid Swift 6 concurrency errors with
    /// @MainActor ViewModels (per CLAUDE.md standards).
    ///
    /// - Parameter video: The video to play
    /// - Parameter viewModel: Optional ViewModel for testing
    init(video: AVIMAVideoItem, viewModel: AVIMAPlayerViewModel? = nil) {
        self.video = video
        _viewModel = StateObject(wrappedValue: viewModel ?? AVIMAPlayerViewModel())
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(video.name)
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
            await viewModel.loadVideo(video)
        }
        .onDisappear {
            viewModel.onDisappear()
        }
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
                    await viewModel.loadVideo(video)
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
            ZStack(alignment: .bottom) {
                // Player content area
                playerContent(in: geometry.size)

                // Overlay controls
                VStack {
                    Spacer()

                    AVIMAPlayerControlsView(viewModel: viewModel)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Player Content

    @ViewBuilder
    private func playerContent(in size: CGSize) -> some View {
        ZStack {
            // Main video player (always present, buffers during ads)
            if viewModel.playbackMode == .mainVideo || viewModel.mainVideoState == .buffering {
                Color.black

                // Placeholder for main video player
                // In production, this would be the AVPlayerViewController
                VStack {
                    Text("Main Video Player")
                        .foregroundStyle(.white.opacity(0.5))
                    if viewModel.playbackMode == .mainVideo {
                        Text("Playing: \(video.name)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            // Ad player (shown during ad playback)
            if viewModel.playbackMode == .advertisement {
                Color.black

                VStack {
                    Text("Ad Player")
                        .foregroundStyle(.yellow.opacity(0.5))

                    if let adProgress = viewModel.adProgress {
                        Text("Ad \(adProgress.currentAdNumber) of \(adProgress.totalAds)")
                            .font(.caption)
                            .foregroundStyle(.yellow.opacity(0.5))
                    }
                }
            }

            // Buffering indicator
            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)

                    Text("Buffering...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size.width, height: size.height)
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
