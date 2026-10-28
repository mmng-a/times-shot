import AppKit
import Observation
import TimesShotCore
import UserNotifications

@MainActor @Observable
final class AppModel {
    var configuration = Configuration.load()
    var draft = Draft()
    var importing = false
    var latestError: String?
    var queue: PostingQueue!
    @ObservationIgnored let storage: DraftStorage
    @ObservationIgnored var onAccepted: (() -> Void)?
    @ObservationIgnored var onStatusChange: (() -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var lastStorageError: String?
    @ObservationIgnored var token = ""

    init(storage: DraftStorage) {
        self.storage = storage
        do {
            draft = try storage.load()
            try storage.removeOrphans(keeping: draft.images)
        } catch { latestError = error.localizedDescription }
        do { token = try TokenStore.read() } catch { latestError = error.localizedDescription }
        let client = SlackClient()
        queue = PostingQueue(send: { post in
            try await client.send(post)
            // Slack's per-channel posting limit is one message per second; this is spacing, not a retry.
            try await Task.sleep(for: .seconds(1))
        }, completed: { [weak self] post, error in
            guard let self else { return }
            if let error { self.notifyFailure(post.draft, error: error) }
            self.storage.remove(post.draft.images)
            self.onStatusChange?()
        })
    }

    var isReady: Bool { configuration.isConfigured && token.hasPrefix("xoxp-") }
    var canSend: Bool { !draft.isEmpty && !importing && isReady }

    func changed() {
        saveTask?.cancel()
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            saveDraft()
        }
    }

    @discardableResult
    func saveDraft() -> Bool {
        saveTask?.cancel()
        do {
            try storage.save(draft)
            lastStorageError = nil
            return true
        } catch {
            if lastStorageError != error.localizedDescription {
                lastStorageError = error.localizedDescription
                notify(title: "下書きを保存できませんでした", body: error.localizedDescription)
            }
            return false
        }
    }

    func discardDraft() {
        cancelImport()
        let images = draft.images
        draft = Draft()
        if saveDraft() { storage.remove(images) }
    }

    func send() {
        guard canSend else { return }
        let submitted = draft
        draft = Draft()
        guard saveDraft() else { draft = submitted; return }
        queue.enqueue(PendingPost(draft: submitted, channelID: configuration.channelID, token: token))
        onStatusChange?()
        onAccepted?()
    }

    func addFiles(_ urls: [URL]) {
        importImages { storage in
            var images: [ImageAttachment] = []
            do {
                for url in urls {
                    try Task.checkCancellation()
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    images.append(try storage.importImage(data: Data(contentsOf: url, options: .mappedIfSafe), filename: url.lastPathComponent))
                }
                return images
            } catch { storage.remove(images); throw error }
        }
    }

    func addImage(data: Data, filename: String) {
        importImages { storage in [try storage.importImage(data: data, filename: filename)] }
    }

    private func importImages(_ operation: @escaping @Sendable (DraftStorage) throws -> [ImageAttachment]) {
        guard !importing else {
            notify(title: "画像を読み込み中です", body: "読み込みが終わってから追加してください。")
            return
        }
        importing = true
        let storage = storage
        importTask = Task {
            do {
                let images = try await Task.detached(priority: .userInitiated) { try operation(storage) }.value
                if Task.isCancelled { storage.remove(images); return }
                draft.images.append(contentsOf: images)
                saveDraft()
            } catch {
                if !Task.isCancelled { notify(title: "画像を添付できませんでした", body: error.localizedDescription) }
            }
            guard !Task.isCancelled else { return }
            importing = false
            importTask = nil
        }
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        importing = false
    }

    func removeImage(_ image: ImageAttachment) {
        draft.images.removeAll { $0.id == image.id }
        if saveDraft() { storage.remove([image]) }
    }

    func notifyFailure(_ draft: Draft, error: Error) {
        let unknown: Bool
        if case DeliveryError.unknown = error { unknown = true } else { unknown = false }
        notify(title: unknown ? "timesへの投稿結果を確認できませんでした" : "timesへの投稿に失敗しました",
               body: draft.notificationSummary + "\n" + error.localizedDescription)
    }

    func notify(title: String, body: String) {
        latestError = title + "\n" + body
        onStatusChange?()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
