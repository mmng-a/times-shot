import AppKit
import Observation
import ServiceManagement
import TimesShotCore

@MainActor @Observable
final class SettingsModel {
    let app: AppModel
    var tokenInput: String { didSet { scheduleTokenUpdate() } }
    var checkingConnection = false
    var connectionError: String?
    var generalError: String?
    var launchAtLogin = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    @ObservationIgnored private(set) var tokenTask: Task<Void, Never>?
    @ObservationIgnored private let authenticate: @Sendable (String) async throws -> SlackIdentity
    @ObservationIgnored private let writeToken: @MainActor (String) throws -> Void
    @ObservationIgnored private let applyShortcut: (Configuration) throws -> Void

    init(app: AppModel, applyShortcut: @escaping (Configuration) throws -> Void,
         authenticate: @escaping @Sendable (String) async throws -> SlackIdentity = { try await SlackClient().identity(token: $0) },
         writeToken: @escaping @MainActor (String) throws -> Void = TokenStore.save) {
        self.app = app
        self.applyShortcut = applyShortcut
        self.authenticate = authenticate
        self.writeToken = writeToken
        tokenInput = app.token
    }

    private func scheduleTokenUpdate() {
        tokenTask?.cancel()
        connectionError = nil
        checkingConnection = false
        let candidate = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate != app.token else { return }
        tokenTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard candidate.isEmpty || candidate.hasPrefix("xoxp-") else {
                    throw StorageError.message("User OAuth Token（xoxp-…）を入力してください。")
                }
                checkingConnection = true
                var proposed = app.configuration
                if !candidate.isEmpty {
                    let identity = try await authenticate(candidate)
                    try Task.checkCancellation()
                    proposed = app.configuration
                    proposed.workspace = identity.team
                    proposed.username = identity.user
                }
                try Task.checkCancellation()
                try app.validateConfigurationChange(proposed)
                let previous = app.token
                try writeToken(candidate)
                do { try app.updateConfiguration(proposed) }
                catch { try? writeToken(previous); throw error }
                app.token = candidate
                checkingConnection = false
            } catch {
                guard !Task.isCancelled else { return }
                checkingConnection = false
                connectionError = error.localizedDescription
            }
        }
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
            throw StorageError.message("チャンネルIDを入力してください。")
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
