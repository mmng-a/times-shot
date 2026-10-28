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
        proposed.channelID = proposed.channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanToken.hasPrefix("xoxp-") else { message = "User OAuth Token（xoxp-…）を入力してください。"; return }
        guard proposed.channelID.range(of: "^[CG][A-Z0-9]+$", options: .regularExpression) != nil else {
            message = "チャンネルID（C…またはG…）を入力してください。"; return
        }
        do {
            let identity = try await SlackClient().identity(token: cleanToken)
            proposed.workspace = identity.team
            proposed.username = identity.user
            if !model.draft.isEmpty,
               (proposed.channelID != model.configuration.channelID || proposed.workspace != model.configuration.workspace) {
                message = "下書きがあります。送信するかEscで破棄してから、投稿先を変更してください。"
                return
            }
            try applyShortcut(proposed)
            do {
                try TokenStore.save(cleanToken)
                try proposed.save()
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
            TextField("チャンネルID", text: $channelID)
            TextField("チャンネル名（表示用）", text: $channelName)
            Text("User Token Scopesに chat:write と files:write を設定してください。トークンはKeychainに保存します。")
                .font(.caption).foregroundStyle(.secondary)
        }
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
