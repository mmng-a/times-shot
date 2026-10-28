import Foundation
import Observation

/// Owns a single worker so accepting another post never changes delivery order.
@MainActor @Observable
public final class PostingQueue {
    public private(set) var count = 0
    @ObservationIgnored private var waiting: [PendingPost] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private let send: @Sendable (PendingPost) async throws -> Void
    @ObservationIgnored private let completed: @MainActor (PendingPost, Error?) -> Void

    public init(
        send: @escaping @Sendable (PendingPost) async throws -> Void,
        completed: @escaping @MainActor (PendingPost, Error?) -> Void
    ) {
        self.send = send
        self.completed = completed
    }

    public func enqueue(_ post: PendingPost) {
        waiting.append(post)
        count += 1
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    public func discardAll() {
        worker?.cancel()
        worker = nil
        waiting.removeAll()
        count = 0
    }

    private func drain() async {
        while !waiting.isEmpty, !Task.isCancelled {
            let post = waiting.removeFirst()
            var failure: Error?
            do { try await send(post) } catch { failure = error }
            guard !Task.isCancelled else { return }
            count -= 1
            completed(post, failure)
        }
        worker = nil
    }
}
