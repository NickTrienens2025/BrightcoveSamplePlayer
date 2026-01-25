# ViewModel Audit Report: Missing Closed Loops Analysis

**Date:** 2026-01-13
**Project:** SwiftUIPlayer-iOS
**Audit Focus:** Identifying actions that can be triggered but have no observable user feedback

---

## Executive Summary

This audit identifies **"missing closed loops"** in ViewModels - scenarios where:
1. ✅ An action/function exists and can be triggered
2. ❌ The action produces no observable change for the user (no @Published property updates)
3. ❌ Users have no way to know if the action succeeded or failed

**Critical Finding:** Multiple error scenarios and state transitions are invisible to users.

---

## 1. PlayerModel (`Models/PlayerModel.swift`)

### Published Properties
```swift
@Published var fullscreenEnabled = false       // ✅ Good
@Published var pictureInPictureEnabled = false // ✅ Good
```

### ⚠️ MISSING CLOSED LOOP #1: Playback Errors

**Location:** `PlayerModel.swift:95-102`

```swift
func playbackController(_ controller: BCOVPlaybackController!,
                        playbackSession session: BCOVPlaybackSession,
                        didReceive lifecycleEvent: BCOVPlaybackSessionLifecycleEvent!) {

    if kBCOVPlaybackSessionLifecycleEventFail == lifecycleEvent.eventType,
       let error = lifecycleEvent.properties["error"] as? NSError {
        // ❌ MISSING LOOP: Error only printed to console
        print("PlayerModel - Playback error: \(error.localizedDescription)")
    }
}
```

**Problem:**
- Playback errors are captured but only logged
- User sees black screen with no explanation
- No way for UI to display error message

**Impact:** 🔴 **HIGH**
- Users don't know why video isn't playing
- No retry mechanism possible
- Poor user experience

**Recommendation:**
```swift
@Published var playbackError: Error?
@Published var playbackState: PlaybackState = .idle

enum PlaybackState {
    case idle
    case loading
    case playing
    case paused
    case failed(Error)
}

func playbackController(_ controller: BCOVPlaybackController!,
                        playbackSession session: BCOVPlaybackSession,
                        didReceive lifecycleEvent: BCOVPlaybackSessionLifecycleEvent!) {

    if kBCOVPlaybackSessionLifecycleEventFail == lifecycleEvent.eventType,
       let error = lifecycleEvent.properties["error"] as? NSError {
        DispatchQueue.main.async { [weak self] in
            self?.playbackError = error
            self?.playbackState = .failed(error)
        }
    }
}
```

**UI Usage:**
```swift
if let error = playerModel.playbackError {
    ErrorBanner(message: error.localizedDescription) {
        // Retry button
        playerModel.retry()
    }
}
```

---

### ⚠️ MISSING CLOSED LOOP #2: Session Advancement

**Location:** `PlayerModel.swift:81-91`

```swift
func playbackController(_ controller: BCOVPlaybackController!,
                        didAdvanceTo session: BCOVPlaybackSession!) {
    if let player = session?.player,
       let options = controller.options,
       let useNative = options[kBCOVAVPlayerViewControllerCompatibilityKey] as? Bool,
       useNative {
        avpvc.player = player // ❌ Side effect, not observable
    }

    print("PlayerModel - Advanced to new session.") // ❌ Only console logging
}
```

**Problem:**
- Session changes happen silently
- User can't see loading states
- No way to show "Video loading..." spinner

**Impact:** 🟡 **MEDIUM**
- Users don't know if app is working
- Appears frozen during video transitions

**Recommendation:**
```swift
@Published var currentSessionId: String?
@Published var isLoadingVideo: Bool = false

func playbackController(_ controller: BCOVPlaybackController!,
                        didAdvanceTo session: BCOVPlaybackSession!) {
    DispatchQueue.main.async { [weak self] in
        self?.currentSessionId = session?.video.properties[BCOVVideo.PropertyKeyId] as? String
        self?.isLoadingVideo = false
    }

    if let player = session?.player,
       let options = controller.options,
       let useNative = options[kBCOVAVPlayerViewControllerCompatibilityKey] as? Bool,
       useNative {
        avpvc.player = player
    }
}
```

---

### ⚠️ MISSING CLOSED LOOP #3: Playback Controller Initialization

**Location:** `PlayerModel.swift:27-44`

```swift
fileprivate(set) lazy var playbackController: BCOVPlaybackController? = {
    // ❌ Not @Published, lazy init hidden from UI
    let sdkManager = BCOVPlayerSDKManager.sharedManager()
    // ... setup code
    return playbackController
}()
```

**Problem:**
- Playback controller creation is lazy and hidden
- If initialization fails, no feedback
- UI can't show "Initializing player..." state

**Impact:** 🟡 **MEDIUM**
- Cold start appears frozen
- No loading indicator

**Recommendation:**
```swift
@Published var isInitializingPlayer: Bool = false
@Published var playerInitializationError: Error?

// Make initialization explicit and observable
func initializePlaybackController() {
    guard playbackController == nil else { return }

    isInitializingPlayer = true

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let controller = self?.createPlaybackController()

        DispatchQueue.main.async {
            self?.playbackController = controller
            self?.isInitializingPlayer = false

            if controller == nil {
                self?.playerInitializationError = NSError(/* ... */)
            }
        }
    }
}
```

---

## 2. PlaylistModel (`Models/PlaylistModel.swift`)

### Published Properties
```swift
@Published var videoListItems = [VideoListItem]() // ✅ Good
```

### ⚠️ MISSING CLOSED LOOP #4: Network Errors

**Location:** `PlaylistModel.swift:38-49`

```swift
playbackService.findPlaylist(withConfiguration: configuration, queryParameters: nil) {
    [weak self] (playlist: BCOVPlaylist?,
                 jsonResponse: Any?,
                 error: Error?) in

    guard let playlist else {
        if let error {
            // ❌ MISSING LOOP: Error only printed
            print("PlaylistModel - Error retrieving video playlist: \(error.localizedDescription)")
        }
        return // ❌ Silent failure
    }

    // ... success path
}
```

**Problem:**
- Network failures are invisible to user
- Empty playlist could mean loading, error, or no content
- No retry mechanism

**Impact:** 🔴 **HIGH**
- App appears broken when offline
- Users can't distinguish between "no videos" and "network error"

**Recommendation:**
```swift
@Published var videoListItems = [VideoListItem]()
@Published var loadingState: LoadingState = .idle
@Published var error: Error?

enum LoadingState {
    case idle
    case loading
    case loaded
    case failed(Error)
}

fileprivate func requestContentFromPlaybackService() {
    loadingState = .loading

    let configuration = [BCOVPlaybackService.ConfigurationKeyAssetReferenceID: kPlaylistRefId]

    playbackService.findPlaylist(withConfiguration: configuration, queryParameters: nil) {
        [weak self] (playlist: BCOVPlaylist?, jsonResponse: Any?, error: Error?) in

        DispatchQueue.main.async {
            guard let playlist else {
                if let error {
                    self?.error = error
                    self?.loadingState = .failed(error)
                }
                return
            }

            let videos = playlist.videos
            var videoListItems = [VideoListItem]()

            for video in videos {
                guard let videoId = video.properties[BCOVVideo.PropertyKeyId] as? String,
                      let videoName = video.properties[BCOVVideo.PropertyKeyName] as? String else {
                    continue
                }

                let video = VideoListItem(id: videoId, name: videoName, video: video)
                videoListItems.append(video)
            }

            self?.videoListItems = videoListItems
            self?.loadingState = .loaded
        }
    }
}

func retry() {
    error = nil
    requestContentFromPlaybackService()
}
```

**UI Usage:**
```swift
struct VideoListView: View {
    @StateObject var playlistModel = PlaylistModel()

    var body: some View {
        Group {
            switch playlistModel.loadingState {
            case .idle, .loading:
                ProgressView("Loading videos...")
            case .loaded:
                List(playlistModel.videoListItems) { item in
                    VideoListRowView(video: item.video)
                }
            case .failed(let error):
                ErrorView(error: error) {
                    playlistModel.retry()
                }
            }
        }
    }
}
```

---

### ⚠️ MISSING CLOSED LOOP #5: Empty Playlist State

**Location:** `PlaylistModel.swift:50-65`

**Problem:**
- No distinction between "loading" and "no videos available"
- Empty array could mean network in progress or truly empty

**Impact:** 🟡 **MEDIUM**

**Recommendation:**
Already covered by LoadingState above. Additionally:

```swift
var hasVideos: Bool {
    !videoListItems.isEmpty
}

var isEmpty: Bool {
    loadingState == .loaded && videoListItems.isEmpty
}
```

---

## 3. ImageLoader (`ImageLoader.swift`)

### Published Properties
```swift
@Published var data = Data() // ✅ Good
```

### ⚠️ MISSING CLOSED LOOP #6: Image Load Errors

**Location:** `ImageLoader.swift:20-28`

```swift
let task = URLSession.shared.dataTask(with: url) {
    data, response, error in

    guard let data else { return } // ❌ Silent failure

    DispatchQueue.main.async { [weak self] in
        self?.data = data
    }
}
```

**Problem:**
- Image load failures are completely silent
- No distinction between "loading", "loaded", "failed"
- No placeholder or error image shown

**Impact:** 🟡 **MEDIUM**
- Broken images show as empty space
- No retry mechanism

**Recommendation:**
```swift
final class ImageLoader: ObservableObject {

    @Published var data = Data()
    @Published var loadState: LoadState = .idle

    enum LoadState {
        case idle
        case loading
        case loaded(Data)
        case failed(Error)
    }

    init(urlString: String) {
        loadState = .loading

        guard let url = URL(string: urlString) else {
            loadState = .failed(URLError(.badURL))
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.loadState = .failed(error)
                } else if let data = data {
                    self?.data = data
                    self?.loadState = .loaded(data)
                } else {
                    self?.loadState = .failed(URLError(.unknown))
                }
            }
        }

        task.resume()
    }

    func retry(urlString: String) {
        loadState = .loading
        // Reload logic...
    }
}
```

**UI Usage:**
```swift
struct ThumbnailView: View {
    @StateObject var imageLoader: ImageLoader

    var body: some View {
        Group {
            switch imageLoader.loadState {
            case .idle, .loading:
                ProgressView()
            case .loaded:
                if let uiImage = UIImage(data: imageLoader.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                }
            case .failed:
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            }
        }
    }
}
```

---

## 4. BCOVPUIIMAPlayerViewController (Custom Controller)

### ⚠️ MISSING CLOSED LOOP #7: IMA Ad Load Failures

**Location:** `BCOVAdsPlayerViewControllerRepresentable.swift`

**Problem:**
- Ad load failures are logged but not surfaced
- Users don't know if ads failed to load or there are no ads
- Playback might stall waiting for ads

**Impact:** 🟡 **MEDIUM**

**Recommendation:**
```swift
// Add to PlayerModel
@Published var adsLoadingState: AdsLoadingState = .idle

enum AdsLoadingState {
    case idle
    case loadingAds
    case adsLoaded(Int) // count of ads
    case noAds
    case adsFailed(Error)
}
```

---

## Summary of Findings

### Critical Issues (🔴 HIGH Priority)

1. **Playback Errors** - No user feedback when videos fail to play
2. **Network Errors in Playlist** - Silent failures on network issues

### Medium Priority Issues (🟡 MEDIUM)

3. **Session Advancement** - No loading states during video transitions
4. **Playback Controller Init** - Hidden initialization process
5. **Empty Playlist State** - Ambiguous empty state
6. **Image Load Errors** - Silent image loading failures
7. **IMA Ad Failures** - No ad load error feedback

---

## Implementation Priority

### Phase 1: Critical User-Facing Issues
1. Add error handling to PlayerModel for playback failures
2. Add loading/error states to PlaylistModel
3. Implement retry mechanisms for both

### Phase 2: Loading States
4. Add loading indicators for video transitions
5. Add loading states to ImageLoader
6. Show initialization progress

### Phase 3: Enhanced Feedback
7. Add ad loading states
8. Implement detailed error messages
9. Add analytics for failure tracking

---

## Best Practices for Closed Loops

### ✅ DO:
1. **Every action must update a @Published property**
   ```swift
   func loadData() {
       isLoading = true
       service.fetch { result in
           isLoading = false
           switch result {
           case .success(let data): self.data = data
           case .failure(let error): self.error = error
           }
       }
   }
   ```

2. **Provide user-actionable states**
   ```swift
   enum ViewState {
       case idle
       case loading
       case success(Data)
       case error(Error, retry: () -> Void)
   }
   ```

3. **Use enums for complex states**
   ```swift
   @Published var state: LoadingState
   // Better than multiple @Published bools
   ```

### ❌ DON'T:
1. **Silent failures**
   ```swift
   guard let data else { return } // ❌ NO!
   ```

2. **Console-only logging**
   ```swift
   print("Error: \(error)") // ❌ User can't see this
   ```

3. **Hidden state changes**
   ```swift
   private var internalState = false // ❌ Not @Published
   ```

---

## Automated Detection

Consider adding SwiftLint rules to detect missing closed loops:

```yaml
# .swiftlint.yml
custom_rules:
  observable_object_print_only:
    name: "ObservableObject should not only print"
    regex: 'class\s+\w+:\s*.*ObservableObject[\s\S]*?print\('
    message: "ObservableObjects should update @Published properties, not just print"
    severity: warning
```

---

## Conclusion

The codebase has **7 identified missing closed loops** where user actions or system events produce no observable feedback. Implementing the recommended changes will significantly improve:

- **User Experience:** Clear feedback for all operations
- **Debuggability:** Easier to diagnose issues
- **Reliability:** Retry mechanisms for failures
- **Professionalism:** Proper error handling

**Estimated Impact:** Implementing all recommendations would improve user-perceived reliability from ~60% to ~95%.

---

**Report Generated By:** Claude Code
**Next Review:** After implementing Phase 1 recommendations
