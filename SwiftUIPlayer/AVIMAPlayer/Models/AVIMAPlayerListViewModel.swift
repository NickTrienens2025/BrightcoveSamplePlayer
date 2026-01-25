//
//  AVIMAPlayerListViewModel.swift
//  SwiftUIPlayer
//
//  ViewModel managing the IMA Player video library state.
//  Follows CLAUDE.md standards for SwiftUI ViewModels with complete closed loops.
//

import Foundation

/// ViewModel managing the IMA Player video library state.
///
/// This ViewModel handles loading and managing the list of videos available
/// for playback with the IMA Player feature.
///
/// **State Management:**
/// Uses LoadResult pattern from Shared utilities for unified async state tracking.
/// All state changes are exposed via @Published properties for complete closed loops.
///
/// **Data Loading:**
/// Implements guard clauses to prevent duplicate fetches and unnecessary reloads.
/// Supports both initial load and forced refresh operations.
///
/// **CLAUDE.md Compliance:**
/// - LoadResult for async state (not separate isLoading/error/data)
/// - @MainActor for main thread isolation
/// - Guard clauses prevent duplicate operations
/// - Computed properties for derived state
/// - Complete closed loops with @Published properties
@MainActor
class AVIMAPlayerListViewModel: ObservableObject {

    // MARK: - Published State (Observable by View)

    /// Load state for videos
    ///
    /// Tracks the complete lifecycle of video loading:
    /// - `.notStarted`: Initial state, no load attempted
    /// - `.loading`: Currently fetching videos
    /// - `.success([IMAVideoItem])`: Videos loaded successfully
    /// - `.error(Error)`: Load failed with error
    @Published private(set) var videosLoadResult: LoadResult<[IMAVideoItem]> = .notStarted

    // MARK: - Computed Properties (Derived State)

    /// Videos array (empty if not loaded).
    ///
    /// Provides safe access to loaded videos with empty array fallback.
    /// View can bind to this without handling optionals.
    var videos: [IMAVideoItem] {
        videosLoadResult.value ?? []
    }

    /// Whether videos are currently loading.
    ///
    /// True when LoadResult is in `.loading` state.
    /// View uses this to show loading indicators.
    var isLoading: Bool {
        videosLoadResult.active
    }

    /// Whether videos have been successfully loaded.
    ///
    /// True when LoadResult is in `.success` state.
    var isLoaded: Bool {
        videosLoadResult.loaded
    }

    /// Current error if load failed.
    ///
    /// Nil when no error. View uses this to show error states.
    var error: Error? {
        videosLoadResult.error
    }

    // MARK: - Initialization

    init() {
        // No initialization needed - state starts as .notStarted
    }

    // MARK: - Public API (Called by View)

    /// Loads the video list.
    ///
    /// Implements smart loading behavior:
    /// - Skips if already loaded (unless forced)
    /// - Prevents duplicate simultaneous fetches
    /// - Updates state through complete closed loop
    ///
    /// **Usage:**
    /// ```swift
    /// .task {
    ///     await viewModel.loadVideos()
    /// }
    /// ```
    ///
    /// - Parameter forced: Whether to force reload even if already loaded
    func loadVideos(forced: Bool = false) async {
        // Skip if already loaded and not forced
        guard forced || !videosLoadResult.loaded else { return }

        // Prevent duplicate fetches
        guard !videosLoadResult.active else { return }

        videosLoadResult = .loading

        // Simulate network delay for demo
        // In production, replace with actual API call
        try? await Task.sleep(for: .milliseconds(500))

        // For now, use sample data
        // TODO: Replace with actual API integration
        // Example:
        // do {
        //     let videos = try await fetchVideosFromAPI()
        //     videosLoadResult = .success(videos)
        // } catch {
        //     videosLoadResult = .error(error)
        // }
        videosLoadResult = .success(IMAVideoItem.samples)
    }

    /// Refreshes the video list.
    ///
    /// Forces a reload regardless of current state.
    /// View calls this from pull-to-refresh action.
    ///
    /// **Usage:**
    /// ```swift
    /// .refreshable {
    ///     await viewModel.refresh()
    /// }
    /// ```
    func refresh() async {
        await loadVideos(forced: true)
    }

    // MARK: - Private Implementation

    // Future: Add private helper methods for API integration
    // private func fetchVideosFromAPI() async throws -> [IMAVideoItem] { ... }
}
