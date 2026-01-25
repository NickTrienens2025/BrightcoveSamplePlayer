# IMA Video Player System

A comprehensive video player with Google IMA (Interactive Media Ads) integration, built following SwiftUI best practices and CLAUDE.md standards.

---

## Overview

The IMA Player system provides a complete video playback solution with:

- **Dual-player architecture** for seamless ad/content transitions
- **Complete state management** with closed loops
- **Unified controls** that adapt to playback mode
- **Resilient error handling** with user feedback
- **Main video buffering** during ad playback

---

## Platform Requirements

- **Minimum iOS Version:** 16.0
- **Brightcove SDK:** Latest compatible version
- **Google IMA SDK:** 3.19.1+
- **Swift:** 5.9+

**iOS 16 Compatibility:**
The player uses a custom `CustomContentUnavailableView` instead of the iOS 17+ `ContentUnavailableView` to maintain backwards compatibility with iOS 16. All other features are compatible with iOS 16.0 and above.

---

## Architecture

### Dual-Player Design

The system uses two separate `AVPlayer` instances:

1. **Main Video Player**
   - Handles primary content playback
   - Continues buffering during ad playback
   - Managed via Brightcove SDK

2. **Ad Player**
   - Handles IMA advertisement playback
   - Takes over view during ad cue points
   - Managed via Google IMA SDK

**Benefits:**
- Main video buffers while ads play (faster resume)
- Clean separation of concerns
- Independent state management
- No playback interruptions during transitions

### State Management

Following CLAUDE.md principles, all state is managed through `@Published` properties with complete closed loops:

```swift
@MainActor
class AVIMAPlayerViewModel: ObservableObject {
    // Observable state
    @Published private(set) var playbackMode: PlaybackMode = .idle
    @Published private(set) var mainVideoState: PlayerState = .idle
    @Published private(set) var adState: PlayerState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published var isMuted: Bool = false

    // Computed properties (derived from @Published state)
    var isPlaying: Bool { ... }
    var canSkip: Bool { ... }
    var canSeek: Bool { ... }
}
```

**Closed Loop Guarantee:**
- Every state change updates a `@Published` property
- View observes and responds to all state changes
- No silent failures or console-only errors
- User always receives feedback

---

## Components

### 1. AVIMAVideoItem

**File:** `Models/AVIMAVideoItem.swift`

Model representing a video with IMA ad configuration.

```swift
struct AVIMAVideoItem: Identifiable {
    let id: String
    let name: String
    let description: String
    let thumbnailURL: String?
    let duration: TimeInterval?
    let adTagURL: String        // IMA ad tag URL
    let video: BCOVVideo
}
```

**Usage:**
```swift
let videoItem = AVIMAVideoItem(
    id: "video-1",
    name: "Sample Video",
    description: "Demonstrates IMA ad integration",
    adTagURL: "https://pubads.g.doubleclick.net/...",
    video: brightcoveVideo
)
```

### 2. AVIMAPlayerViewModel

**File:** `Models/AVIMAPlayerViewModel.swift`

Main ViewModel managing all player state and logic.

**Key Features:**
- `@MainActor` for main thread isolation
- LoadStatus for initialization state
- Separate state tracking for main/ad players
- Complete control restrictions based on mode
- Comprehensive error handling

**Playback Modes:**

```swift
enum PlaybackMode {
    case idle           // No content loaded
    case mainVideo      // Playing main content
    case advertisement  // Playing ad content
}
```

**Player States:**

```swift
enum PlayerState {
    case idle
    case loading
    case ready
    case playing
    case paused
    case buffering
    case error(String)
    case completed
}
```

**Public API:**

| Method | Purpose | Restrictions |
|--------|---------|--------------|
| `loadVideo(_:)` | Loads video and initializes players | Async, prevents duplicate loads |
| `play()` | Starts/resumes playback | Works in all modes |
| `pause()` | Pauses playback | Works in all modes |
| `toggleMute()` | Toggles audio mute | Works in all modes |
| `seek(to:)` | Seeks to time position | **Only during main video** |
| `skipAd()` | Skips current ad | **Only for skippable ads** |

### 3. AVIMAPlayerControlsView

**File:** `Views/AVIMAPlayerControlsView.swift`

Unified controls that adapt to playback mode.

**Features:**
- Consistent UI in both modes
- Dynamic enable/disable based on mode
- Progress slider (seekable for main video, static for ads)
- Ad info banner with progress
- Skip button (only for skippable ads)

**Control Behavior:**

| Control | Main Video | Advertisement |
|---------|------------|---------------|
| Play/Pause | ✅ Enabled | ✅ Enabled |
| Seek | ✅ Enabled | ❌ Disabled |
| Mute | ✅ Enabled | ✅ Enabled |
| Skip | ❌ Hidden | ✅ If skippable |

### 4. AVIMAPlayerView

**File:** `Views/AVIMAPlayerView.swift`

Main player view with complete UX flow.

**Features:**
- Loading state with spinner
- Error state with retry button
- Dual player rendering
- Overlay controls
- Playback mode indicators

**State Handling:**

```swift
switch viewModel.initializationStatus {
case .notStarted:
    EmptyView()

case .loading:
    ProgressView() + "Loading video..."

case .error(let error):
    ErrorView with retry button

case .success:
    Player with controls
}
```

### 5. AVIMAPlayerListView

**File:** `Views/AVIMAPlayerListView.swift`

List view displaying available videos.

**Features:**
- Video metadata display (name, description, duration)
- IMA ad indicator badge
- Pull-to-refresh
- Error handling with retry (iOS 16 compatible)
- LoadResult pattern for data state

**ViewModel:**

```swift
@MainActor
class AVIMAPlayerListViewModel: ObservableObject {
    @Published private(set) var videosLoadResult: LoadResult<[AVIMAVideoItem]> = .notStarted

    func loadVideos(forced: Bool = false) async
    func refresh() async
}
```

### 6. CustomContentUnavailableView

**File:** `Views/CustomContentUnavailableView.swift`

iOS 16 compatible alternative to `ContentUnavailableView` (iOS 17+).

**Purpose:**
Provides backwards compatibility for error and empty states on iOS 16, where Apple's `ContentUnavailableView` is not available.

**Features:**
- Title with SF Symbol icon
- Optional description text
- Optional action buttons
- Centered layout with consistent spacing
- Same visual appearance as iOS 17's ContentUnavailableView

**Usage:**
```swift
// With action button
CustomContentUnavailableView(
    "Unable to Load Videos",
    systemImage: "exclamationmark.triangle",
    description: error.localizedDescription
) {
    Button("Retry") {
        Task { await viewModel.refresh() }
    }
    .buttonStyle(.borderedProminent)
}

// Without action button
CustomContentUnavailableView(
    "No Videos",
    systemImage: "video.slash",
    description: "There are no videos available."
)
```

**Design Notes:**
- Matches iOS 17 ContentUnavailableView API surface
- Uses iOS 16-compatible SwiftUI components
- Automatically adjusts to iOS 17+ if available (future-proof)

---

## Usage

### Basic Integration

1. **Add to ContentView:**

```swift
AVIMAPlayerListView()
    .tabItem {
        Label("IMA Player", systemImage: "play.rectangle.fill")
    }
```

2. **Select a video from the list:**
   - Tap any video to navigate to player
   - Player automatically loads and initializes
   - Ads play at configured cue points

3. **Controls:**
   - **Play/Pause:** Tap center button
   - **Seek:** Drag slider (main video only)
   - **Mute:** Tap speaker icon
   - **Skip Ad:** Tap "Skip" button (if available)

### Programmatic Playback

```swift
let viewModel = AVIMAPlayerViewModel()
let video = AVIMAVideoItem(...)

// Load video
await viewModel.loadVideo(video)

// Control playback
viewModel.play()
viewModel.pause()
viewModel.toggleMute()
viewModel.seek(to: 30.0)  // Seek to 30 seconds

// Monitor state
if viewModel.playbackMode == .advertisement {
    print("Playing ad \(viewModel.adProgress?.currentAdNumber ?? 0)")
}
```

---

## Design Decisions

### Why Dual Players?

**Problem:** Switching between ad and main content in a single player causes:
- Playback interruptions
- Buffer delays on resume
- Complex state management

**Solution:** Separate players allow:
- Main video buffers during ad playback
- Instant resume after ads
- Clear state separation
- Independent error handling

### Why Unified Controls?

**Problem:** Separate control UIs for ads/content create:
- Inconsistent user experience
- Layout shifts during transitions
- Duplicate code

**Solution:** Single control view that adapts:
- Consistent visual design
- Smooth transitions
- Single source of truth
- Controls enable/disable based on context

### State Management Pattern

**Following CLAUDE.md standards:**

1. **LoadResult for Async State**
   ```swift
   @Published private(set) var videosLoadResult: LoadResult<[AVIMAVideoItem]> = .notStarted
   ```
   - Prevents fragmented state (separate isLoading/error/data)
   - Impossible states are impossible
   - Clear lifecycle: notStarted → loading → success/error

2. **Closed Loops**
   ```swift
   // Every state change updates @Published property
   func play() {
       mainPlayer?.play()
       mainVideoState = .playing  // ✅ Observable by View
   }
   ```

3. **Computed Properties**
   ```swift
   // Derive UI state from @Published properties
   var isPlaying: Bool {
       switch playbackMode {
       case .mainVideo: return mainVideoState == .playing
       case .advertisement: return adState == .playing
       case .idle: return false
       }
   }
   ```

4. **Complete Code Paths**
   ```swift
   @discardableResult
   func skipAd() -> Bool {
       guard canSkip, playbackMode == .advertisement else {
           return false  // View knows skip failed
       }
       adsManager?.skip()
       return true  // View knows skip succeeded
   }
   ```

---

## Testing

### Unit Testing ViewModels

```swift
@MainActor
func testPlaybackStateTransitions() async throws {
    let viewModel = AVIMAPlayerViewModel()
    let video = AVIMAVideoItem.samples[0]

    // Test loading
    XCTAssertEqual(viewModel.initializationStatus, .notStarted)
    await viewModel.loadVideo(video)
    XCTAssertEqual(viewModel.initializationStatus, .success)

    // Test playback
    viewModel.play()
    XCTAssertTrue(viewModel.isPlaying)

    viewModel.pause()
    XCTAssertFalse(viewModel.isPlaying)
}

@MainActor
func testAdRestrictions() {
    let viewModel = AVIMAPlayerViewModel()

    // Simulate ad mode
    // (requires mocking IMA callbacks)

    XCTAssertFalse(viewModel.canSeek)  // No seeking during ads
    XCTAssertTrue(viewModel.canSkip)   // If ad is skippable
}
```

### Preview Testing

Use SwiftUI previews for visual testing:

```swift
#Preview("Loading State") {
    AVIMAPlayerView(video: .samples[0])
        // Previews show loading state initially
}

#Preview("Playing State") {
    let viewModel = AVIMAPlayerViewModel()
    // Configure viewModel to simulate playing state
    return AVIMAPlayerView(video: .samples[0], viewModel: viewModel)
}
```

---

## Error Handling

### Closed Loop Error Pattern

All errors are exposed via `@Published` properties:

```swift
@Published private(set) var playbackError: Error?
@Published private(set) var mainVideoState: PlayerState = .idle
@Published private(set) var adState: PlayerState = .idle
```

### Error Types

```swift
enum PlayerError: LocalizedError {
    case invalidAdTagURL
    case adLoadFailed(String)
    case videoLoadFailed(String)

    var errorDescription: String? { ... }
}
```

### Error Recovery

The View provides retry capability:

```swift
errorView(error: error)
    // Shows:
    // - Error icon
    // - Error message
    // - Retry button
```

**Fallback Strategy:**
- Ad load fails → Skip to main video
- Main video fails → Show error with retry
- Network errors → Retry with exponential backoff (future)

---

## Performance Considerations

### Memory Management

1. **Time Observers:**
   - Properly removed in `cleanup()`
   - Weak self captures prevent retain cycles

2. **Player Cleanup:**
   - Both players released on `onDisappear()`
   - IMA resources destroyed properly

3. **Combine Cancellables:**
   - Stored in Set for automatic cleanup
   - Cleared on deinit

### Threading

- `@MainActor` on ViewModel ensures UI updates on main thread
- IMA callbacks dispatched to main queue
- No race conditions in state updates

### Buffering Strategy

- Main video begins buffering on `loadVideo()`
- Continues buffering during ad playback
- Ready to resume instantly when ads complete

---

## Future Enhancements

### Planned Features

1. **Analytics Integration**
   - Track ad impressions
   - Monitor completion rates
   - Measure engagement

2. **Advanced Ad Features**
   - Companion ads
   - Click-through handling
   - VPAID support

3. **Picture-in-Picture**
   - PiP support for main video
   - Ad restrictions in PiP mode

4. **Offline Support**
   - Cached video playback
   - Ad substitution for offline

5. **Accessibility**
   - VoiceOver support
   - Closed captions
   - Audio descriptions

---

## Troubleshooting

### Common Issues

**Issue:** Ads don't play
- **Check:** Ad tag URL is valid
- **Check:** IMA SDK is properly initialized
- **Check:** Network connectivity
- **Solution:** Check logs for IMA error messages

**Issue:** Main video doesn't resume after ad
- **Check:** `adsManagerDidRequestContentResume` delegate called
- **Check:** `switchToMainVideoMode()` updates state correctly
- **Solution:** Verify mode transition logic

**Issue:** Controls don't respond
- **Check:** `@Published` properties updating
- **Check:** View observing correct ViewModel
- **Solution:** Use View debugger to inspect state

### Debug Logging

Enable verbose logging:

```swift
// Add to ViewModel
private func log(_ message: String) {
    #if DEBUG
    debugPrint("🎬 IMAPlayer: \(message)")
    #endif
}
```

---

## Code Quality Checklist

Following CLAUDE.md standards:

### Closed Loops
- [x] All state changes update `@Published` properties
- [x] View can observe all state changes
- [x] No silent failures or console-only errors
- [x] User receives feedback for all actions

### Code Quality
- [x] `@MainActor` on ViewModels
- [x] LoadResult for async state
- [x] Computed properties for derived state
- [x] Guard clauses prevent duplicate operations
- [x] Function names describe actions (not UI events)
- [x] Private helpers marked private
- [x] Complete code paths with return values
- [x] Resilient error handling

### Documentation
- [x] Comprehensive file headers
- [x] Public API documented
- [x] Complex logic explained
- [x] Usage examples provided

---

## References

- **CLAUDE.md**: Project coding standards
- **Google IMA SDK**: [IMA iOS SDK Guide](https://developers.google.com/interactive-media-ads/docs/sdks/ios/client-side)
- **Brightcove SDK**: [Brightcove Native Player SDK](https://github.com/brightcove/brightcove-player-sdk-ios)
- **Apple AVFoundation**: [AVPlayer Documentation](https://developer.apple.com/documentation/avfoundation/avplayer)

---

**Last Updated:** 2026-01-25
**Author:** Generated following CLAUDE.md standards
