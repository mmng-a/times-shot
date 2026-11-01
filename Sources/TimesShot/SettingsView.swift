import AppKit
import SwiftUI
import TimesShotCore

@MainActor
final class SettingsViewController: NSTabViewController {
    init(settings: SettingsModel, locale: Locale = .current) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        preferredContentSize = NSSize(width: 520, height: 420)
        let general = NSHostingController(rootView: GeneralSettings(settings: settings).environment(\.locale, locale))
        general.title = String(localized: LocalizedStringResource("General", locale: locale, bundle: .atURL(Bundle.module.bundleURL)))
        general.preferredContentSize = preferredContentSize
        let channels = NSHostingController(rootView: ChannelSettings(settings: settings).environment(\.locale, locale))
        channels.title = String(localized: LocalizedStringResource("Channels", locale: locale, bundle: .atURL(Bundle.module.bundleURL)))
        channels.preferredContentSize = preferredContentSize
        for (controller, symbol) in [(general as NSViewController, "gearshape"), (channels, "number")] {
            let item = NSTabViewItem(viewController: controller)
            item.label = controller.title ?? ""
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.label)
            addTabViewItem(item)
        }
    }

    required init?(coder: NSCoder) { nil }

    func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: self)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.toolbar?.allowsUserCustomization = false
        return window
    }
}

private struct GeneralSettings: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section("Slack") {
                SlackConnectionSettings(settings: settings)
            }
            Section("操作") {
                LabeledContent("呼び出す／隠す") {
                    ShortcutRecorder(label: settings.app.configuration.shortcutLabel, recorded: settings.setShortcut)
                        .frame(width: 150, height: 26)
                }
                Toggle("ログイン時に起動", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
                Button("通知設定…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                if let error = settings.generalError {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
    }
}

private struct SlackConnectionSettings: View {
    let settings: SettingsModel

    var body: some View {
        if let credentials = settings.app.connection.credentials {
            LabeledContent("アカウント") {
                Text(verbatim: credentials.username + " / " + credentials.workspace)
                    .foregroundStyle(.secondary)
            }
        }
        HStack {
            Button {
                Task { await settings.connect(window: NSApp.keyWindow) }
            } label: {
                if settings.app.connection.credentials == nil {
                    Text("Slackに接続", bundle: .module)
                } else {
                    Text("Slackに再接続", bundle: .module)
                }
            }
            .disabled(settings.checkingConnection || settings.app.connection.clientID.isEmpty)
            if settings.app.connection.credentials != nil {
                Button { settings.disconnect() } label: { Text("接続解除", bundle: .module) }
                    .disabled(settings.checkingConnection)
            }
            if settings.checkingConnection { ProgressView().controlSize(.small) }
        }
        if settings.app.connection.clientID.isEmpty {
            Text("このバージョンはSlackへの接続設定が完了していません。", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
        } else if settings.app.connection.requiresReconnect {
            Text("Slackに再接続してください。", bundle: .module)
                .font(.callout).foregroundStyle(.red)
        }
        if let error = settings.connectionError {
            Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
        }
        Text("認証情報はこのMacのKeychainに保存します。接続解除はこのMacに保存した認証情報を削除します。", bundle: .module)
            .font(.caption).foregroundStyle(.secondary)
    }
}

private struct ChannelSettings: View {
    @Bindable var settings: SettingsModel
    @State private var selection: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("登録した投稿先", bundle: .module).font(.headline)
            List(selection: $selection) {
                ForEach(settings.app.configuration.channels) { channel in
                    Text(verbatim: channel.label).tag(channel.id)
                        .contextMenu { Button("削除") { remove(channel.id) } }
                }
            }
            .listStyle(.bordered).frame(height: 100)
            .accessibilityLabel("投稿先チャンネル")
            .onDeleteCommand { if let selection { remove(selection) } }
            HStack {
                Button { if let selection { remove(selection) } } label: {
                    Image(systemName: "minus")
                }
                .help("選択したチャンネルを削除").disabled(selection == nil)
                Spacer()
                Button { Task { await settings.reloadChannels() } } label: {
                    Label { Text("一覧を再取得", bundle: .module) } icon: { Image(systemName: "arrow.clockwise") }
                }
                .disabled(settings.loadingChannels || settings.app.connection.credentials == nil || settings.checkingConnection)
            }
            Divider()
            TextField(text: $settings.channelSearch) { Text("追加するチャンネルを検索", bundle: .module) }
                .textFieldStyle(.roundedBorder)
            AvailableChannels(settings: settings)
            if let error = error ?? settings.channelError {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .task(id: settings.app.connection.credentials?.connectionID) { await settings.reloadChannels() }
    }

    private func remove(_ id: String) {
        do {
            try settings.removeChannel(id)
            selection = settings.app.configuration.channels.first?.id
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct AvailableChannels: View {
    let settings: SettingsModel

    var body: some View {
        List(settings.filteredChannels) { channel in
            let registered = settings.app.configuration.channels.contains { $0.channelID == channel.id }
            Button { settings.addChannel(channel) } label: {
                HStack {
                    Label(channel.name, systemImage: channel.is_private ? "lock" : "number")
                    Spacer()
                    Image(systemName: registered ? "checkmark" : "plus")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(registered || settings.loadingChannels || settings.app.connection.requiresReconnect)
            .accessibilityLabel(channel.name)
            .accessibilityHint(registered ? "登録済み" : "投稿先に追加")
        }
        .listStyle(.bordered)
        .overlay {
            if settings.loadingChannels {
                ProgressView()
            } else if settings.app.connection.credentials == nil {
                Text("一般設定からSlackに接続してください。", bundle: .module).foregroundStyle(.secondary)
            } else if settings.filteredChannels.isEmpty, settings.channelError == nil {
                Text("該当するチャンネルがありません。", bundle: .module).foregroundStyle(.secondary)
            }
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

    override func resignFirstResponder() -> Bool {
        if recording { recording = false; title = oldTitle }
        return super.resignFirstResponder()
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
