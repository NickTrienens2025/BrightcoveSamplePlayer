import Foundation

public extension LoadResult {
    static func tracked(_ work: @escaping () async throws -> T, skipLoading: Bool = false) -> AsyncStream<LoadResult<T>> {
        let stream = AsyncStream(LoadResult<T>.self) { continuation in
            Task {
                if !skipLoading {
                    continuation.yield(LoadResult<T>.loading)
                }

                do {
                    try await continuation.yield(LoadResult<T>.success(work()))
                    continuation.finish()
                } catch {
                    continuation.yield(LoadResult<T>.error(error))
                    continuation.finish()
                }
            }
        }

        return stream
    }
}

public extension LoadStatus {
    static func tracked(_ work: @escaping () async throws -> some Any, skipLoading: Bool = false) async throws -> AsyncStream<LoadStatus> {
        let stream = AsyncStream(LoadStatus.self) { continuation in
            Task {
                if !skipLoading {
                    continuation.yield(LoadStatus.loading)
                }

                do {
                    _ = try await work()
                    continuation.yield(LoadStatus.success)
                    continuation.finish()
                } catch {
                    continuation.yield(LoadStatus.error(error))
                    continuation.finish()
                }
            }
        }

        return stream
    }
}
