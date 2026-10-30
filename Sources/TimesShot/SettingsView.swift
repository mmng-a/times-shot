import AppKit
import ServiceManagement
import SwiftUI
import TimesShotCore

struct SettingsView: View {
    let model: AppModel
    let applyShortcut: (Configuration) throws -> Void
    @State private var configuration = Configuration()
    @State private var token = ""
    @State private var message = ""
    @State private var saving = false
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Times Shot 設定").font(.title2).fontWeight(.semibold)
            Form {
                SlackSettingsFields(token: $token, channelID: $configuration.channelID,
                                    channelName: $configuration.channelName)
                AdditionalChannelSettings(channels: $configuration.additionalChannels,
                                          remove: { configuration.removeAdditionalChannel($0) })
                Section("操作") {
                    LabeledContent("呼び出す／隠す") {
                        ShortcutRecorder(label: configuration.shortcutLabel) { shortcut in
                            configuration.keyCode = shortcut.keyCode
                            configuration.modifiers = shortcut.modifiers
                            configuration.shortcutLabel = shortcut.label
                        }.frame(width: 150, height: 26)
                    }
                    Toggle("ログイン時に起動", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled, ![.enabled, .requiresApproval].contains(SMAppService.mainApp.status) {
                                    try SMAppService.mainApp.register()
                                } else if !enabled, SMAppService.mainApp.status != .notRegistered {
                                    try SMAppService.mainApp.unregister()
                                }
                                UserDefaults.standard.set(true, forKey: "loginPreferenceChosen")
                                message = SMAppService.mainApp.status == .requiresApproval
                                    ? "自動起動はシステム設定で許可してください。" : ""
                            } catch { message = error.localizedDescription }
                        }
                }
            }.formStyle(.grouped).disabled(saving)
            Text("\(configuration.workspace) \(configuration.username)").foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
            HStack {
                Button("通知設定") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Button(saving ? "接続を確認中…" : "接続を確認して保存") { Task { await save() } }
                    .buttonStyle(.borderedProminent).disabled(saving)
            }
        }
        .padding(24).frame(width: 520)
        .onAppear {
            configuration = model.configuration
            launchAtLogin = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
            do { token = try TokenStore.read() } catch { message = error.localizedDescription }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var proposed = configuration
        guard cleanToken.hasPrefix("xoxp-") else { message = "User OAuth Token（xoxp-…）を入力してください。"; return }
        do {
            try proposed.validateChannels()
            let identity = try await SlackClient().identity(token: cleanToken)
            proposed.workspace = identity.team
            proposed.username = identity.user
            let selectedID = model.configuration.selectedDestinationID
            proposed.selectedDestinationID = proposed.channels.contains { $0.id == selectedID }
                ? selectedID : Configuration.defaultDestinationID
            if !model.draft.isEmpty,
               (proposed.selectedChannel?.channelID != model.configuration.selectedChannel?.channelID
                || proposed.workspace != model.configuration.workspace) {
                message = "下書きがあります。送信するかEscで破棄してから、選択中の投稿先を変更・削除してください。"
                return
            }
            try applyShortcut(proposed)
            do {
                try TokenStore.save(cleanToken)
                try proposed.save(defaults: model.defaults)
            } catch {
                try? applyShortcut(model.configuration)
                throw error
            }
            configuration = proposed
            model.configuration = proposed
            model.token = cleanToken
            model.onStatusChange?()
            message = "保存しました。投稿先：\(proposed.destination)"
        } catch { message = error.localizedDescription }
    }
}

private struct SlackSettingsFields: View {
    @Binding var token: String
    @Binding var channelID: String
    @Binding var channelName: String

    var body: some View {
        Section("Slack") {
            SecureField("User OAuth Token", text: $token)
            TextField("普段のチャンネルID", text: $channelID)
            TextField("普段のチャンネル名（表示用）", text: $channelName)
            Text("User Token Scopesに chat:write と files:write を設定してください。トークンはKeychainに保存します。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct AdditionalChannelSettings: View {
    @Binding var channels: [PostingChannel]
    let remove: (String) -> Void

    var body: some View {
        Section("追加の投稿先") {
            ForEach($channels) { $channel in
                AdditionalChannelRow(channel: $channel, remove: { remove(channel.id) })
            }
            Button("チャンネルを追加", systemImage: "plus") { channels.append(PostingChannel()) }
            Text("投稿画面で切り替えられます。選んだ投稿先は、次回の投稿や再起動後も維持します。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct AdditionalChannelRow: View {
    @Binding var channel: PostingChannel
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("チャンネルID", text: $channel.channelID)
                Button("削除", systemImage: "minus.circle", action: remove)
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .accessibilityLabel("\(channel.label.isEmpty ? "追加の投稿先" : channel.label)を削除")
            }
            TextField("チャンネル名（表示用）", text: $channel.name)
        }
        .padding(.vertical, 4)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let label: String
    let recorded: (RecordedShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutButton {
        let button = ShortcutButton()
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(ShortcutButton.beginRecording)
        button.recorded = recorded
        return button
    }

    func updateNSView(_ button: ShortcutButton, context: Context) {
        if !button.recording { button.title = label }
        button.recorded = recorded
    }
}

private final class ShortcutButton: NSButton {
    var recording = false
    var recorded: ((RecordedShortcut) -> Void)?
    private var oldTitle = ""
    override var acceptsFirstResponder: Bool { true }

    @objc func beginRecording() {
        oldTitle = title
        recording = true
        title = "キーを入力…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; title = oldTitle; return }
        guard let shortcut = RecordedShortcut(event: event) else { return }
        recording = false
        title = shortcut.label
        recorded?(shortcut)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
}
