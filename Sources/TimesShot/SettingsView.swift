import AppKit
import SwiftUI

@MainActor
final class SettingsViewController: NSTabViewController {
    init(settings: SettingsModel) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        preferredContentSize = NSSize(width: 520, height: 420)
        let general = NSHostingController(rootView: GeneralSettings(settings: settings))
        general.title = "General"
        general.preferredContentSize = preferredContentSize
        let channels = NSHostingController(rootView: ChannelSettings(settings: settings))
        channels.title = "Channels"
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
                SecureField("User OAuth Token", text: $settings.tokenInput)
                if settings.checkingConnection {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("接続を確認中…").foregroundStyle(.secondary)
                    }
                } else if let error = settings.connectionError {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                } else if !settings.app.token.isEmpty {
                    LabeledContent("アカウント") {
                        Text(verbatim: settings.app.configuration.username + " / " + settings.app.configuration.workspace)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("User Token Scopesにchat:writeとfiles:writeが必要です。認証情報はKeychainに保存します。")
                    .font(.caption).foregroundStyle(.secondary)
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

private struct ChannelSettings: View {
    let settings: SettingsModel
    @State private var selection: String?
    @State private var editing: PostingChannel?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(settings.app.configuration.channels) { channel in
                    ChannelRow(channel: channel).tag(channel.id)
                        .contextMenu {
                            Button("編集…") { editing = channel }
                            Button("削除") { remove(channel.id) }
                        }
                }
            }
            .listStyle(.bordered)
            .accessibilityLabel("投稿先チャンネル")
            .onDeleteCommand { if let selection { remove(selection) } }
            .onKeyPress(.return) {
                guard let channel = settings.app.configuration.channels.first(where: { $0.id == selection }) else { return .ignored }
                editing = channel
                return .handled
            }
            HStack(spacing: 0) {
                ChannelListButtons(canRemove: selection != nil, add: add, remove: {
                    if let selection { remove(selection) }
                })
                .frame(width: 56, height: 24)
                Spacer()
                Button("編集…") {
                    editing = settings.app.configuration.channels.first { $0.id == selection }
                }
                .disabled(selection == nil)
                .controlSize(.small)
            }
            .padding(.top, 6)
            if let error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(.top, 8)
            }
            Text("選んだ投稿先は次回も維持します。「普段」のチャンネルには投稿画面から戻れます。")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .sheet(item: $editing) { channel in
            ChannelEditor(settings: settings, channel: channel) { selection = channel.id }
        }
    }

    private func add() {
        let id = settings.app.configuration.channels.isEmpty ? Configuration.defaultDestinationID : UUID().uuidString
        editing = PostingChannel(id: id)
    }

    private func remove(_ id: String) {
        do {
            try settings.removeChannel(id)
            selection = settings.app.configuration.channels.first?.id
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct ChannelRow: View {
    let channel: PostingChannel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: channel.label)
                Text(verbatim: channel.channelID).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if channel.id == Configuration.defaultDestinationID {
                Text("普段").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ChannelEditor: View {
    let settings: SettingsModel
    let completed: () -> Void
    @State private var channel: PostingChannel
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(settings: SettingsModel, channel: PostingChannel, completed: @escaping () -> Void) {
        self.settings = settings
        self.completed = completed
        _channel = State(initialValue: channel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("チャンネル").font(.headline)
            Form {
                TextField("チャンネル名", text: $channel.name).focused($focused)
                TextField("チャンネルID", text: $channel.channelID)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("完了") {
                    do { try settings.saveChannel(channel); completed(); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(channel.channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 400)
        .onAppear { focused = true }
    }
}

private struct ChannelListButtons: NSViewRepresentable {
    let canRemove: Bool
    let add: () -> Void
    let remove: () -> Void

    func makeNSView(context: Context) -> ChannelActionsControl {
        let control = ChannelActionsControl()
        control.segmentCount = 2
        control.trackingMode = .momentary
        control.segmentStyle = .smallSquare
        control.controlSize = .small
        control.target = control
        control.action = #selector(ChannelActionsControl.performAction)
        for (index, symbol) in ["plus", "minus"].enumerated() {
            control.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: index == 0 ? "チャンネルを追加" : "選択したチャンネルを削除"), forSegment: index)
            control.setWidth(28, forSegment: index)
            control.setToolTip(index == 0 ? "チャンネルを追加" : "選択したチャンネルを削除", forSegment: index)
        }
        return control
    }

    func updateNSView(_ control: ChannelActionsControl, context: Context) {
        control.add = add
        control.remove = remove
        control.setEnabled(canRemove, forSegment: 1)
    }
}

private final class ChannelActionsControl: NSSegmentedControl {
    var add: (() -> Void)?
    var remove: (() -> Void)?

    @objc func performAction() {
        if selectedSegment == 0 { add?() }
        else if selectedSegment == 1 { remove?() }
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
