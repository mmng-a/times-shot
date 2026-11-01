import AppKit
import Observation
import TimesShotCore
import UserNotifications

@MainActor @Observable
final class AppModel {
    var configuration: Configuration
    var draft = Draft()
    var importing = false
    var latestError: String?
    var queue: PostingQueue!
    @ObservationIgnored let storage: DraftStorage
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored var onAccepted: (() -> Void)?
    @ObservationIgnored var onStatusChange: (() -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var lastStorageError: String?
    let connection: SlackConnection

    init(storage: DraftStorage, defaults: UserDefaults = .standard,
         connection: SlackConnection) {
        self.storage = storage
        self.defaults = defaults
        self.connection = connection
        configuration = Configuration.load(defaults: defaults)
        do {
            draft = try storage.load()
            try storage.removeOrphans(keeping: draft.images)
        } catch { latestError = error.localizedDescription }
        let client = SlackClient()
        queue = PostingQueue(send: { post in
            do {
                try await client.send(post, accessToken: { try await connection.accessToken(for: post.connectionID) })
            } catch {
                if case SlackAuthorizationError.reconnect = error { await connection.markForReconnect(connectionID: post.connectionID) }
                throw error
            }
            // Slack's per-channel posting limit is one message per second; this is spacing, not a retry.
            try await Task.sleep(for: .seconds(1))
        }, completed: { [weak self] post, error in
            guard let self else { return }
            if let error { self.notifyFailure(post.draft, error: error) }
            self.storage.remove(post.draft.images)
            self.onStatusChange?()
        })
    }

    var isReady: Bool {
        configuration.isConfigured && connection.credentials != nil && !connection.requiresReconnect
            && configuration.teamID == connection.credentials?.teamID && configuration.userID == connection.credentials?.userID
    }
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

    func selectChannel(_ id: String) {
        guard id != configuration.selectedDestinationID,
              configuration.channels.contains(where: { $0.id == id }), saveDraft() else { return }
        var proposed = configuration
        proposed.selectedDestinationID = id
        do {
            try proposed.save(defaults: defaults)
            configuration = proposed
            onStatusChange?()
        } catch { notify(title: "投稿先を変更できませんでした", body: error.localizedDescription) }
    }

    func updateConfiguration(_ proposed: Configuration) throws {
        try validateConfigurationChange(proposed)
        try proposed.save(defaults: defaults)
        configuration = proposed
        onStatusChange?()
    }

    func validateConfigurationChange(_ proposed: Configuration) throws {
        guard draft.isEmpty || (proposed.selectedChannel?.channelID == configuration.selectedChannel?.channelID
                               && proposed.teamID == configuration.teamID && proposed.userID == configuration.userID) else {
            throw StorageError.message("下書きがあります。送信するか破棄してから、選択中の投稿先やワークスペースを変更してください。")
        }
    }

    func connect(_ credentials: SlackCredentials) throws {
        guard queue.count == 0, !importing else {
            throw StorageError.message("送信と画像の読み込みが完了してから、Slackに接続してください。")
        }
        var proposed = configuration
        let sameAccount = configuration.teamID == credentials.teamID && configuration.userID == credentials.userID
        guard sameAccount || draft.isEmpty else {
            throw StorageError.message("下書きがあります。送信するか破棄してから、Slackの接続先を変更してください。")
        }
        if !sameAccount {
            proposed.channelID = ""
            proposed.channelName = ""
            proposed.additionalChannels = []
            proposed.selectedDestinationID = Configuration.defaultDestinationID
        }
        proposed.teamID = credentials.teamID
        proposed.userID = credentials.userID
        proposed.workspace = credentials.workspace
        proposed.username = credentials.username
        var credentials = credentials
        if let previous = connection.credentials, previous.teamID == credentials.teamID, previous.userID == credentials.userID {
            credentials.connectionID = previous.connectionID
        }
        try connection.replace(credentials)
        try updateConfiguration(proposed)
    }

    func disconnect() throws {
        guard queue.count == 0, !importing else {
            throw StorageError.message("送信と画像の読み込みが完了してから、Slackとの接続を解除してください。")
        }
        try connection.disconnect()
        onStatusChange?()
    }

    func send() {
        guard canSend, let channel = configuration.selectedChannel, let credentials = connection.credentials else { return }
        let submitted = draft
        draft = Draft()
        guard saveDraft() else { draft = submitted; return }
        queue.enqueue(PendingPost(draft: submitted, channelID: channel.channelID, connectionID: credentials.connectionID))
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
        notify(title: unknown ? "Slackへの投稿結果を確認できませんでした" : "Slackへの投稿に失敗しました",
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
