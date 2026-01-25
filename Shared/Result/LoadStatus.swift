import Foundation

/// The state of a data load.
///
/// - loading: A load is in progress.
/// - error: An error occurred when loading.
/// - success: a load has completed
/// - notStarted: No load is in progress. This represents both "a load has not started."
public enum LoadStatus: Equatable {
    case loading
    case error(_ error: Error)
    case success
    case notStarted

    public var active: Bool {
        switch self {
        case .loading:
            true
        default:
            false
        }
    }

    public var started: Bool {
        switch self {
        case .notStarted:
            false
        default:
            true
        }
    }

    public var complete: Bool {
        switch self {
        case .success:
            true
        default:
            false
        }
    }

    public var error: Error? {
        switch self {
        case let .error(error):
            error
        default:
            nil
        }
    }
}

public func == (lhs: LoadStatus, rhs: LoadStatus) -> Bool {
    switch (lhs, rhs) {
    case (.loading, .loading),
         (.notStarted, .notStarted),
         (.error, .error),
         (.success, .success):
        true
    default:
        false
    }
}

func != (lhs: LoadStatus, rhs: LoadStatus) -> Bool {
    !(lhs == rhs)
}
