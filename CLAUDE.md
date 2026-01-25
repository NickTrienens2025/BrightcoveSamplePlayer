# SwiftUIPlayer Project Guide

This document contains important patterns and practices for this codebase.

---

## Open vs. Closed Loops in ViewModels

### What is a "Closed Loop"?

A **closed loop** is when user actions or system events have complete, observable feedback:

1. ✅ **Action triggered** (function called)
2. ✅ **Business logic executes** (work happens)
3. ✅ **@Published property updated** (state changes)
4. ✅ **UI reflects the change** (user sees feedback)

An **open loop** (missing loop) occurs when steps 3-4 are missing - the action happens but the user gets no feedback.

---

### Example: Open Loop (❌ Bad)

```swift
class PlayerModel: ObservableObject {
    // No @Published property for errors

    func playbackController(_ controller: BCOVPlaybackController!,
                            playbackSession session: BCOVPlaybackSession,
                            didReceive lifecycleEvent: BCOVPlaybackSessionLifecycleEvent!) {

        if lifecycleEvent.eventType == .fail, let error = ... {
            print("Error: \(error)") // ❌ Only console, user can't see
        }
    }
}
```

**Problem:** The error happens, gets logged, but the user sees a black screen with no explanation.

**User Experience:**
- 😕 User taps video
- ⏳ Black screen appears
- 🤷 Nothing happens
- 😠 User gives up

---

### Example: Closed Loop (✅ Good)

```swift
class PlayerModel: ObservableObject {
    @Published var playbackError: Error? // ✅ Observable state

    func playbackController(_ controller: BCOVPlaybackController!,
                            playbackSession session: BCOVPlaybackSession,
                            didReceive lifecycleEvent: BCOVPlaybackSessionLifecycleEvent!) {

        if lifecycleEvent.eventType == .fail, let error = ... {
            DispatchQueue.main.async { [weak self] in
                self?.playbackError = error // ✅ Update observable state
            }
        }
    }
}
```

**UI Usage:**
```swift
struct VideoDetailView: View {
    @ObservedObject var playerModel: PlayerModel

    var body: some View {
        ZStack {
            PlayerView()

            // ✅ User sees the error
            if let error = playerModel.playbackError {
                ErrorBanner(message: error.localizedDescription) {
                    // ✅ User can retry
                    playerModel.retry()
                }
            }
        }
    }
}
```

**User Experience:**
- 😊 User taps video
- ⏳ Loading indicator appears
- ⚠️ Error banner shows: "Video failed to load"
- 🔄 User taps "Retry" button
- ✅ Video plays successfully

---

## Common Missing Loops in This Project

See [VIEWMODEL-AUDIT-REPORT.md](./VIEWMODEL-AUDIT-REPORT.md) for a complete analysis of missing closed loops in the codebase.

### Quick Reference

| ViewModel | Missing Loop | Fix |
|-----------|-------------|-----|
| `PlayerModel` | Playback errors | Add `@Published var playbackError: Error?` |
| `PlayerModel` | Loading state | Add `@Published var isLoadingVideo: Bool` |
| `PlaylistModel` | Network errors | Add `@Published var loadingState: LoadingState` |
| `ImageLoader` | Image load failures | Add `@Published var loadState: LoadState` |

---

## Best Practices for Closed Loops

### ✅ DO: Always Update @Published Properties

```swift
class MyViewModel: ObservableObject {
    @Published var state: LoadingState = .idle

    enum LoadingState {
        case idle
        case loading
        case success(Data)
        case failure(Error)
    }

    func loadData() {
        state = .loading // ✅ User sees loading

        service.fetch { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    self?.state = .success(data) // ✅ User sees data
                case .failure(let error):
                    self?.state = .failure(error) // ✅ User sees error
                }
            }
        }
    }
}
```

### ❌ DON'T: Silent Failures

```swift
func loadData() {
    service.fetch { result in
        guard case .success(let data) = result else {
            return // ❌ User gets no feedback
        }
        self.data = data
    }
}
```

### ❌ DON'T: Console-Only Logging

```swift
func loadData() {
    service.fetch { result in
        if case .failure(let error) = result {
            print("Error: \(error)") // ❌ User can't see console
        }
    }
}
```

---

## Testing Closed Loops

When testing ViewModels, verify the complete loop:

```swift
func testPlaybackError() {
    let viewModel = PlayerModel()

    // 1. Trigger action
    viewModel.simulatePlaybackError()

    // 2. Verify state updated
    XCTAssertNotNil(viewModel.playbackError) // ✅ Loop is closed

    // 3. Verify user can recover
    viewModel.retry()
    XCTAssertNil(viewModel.playbackError) // ✅ Loop resets
}
```

---

## Why Closed Loops Matter

### User Trust
- Users trust apps that provide clear feedback
- Silent failures erode confidence
- Visible errors with retry options build trust

### Debugging
- @Published properties are observable in SwiftUI previews
- State changes are traceable in debugging
- Easier to write unit tests

### Accessibility
- Screen readers can announce state changes
- Users with cognitive disabilities benefit from clear feedback
- Loading states prevent confusion

---

## Quick Audit Checklist

When adding new ViewModel functionality, ask:

- [ ] Does this action update a @Published property?
- [ ] Can users see if the action succeeded?
- [ ] Can users see if the action failed?
- [ ] Can users retry on failure?
- [ ] Does the UI show loading states?
- [ ] Are all async operations main-thread safe?

If you answered "No" to any question, you have an **open loop**.

---

## Additional Resources

- **Full Audit Report:** [VIEWMODEL-AUDIT-REPORT.md](./VIEWMODEL-AUDIT-REPORT.md)
- **SwiftUI State Management:** [Apple Documentation](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- **MVVM Best Practices:** [Swift.org](https://www.swift.org/)

---

**Last Updated:** 2026-01-16
**Maintained By:** Project Team
