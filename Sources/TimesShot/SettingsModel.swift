import AppKit
import AuthenticationServices
import Observation
import OSLog
import ServiceManagement
import TimesShotCore

@MainActor @Observable
final class SettingsModel {
    private static let logger = Logger(subsystem: "jp.sendocorp.TimesShot", category: "OAuth")
    let app: AppModel
    var checkingConnection = false
    var connectionError: String?
    var generalError: String?
    var loadingChannels = false
    var channelError: String?
    var channelSearch = "" { didSet { filterChannels() } }
    private(set) var availableChannels: [SlackChannel] = []
    private(set) var filteredChannels: [SlackChannel] = []
    var launchAtLogin = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    @ObservationIgnored private let client: SlackClient
    @ObservationIgnored private let authenticate: @MainActor (URL, NSWindow) async throws -> URL
    @ObservationIgnored private let applyShortcut: (Configuration) throws -> Void
    @ObservationIgnored private var loadedConnectionID: UUID?
    @ObservationIgnored private var channelRequestID: UUID?

    init(app: AppModel, applyShortcut: @escaping (Configuration) throws -> Void,
         client: SlackClient = SlackClient(),
         authenticate: (@MainActor (URL, NSWindow) async throws -> URL)? = nil) {
        self.app = app
        self.applyShortcut = applyShortcut
        self.client = client
        self.authenticate = authenticate ?? SlackWebAuthentication().authenticate
    }

    func connect(window: NSWindow?) async {
        guard !checkingConnection else { return }
        guard let window, !app.connection.clientID.isEmpty else {
            connectionError = "このバージョンはSlackへの接続を開始できません。"
            return
        }
        guard app.queue.count == 0, !app.importing else {
            connectionError = "送信と画像の読み込みが完了してから、Slackに接続してください。"
            return
        }
        checkingConnection = true
        connectionError = nil
        defer { checkingConnection = false }
        var stage = "browser"
        do {
            let authorization = try SlackAuthorization()
            Self.logger.notice("Connection started")
            let callback = try await authenticate(authorization.url(clientID: app.connection.clientID), window)
            stage = "callback"
            Self.logger.notice("Browser returned a callback")
            let code = try authorization.code(from: callback)
            stage = "token_exchange"
            Self.logger.notice("Callback validated; exchanging authorization code")
            let credentials = try await client.authorize(code: code, verifier: authorization.verifier, clientID: app.connection.clientID)
            stage = "save_connection"
            Self.logger.notice("Slack credentials verified")
            try app.connect(credentials)
            Self.logger.notice("Connection saved")
            await reloadChannels()
        } catch {
            let nsError = error as NSError
            Self.logger.error("Connection failed: stage=\(stage, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
            if nsError.domain == ASWebAuthenticationSessionErrorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                connectionError = "Slackへの接続がキャンセルされました。許可後に画面が閉じた場合は、もう一度接続してください。"
            } else {
                connectionError = error.localizedDescription
            }
        }
    }

    func disconnect() {
        do {
            try app.disconnect()
            availableChannels = []
            loadedConnectionID = nil
            channelRequestID = nil
            loadingChannels = false
            filterChannels()
            connectionError = nil
            channelError = nil
        } catch { connectionError = error.localizedDescription }
    }

    func reloadChannels() async {
        guard let connectionID = app.connection.credentials?.connectionID else {
            availableChannels = []
            loadedConnectionID = nil
            channelRequestID = nil
            loadingChannels = false
            filterChannels()
            return
        }
        let requestID = UUID()
        channelRequestID = requestID
        loadingChannels = true
        channelError = nil
        availableChannels = []
        loadedConnectionID = nil
        filterChannels()
        defer { if channelRequestID == requestID { loadingChannels = false } }
        do {
            let token = try await app.connection.accessToken(for: connectionID)
            let channels = try await client.channels(token: token)
            try Task.checkCancellation()
            guard app.connection.credentials?.connectionID == connectionID, channelRequestID == requestID else { return }
            availableChannels = channels
            loadedConnectionID = connectionID
            filterChannels()
        } catch {
            guard app.connection.credentials?.connectionID == connectionID, channelRequestID == requestID, !Task.isCancelled else { return }
            if case SlackAuthorizationError.reconnect = error { app.connection.markForReconnect(connectionID: connectionID) }
            channelError = error.localizedDescription
        }
    }

    private func filterChannels() {
        let search = channelSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredChannels = availableChannels.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
    }

    func addChannel(_ channel: SlackChannel) {
        do {
            guard loadedConnectionID == app.connection.credentials?.connectionID, loadedConnectionID != nil,
                  availableChannels.contains(channel), !app.connection.requiresReconnect else {
                throw StorageError.message("チャンネル一覧を再取得してください。")
            }
            let id = app.configuration.channels.isEmpty ? Configuration.defaultDestinationID : UUID().uuidString
            try saveChannel(PostingChannel(id: id, channelID: channel.id, name: channel.name))
            channelError = nil
        } catch { channelError = error.localizedDescription }
    }

    func setShortcut(_ shortcut: RecordedShortcut) {
        let previous = app.configuration
        var proposed = previous
        proposed.keyCode = shortcut.keyCode
        proposed.modifiers = shortcut.modifiers
        proposed.shortcutLabel = shortcut.label
        do {
            try applyShortcut(proposed)
            do { try app.updateConfiguration(proposed) }
            catch { try? applyShortcut(previous); throw error }
            generalError = nil
        } catch { generalError = error.localizedDescription }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled, SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            app.defaults.set(true, forKey: "loginPreferenceChosen")
            launchAtLogin = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
            generalError = SMAppService.mainApp.status == .requiresApproval ? "自動起動はシステム設定で許可してください。" : nil
        } catch { generalError = error.localizedDescription }
    }

    func saveChannel(_ channel: PostingChannel) throws {
        var proposed = app.configuration
        if channel.id == Configuration.defaultDestinationID {
            proposed.channelID = channel.channelID
            proposed.channelName = channel.name
        } else if let index = proposed.additionalChannels.firstIndex(where: { $0.id == channel.id }) {
            proposed.additionalChannels[index] = channel
        } else {
            proposed.additionalChannels.append(channel)
        }
        guard !channel.channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StorageError.message("投稿先のチャンネルを選択してください。")
        }
        try proposed.validateChannels()
        try app.updateConfiguration(proposed)
    }

    func removeChannel(_ id: String) throws {
        var proposed = app.configuration
        proposed.removeChannel(id)
        try app.updateConfiguration(proposed)
    }
}
