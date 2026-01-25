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
        .task {
            await viewModel.loadVideos()
        }
        .refreshable {
            await viewModel.refresh()
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
    private func videoList(videos: [IMAVideoItem]) -> some View {
        List(videos) { video in
            NavigationLink {
                AVIMAPlayerView(video: video)
            } label: {
                VideoRowView(video: video)
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Video Row View

/// Individual row view for a video item.
///
/// Displays video metadata in a consistent format with clear visual hierarchy.
private struct VideoRowView: View {

    // MARK: - Properties

    let video: IMAVideoItem

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

// MARK: - ViewModel

/// ViewModel managing the IMA Player video library state.
///
/// Follows CLAUDE.md patterns:
/// - Uses LoadResult for async state
/// - @MainActor for main thread isolation
/// - Closed loops with @Published properties
/// - Guard clauses to prevent duplicate fetches
@MainActor
class AVIMAPlayerListViewModel: ObservableObject {

    // MARK: - Published State

    /// Load state for videos
    @Published private(set) var videosLoadResult: LoadResult<[IMAVideoItem]> = .notStarted

    // MARK: - Computed Properties

    /// Videos array (empty if not loaded)
    var videos: [IMAVideoItem] {
        videosLoadResult.value ?? []
    }

    /// Whether videos are currently loading
    var isLoading: Bool {
        videosLoadResult.active
    }

    // MARK: - Public API

    /// Loads the video list.
    ///
    /// Skips load if already loaded and not forced.
    /// Prevents duplicate fetches while loading.
    ///
    /// - Parameter forced: Whether to force reload even if already loaded
    func loadVideos(forced: Bool = false) async {
        // Skip if already loaded and not forced
        guard forced || !videosLoadResult.loaded else { return }

        // Prevent duplicate fetches
        guard !videosLoadResult.active else { return }

        videosLoadResult = .loading

        // Simulate network delay for demo
        try? await Task.sleep(for: .milliseconds(500))

        // For now, use sample data
        // In production, this would fetch from an API
        videosLoadResult = .success(IMAVideoItem.samples)
    }

    /// Refreshes the video list.
    func refresh() async {
        await loadVideos(forced: true)
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
