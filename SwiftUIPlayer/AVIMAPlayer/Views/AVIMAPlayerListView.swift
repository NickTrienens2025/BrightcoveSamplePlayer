//
//  AVIMAPlayerListView.swift
//  SwiftUIPlayer
//
//  List view for selecting videos to play with the AVIMA Player.
//

import SwiftUI

/// List view for browsing and selecting videos for the AVIMA Player.
///
/// This is the entry point for the AVIMA Player tab - it shows available
/// videos that can be played with the custom IMA ad integration.
///
/// **Features:**
/// - Displays video metadata (name, description, duration)
/// - Navigates to dedicated IMA player view on selection
/// - Uses LoadResult for data state management
/// - Follows CLAUDE.md ViewModel patterns
///
/// **Data Flow:**
/// Videos are loaded via ViewModel with complete state tracking.
/// Each video tap navigates to `AVIMAPlayerView` with isolated player instance.
struct AVIMAPlayerListView: View {

    // MARK: - Properties

    @StateObject private var viewModel: AVIMAPlayerListViewModel
    @State private var fullscreenVideo: AVIMAVideoItem?

    // MARK: - Initialization

    /// Creates the list view.
    ///
    /// Uses nil default pattern to avoid Swift 6 concurrency errors with
    /// @MainActor ViewModels (per CLAUDE.md standards).
    ///
    /// - Parameter viewModel: Optional ViewModel for testing
    init(viewModel: AVIMAPlayerListViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AVIMAPlayerListViewModel())
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("IMA Video Player")
                .navigationBarTitleDisplayMode(.large)
        }
        .accessibilityIdentifier(AccessibilityID.VideoList.container)
        .task {
            await viewModel.loadVideos()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .fullScreenCover(item: $fullscreenVideo) { video in
            fullscreenPlayerView(video: video)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.videosLoadResult {
        case .notStarted:
            EmptyView()

        case .loading:
            loadingView

        case .error(let error):
            errorView(error: error)

        case .success(let videos):
            videoList(videos: videos)
        }
    }

    // MARK: - Loading View

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()

            Text("Loading videos...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(error: Error) -> some View {
        CustomContentUnavailableView(
            "Unable to Load Videos",
            systemImage: "exclamationmark.triangle",
            description: error.localizedDescription
        ) {
            Button("Retry") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Video List

    @ViewBuilder
    private func videoList(videos: [AVIMAVideoItem]) -> some View {
        VStack(spacing: 0) {
            // Featured inline player OUTSIDE the List so UITableView gesture
            // recognizers don't intercept IMA ad taps ("Learn More", click-throughs).
            if let firstVideo = videos.first {
                AVIMAEmbeddedPlayerView(video: firstVideo)
                    .background(Color.black)
                    .accessibilityIdentifier(AccessibilityID.VideoList.embeddedSection)
            }

            // Full video list — each row navigates to the dedicated player screen.
            List {
                Section("All Videos") {
                    ForEach(videos) { video in
                        HStack {
                            NavigationLink {
                                AVIMAPlayerView(videoId: video.id)
                            } label: {
                                VideoRowView(video: video)
                            }

                            // Fullscreen launch button
                            Button {
                                fullscreenVideo = video
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(.blue))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play fullscreen")
                        }
                        .accessibilityIdentifier(AccessibilityID.VideoList.videoRow(id: video.id))
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Fullscreen Player

    /// Standalone fullscreen player presented via `.fullScreenCover`.
    /// No navigation chrome — close button overlay dismisses.
    private func fullscreenPlayerView(video: AVIMAVideoItem) -> some View {
        AVIMAPlayerView(
            video: video,
            showNavigationChrome: false
        )
        .overlay(alignment: .topLeading) {
            Button {
                fullscreenVideo = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.leading, 16)
            .accessibilityIdentifier(AccessibilityID.Controls.closeButton)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - Video Row View

/// Individual row view for a video item.
///
/// Displays video metadata in a consistent format with clear visual hierarchy.
private struct VideoRowView: View {

    // MARK: - Properties

    let video: AVIMAVideoItem

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Video name
            Text(video.name)
                .font(.headline)
                .foregroundStyle(.primary)

            // Description
            if !video.description.isEmpty {
                Text(video.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Metadata row
            HStack(spacing: 12) {
                // Duration
                if let duration = video.duration {
                    Label(
                        formatDuration(duration),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // Ad indicator
                Label("IMA Ads", systemImage: "rectangle.stack.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    /// Formats duration as MM:SS or H:MM:SS.
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AVIMAPlayerListView_Previews: PreviewProvider {
    static var previews: some View {
        AVIMAPlayerListView()
    }
}
#endif
