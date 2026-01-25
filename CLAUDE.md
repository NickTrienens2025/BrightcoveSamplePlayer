# SwiftUIPlayer Project Guide

This document contains important patterns and practices for this codebase.

---

## Code Quality Standards

### DRY (Don't Repeat Yourself)

Avoid code duplication. Each piece of logic should exist in one place.

**Extract repeated patterns into helpers:**
```swift
// ✅ Good - Reusable helper
private func trackAnalytics(event: String, section: String, itemId: String) {
    AnalyticsService.trackEvent(
        eventName: .itemClick,
        parameters: [
            .clickText: event,
            .clickSection: section,
            .itemId: itemId
        ]
    )
}

func trackItemTap(itemId: String) {
    trackAnalytics(event: "item tap", section: "home", itemId: itemId)
}

// ❌ Bad - Copy-paste duplication
func trackItemTap(itemId: String) {
    AnalyticsService.trackEvent(
        eventName: .itemClick,
        parameters: [.clickText: "item tap", .clickSection: "home", .itemId: itemId]
    )
}
```

**Use computed properties for derived state:**
```swift
// ✅ Good - Single source of truth
var items: [Item] { loadResult.value ?? [] }
var isLoading: Bool { loadResult.active && loadResult.value == nil }
var hasError: Bool { loadResult.error != nil }

// ❌ Bad - Duplicated state that can get out of sync
@Published var items: [Item] = []
@Published var isLoading = false
@Published var hasError = false
```

### Functional Patterns

Prefer functional transformations over imperative loops when processing data.

**Use map, filter, compactMap:**
```swift
// ✅ Good - Functional, declarative
let activeItems = items
    .filter { $0.isActive }
    .sorted { $0.name < $1.name }

let itemNames = items.map { $0.name }

let validValues = values.compactMap { $0.value }  // Removes nils

// ❌ Bad - Imperative mutation
var activeItems: [Item] = []
for item in items {
    if item.isActive {
        activeItems.append(item)
    }
}
activeItems.sort { $0.name < $1.name }
```

**Use guard/early return over nested if-else:**
```swift
// ✅ Good - Flat structure, clear exit points
func processItem(_ item: Item?) -> ItemViewModel? {
    guard let item = item else { return nil }
    guard item.isValid else { return nil }
    guard let name = item.name else { return nil }

    return ItemViewModel(item: item, name: name)
}

// ❌ Bad - Pyramid of doom
func processItem(_ item: Item?) -> ItemViewModel? {
    if let item = item {
        if item.isValid {
            if let name = item.name {
                return ItemViewModel(item: item, name: name)
            }
        }
    }
    return nil
}
```

### Access Control

Apply the principle of least visibility - only expose what consumers actually need.

```swift
// ✅ Good - Clear public API, internals hidden
@MainActor
class ContentViewModel: ObservableObject {
    // MARK: - Published Properties (implicitly internal, needed by View)
    @Published var currentIndex = 0
    @Published var contentData: LoadResult<ContentData> = .notStarted

    // MARK: - Private Properties
    private var autoAdvanceTask: Task<Void, Never>?
    private var hasUserInteracted = false

    // MARK: - Public API (called by View)
    func loadContent(forced: Bool = false) async { ... }
    func refresh() async { ... }
    func onDisappear() { ... }

    // MARK: - Private Implementation
    private func startAutoAdvance() { ... }
    private func stopAutoAdvance() { ... }
    private func trackView() { ... }
}

// ❌ Bad - Everything exposed, unclear what View should call
class ContentViewModel: ObservableObject {
    var autoAdvanceTask: Task<Void, Never>?  // Should be private
    var hasUserInteracted = false            // Should be private

    func startAutoAdvance() { ... }          // Should be private
    func handleChange() { ... }              // Should be private
}
```

**Guidelines:**
- `@Published` properties: Keep internal (default) - View needs to observe them
- Lifecycle methods (`onAppear`, `onDisappear`): Keep internal - called by View
- Action methods (user interactions): Keep internal - called by View
- Helper/implementation methods: Mark `private` - not part of public API
- Properties only used internally: Mark `private`

### Function Naming in ViewModels

Use clear, feature-specific names that describe *what* the action does, not *how* it's triggered.

```swift
// ✅ Good - Names describe the action's purpose
func startPlayback()                          // Clear: starts playback
func loadContentData(forced: Bool = false)    // Clear: loads the data
func skipToEnd()                              // Clear: skips to end

// ❌ Bad - Generic names tied to UI events
func playButtonTapped()                       // Tied to button name
func handleButtonPress()                      // Vague, which button?
func onTap()                                  // Too generic
```

**Naming principles:**
- **Actions:** Use verb phrases describing the outcome: `startPlayback`, `dismissSheet`, `saveChanges`
- **Data loading:** Use `load*`, `fetch*`, or `refresh`: `loadContentData`, `fetchItems`, `refresh`
- **Lifecycle:** Use standard names: `onAppear`, `onDisappear`, `didBecomeActive`
- **Avoid:** UI-specific terms like "tapped", "pressed", "clicked" in method names

---

## SwiftUI Patterns

### ViewModel Pattern with LoadResult

ViewModels use `LoadResult<T>` for async state and direct function calls for actions:

```swift
@MainActor
class FeatureViewModel: ObservableObject {
    // MARK: - State (use LoadResult for async data)
    @Published var loadResult: LoadResult<[Item]> = .notStarted
    @Published var selectedItem: Item?

    // MARK: - Computed State (derive from LoadResult)
    var items: [Item] { loadResult.value ?? [] }
    var isLoading: Bool { loadResult.active && loadResult.value == nil }

    // MARK: - Dependencies
    private let service: SomeService

    // MARK: - Init
    init(service: SomeService = SomeServiceImplementation()) {
        self.service = service
    }

    // MARK: - Fetching
    func fetchItems(forced: Bool = false) async {
        // Skip if already loaded and not forced
        if !forced && loadResult.value != nil { return }
        // Skip if already loading
        guard !loadResult.active else { return }

        loadResult = .loading

        do {
            let items = try await service.fetchItems()
            loadResult = .success(items)
        } catch {
            loadResult = .error(error)
        }
    }

    func refresh() async {
        await fetchItems(forced: true)
    }

    // MARK: - Actions
    func itemTapped(_ item: Item) {
        selectedItem = item
    }

    func didDisappear() {
        // Clear stale data to save memory
        if loadResult.value?.isStale == true {
            loadResult = .notStarted
        }
    }
}
```

### LoadResult Type

The project uses `LoadResult<T>` from Shared utilities for async state:

```swift
public enum LoadResult<T>: Equatable {
    case success(_ value: T)
    case loading
    case error(_ error: Error)
    case notStarted

    var active: Bool    // true when .loading
    var value: T?       // the success value, nil otherwise
    var loaded: Bool    // true when .success
    var error: Error?   // the error, nil otherwise
}
```

**Key Principles:**
- **LoadResult for async state:** Use `LoadResult<T>` instead of separate `isLoading`/`error`/`data` properties
- **Direct function calls:** Use named functions like `fetchItems()`, `refresh()`, `itemTapped(_:)`
- **Guard clauses:** Prevent duplicate fetches with `guard !loadResult.active else { return }`
- **forced parameter:** Use `forced: Bool = false` to allow refresh vs initial load
- **Computed properties:** Derive UI state from `loadResult`

### ViewModel Isolation

Keep business logic isolated in the ViewModel. When a ViewModel needs to react to changes in its own `@Published` properties, use Combine subscriptions inside the ViewModel rather than `.onChange` in the View.

```swift
// ✅ Good - Logic stays in ViewModel, View remains simple
@MainActor
class SlideshowViewModel: ObservableObject {
    @Published var currentIndex = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        // React to index changes internally
        $currentIndex
            .dropFirst()
            .sink { [weak self] newIndex in
                self?.handleIndexChange(newIndex)
            }
            .store(in: &cancellables)
    }

    private func handleIndexChange(_ index: Int) {
        // Analytics, auto-advance logic, etc.
    }
}

// View just binds, no knowledge of tracking logic
TabView(selection: $viewModel.currentIndex) { ... }

// ❌ Bad - View knows about ViewModel internals
TabView(selection: $viewModel.currentIndex) { ... }
    .onChange(of: viewModel.currentIndex) { _, newIndex in
        viewModel.slideDidChange(to: newIndex)  // Leaks implementation detail
    }
```

**Benefits of ViewModel isolation:**
- **Testability:** ViewModel logic can be unit tested without a View
- **Encapsulation:** View doesn't need to know about tracking, timers, etc.
- **Single Responsibility:** View displays state, ViewModel manages state
- **Maintainability:** Changes to logic don't require View changes

### View Pattern (with LoadResult switch)

```swift
struct FeatureView: View {
    @StateObject private var viewModel: FeatureViewModel

    // Use nil default to avoid Swift 6 concurrency error with @MainActor ViewModels
    init(viewModel: FeatureViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? FeatureViewModel())
    }

    var body: some View {
        content
            .task {
                await viewModel.fetchItems()
            }
            .onDisappear {
                viewModel.didDisappear()
            }
            .refreshable {
                await viewModel.refresh()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadResult {
        case .notStarted:
            EmptyView()

        case .loading:
            ProgressView()

        case .error(let error):
            ErrorView(error: error, onRetry: {
                Task { await viewModel.refresh() }
            })

        case .success(let items):
            List(items) { item in
                Button {
                    viewModel.itemTapped(item)
                } label: {
                    ItemRow(item: item)
                }
            }
        }
    }
}
```

### UIViewRepresentable Pattern

**IMPORTANT:** Never create UIKit views as properties on the struct - this causes memory leaks.

```swift
// CORRECT
struct MyUIViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()  // Create here
        context.coordinator.view = view
        return view
    }
}

// WRONG - Memory leak!
struct MyUIViewRepresentable: UIViewRepresentable {
    let view = UIView()  // Never do this
}
```

### @MainActor ViewModel Initialization (Swift 6)

When a ViewModel is marked `@MainActor`, using it as a default parameter value causes a Swift 6 concurrency error because default values are evaluated in a nonisolated context.

**Error:** `Call to main actor-isolated initializer 'init()' in a synchronous nonisolated context`

```swift
// ❌ Bad - Causes Swift 6 concurrency error
init(viewModel: FeatureViewModel = FeatureViewModel()) {
    _viewModel = StateObject(wrappedValue: viewModel)
}

// ✅ Good - Use nil default, create inside init body
init(viewModel: FeatureViewModel? = nil) {
    _viewModel = StateObject(wrappedValue: viewModel ?? FeatureViewModel())
}
```

**Why this works:**
1. `nil` as default doesn't call any initializer (no actor isolation needed)
2. The `??` creates the ViewModel inside the init body
3. The init body inherits `@MainActor` isolation from the View struct

**Apply this pattern to all Views with `@StateObject` and `@MainActor` ViewModels.**

### Task.sleep Duration Syntax

Always use the `for:` parameter with `Duration` types instead of nanoseconds:

```swift
// ❌ Bad - Hard to read, error-prone math
try? await Task.sleep(nanoseconds: UInt64(5.0 * 1_000_000_000))

// ✅ Good - Clear, type-safe duration
try? await Task.sleep(for: .seconds(5))
try? await Task.sleep(for: .milliseconds(500))
try? await Task.sleep(for: .seconds(0.5))
```

### Complete Code Paths

Functions that can succeed or fail should return a result so the View can respond:

```swift
// ❌ Bad - View doesn't know if action succeeded
func start() {
    guard canStart else { return }
    service.start()
}

// View assumes it worked
Button { viewModel.start(); dismiss() }

// ✅ Good - View knows the outcome
@discardableResult
func start() -> Bool {
    guard canStart else { return false }
    service.start()
    return true
}

// View responds to actual result
Button { if viewModel.start() { dismiss() } }
```

---

## Resilient Codable Parsing

API responses can be unreliable - fields may be missing, have unexpected types, or contain malformed data. Use these patterns to ensure parsing never crashes the app.

### Golden Rule: Always Implement Custom Decoding

**All API models MUST implement custom `init(from decoder:)`** - never rely on auto-synthesized Codable for external data.

```swift
// ❌ Bad - Auto-synthesized decoding throws on ANY unexpected data
public struct Item: Decodable {
    public let id: Int
    public let name: String
    public let metadata: Metadata?  // Throws if metadata has unexpected structure
}

// ✅ Good - Custom decoding handles edge cases gracefully
public struct Item: Decodable {
    public let id: Int
    public let name: String
    public let metadata: Metadata?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        metadata = try? container.decodeIfPresent(Metadata.self, forKey: .metadata)  // Malformed metadata = nil, not throw
    }

    enum CodingKeys: String, CodingKey {
        case id, name, metadata
    }
}
```

**Why custom decoding is required:**
- API responses change without warning
- Backend bugs can return unexpected types (`"null"` string vs `null`)
- Third-party APIs are especially unreliable
- Auto-synthesized decoding throws on the first error, losing all data
- Custom decoding lets you decide what's required vs optional

### Pattern: Try-Optional for Individual Fields

Use `try?` for optional fields that shouldn't fail the whole object.

```swift
// ✅ Good - Optional fields use try?, required fields throw
public struct MediaItem: Decodable {
    public let id: Int              // Required - will throw if missing
    public let title: String        // Required
    public let duration: Int?       // Optional - won't crash if missing/malformed
    public let viewCount: Int?      // Optional

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields - throw on failure
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)

        // Optional fields - use try? to convert failures to nil
        duration = try? container.decode(Int.self, forKey: .duration)
        viewCount = try container.decodeIfPresent(Int.self, forKey: .viewCount)
    }
}
```

### Pattern: Default Values for Missing Fields

Use `?? defaultValue` when you need a sensible fallback.

```swift
// ✅ Good - Provides default when field is missing or malformed
public struct VideoConfig: Decodable {
    public let autoplay: Bool
    public let volume: Double
    public let quality: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Default to false if missing/malformed
        autoplay = (try? container.decode(Bool.self, forKey: .autoplay)) ?? false

        // Default to 1.0 if missing/malformed
        volume = (try? container.decode(Double.self, forKey: .volume)) ?? 1.0

        // Default to "auto" if missing/malformed
        quality = (try? container.decode(String.self, forKey: .quality)) ?? "auto"
    }
}
```

### Pattern: Full Model with Resilient Parsing

```swift
// ✅ Good - Every optional field is protected
public struct VideoMetadata: Decodable {
    public let thumbnail: URL?
    public let captions: [Caption]?
    public let relatedVideos: [VideoSummary]?
    public let analytics: AnalyticsInfo?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Every field uses try? - partial data is better than no data
        thumbnail = try? container.decodeIfPresent(URL.self, forKey: .thumbnail)
        captions = try? container.decodeIfPresent([Caption].self, forKey: .captions)
        relatedVideos = try? container.decodeIfPresent([VideoSummary].self, forKey: .relatedVideos)

        // Try-catch for more detailed error logging
        do {
            analytics = try container.decodeIfPresent(AnalyticsInfo.self, forKey: .analytics)
        } catch {
            debugPrint("Analytics decode error: \(error)")
            analytics = nil
        }
    }
}
```

### Quick Reference: When to Use Each Pattern

| Pattern | Use When | Example |
|---------|----------|---------|
| `try container.decode(T.self)` | Field is required, failure should propagate | `id`, `title` |
| `try? container.decode(T.self)` | Field is optional, malformed = nil | Enum that may have unknown cases |
| `try container.decodeIfPresent(T.self)` | Field may be missing from JSON | Optional metadata fields |
| `(try? ...) ?? default` | Need a value even when missing | `autoplay ?? false` |

### Audit Checklist for Codable Models

1. ✅ Does the model implement custom `init(from decoder:)`? (Required for all API models)
2. ✅ Do optional fields use `try?` or `decodeIfPresent`?
3. ✅ Are sensible defaults provided with `?? value`?
4. ✅ Does the model validate it has minimum required data?
5. ✅ Are enums decoded with `try?` in case of unknown values?
6. ✅ Are nested models also using custom decoding?

---

## Open vs. Closed Loops in ViewModels

### What is a "Closed Loop"?

A **closed loop** is when user actions or system events have complete, observable feedback:

1. ✅ **Action triggered** (function called)
2. ✅ **Business logic executes** (work happens)
3. ✅ **@Published property updated** (state changes)
4. ✅ **UI reflects the change** (user sees feedback)
5. ✅ **View actually responds** to the update (UI changes, dismisses, shows error, etc.)

An **open loop** (missing loop) occurs when steps 3-5 are missing - the action happens but the user gets no feedback.

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

### Closed Loop Checklist
- [ ] Does this action update a @Published property?
- [ ] Can users see if the action succeeded?
- [ ] Can users see if the action failed?
- [ ] Can users retry on failure?
- [ ] Does the UI show loading states?
- [ ] Are all async operations main-thread safe?
- [ ] Does the View **actually use** every `@Published` property? (A property nobody reads is still an open loop)

### Code Quality Checklist
- [ ] Does every `catch` block update a `@Published` property?
- [ ] Do actions that can fail return `Bool` or a result type?
- [ ] Are there guard clauses to prevent duplicate fetches?
- [ ] Is the class marked `@MainActor`?
- [ ] Is validation logic in testable computed properties (e.g., `canStart`)?
- [ ] Are helper methods marked `private`?
- [ ] Do function names describe the action, not the UI event (e.g., `startPlayback` not `playButtonTapped`)?

If you answered "No" to any question, you have an **open loop** or code quality issue.

---

## Additional Resources

- **Full Audit Report:** [VIEWMODEL-AUDIT-REPORT.md](./VIEWMODEL-AUDIT-REPORT.md)
- **SwiftUI State Management:** [Apple Documentation](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- **MVVM Best Practices:** [Swift.org](https://www.swift.org/)

---

**Last Updated:** 2026-01-16
**Maintained By:** Project Team
