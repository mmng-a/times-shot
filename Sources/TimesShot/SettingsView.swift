import AppKit
import SwiftUI

@MainActor
final class SettingsViewController: NSTabViewController {
    init(settings: SettingsModel, locale: Locale = .current) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        preferredContentSize = NSSize(width: 520, height: 420)
        let general = NSHostingController(rootView: GeneralSettings(settings: settings))
        general.title = String(localized: LocalizedStringResource("General", locale: locale, bundle: .atURL(Bundle.module.bundleURL)))
        general.preferredContentSize = preferredContentSize
        let channels = NSHostingController(rootView: ChannelSettings(settings: settings))
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

private enum ChannelField: Hashable {
    case name(String)
    case channelID(String)

    var channel: String {
        switch self {
        case .name(let id), .channelID(let id): id
        }
    }
}

private struct ChannelSettings: View {
    let settings: SettingsModel
    @State private var selection: String?
    @State private var error: String?
    @FocusState private var focusedField: ChannelField?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("チャンネル名（表示用）").frame(maxWidth: .infinity, alignment: .leading)
                Text("チャンネルID").frame(width: 130, alignment: .leading)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.bottom, 8)
            List(selection: $selection) {
                ForEach(settings.channels) { channel in
                    ChannelRow(channel: Binding(get: { settings.channelEdits[channel.id] ?? channel }, set: { settings.channelEdits[channel.id] = $0 }),
                               focusedField: $focusedField, commit: { commit(channel.id) })
                        .tag(channel.id)
                        .contextMenu { Button("削除") { remove(channel.id) } }
                }
            }
            .listStyle(.bordered)
            .accessibilityLabel("投稿先チャンネル")
            .onDeleteCommand { if let selection { remove(selection) } }
            HStack(spacing: 0) {
                ChannelListButtons(canRemove: selection != nil, add: add, remove: {
                    if let selection { remove(selection) }
                })
                .frame(width: 56, height: 24)
                Spacer()
            }
            .padding(.top, 6)
            if let error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(.top, 8)
            }
            Text("投稿画面で選んだチャンネルは、次回も維持します。")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .onChange(of: focusedField) { previous, current in
            if let previous, previous.channel != current?.channel { commit(previous.channel) }
            if let current { selection = current.channel }
        }
        .onDisappear { for id in Array(settings.channelEdits.keys) { commit(id) } }
    }

    private func commit(_ id: String) {
        do {
            try settings.commitChannel(id)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func add() {
        let id = settings.startAddingChannel()
        selection = id
        focusedField = .name(id)
    }

    private func remove(_ id: String) {
        do {
            try settings.removeChannel(id)
            selection = settings.app.configuration.channels.first?.id
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ChannelRow: View {
    @Binding var channel: PostingChannel
    let focusedField: FocusState<ChannelField?>.Binding
    let commit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("チャンネル名", text: $channel.name)
                .textFieldStyle(.plain).frame(maxWidth: .infinity)
                .focused(focusedField, equals: .name(channel.id))
            TextField("チャンネルID", text: $channel.channelID)
                .textFieldStyle(.plain).frame(width: 130)
                .focused(focusedField, equals: .channelID(channel.id))
        }
        .padding(.vertical, 5)
        .onSubmit(commit)
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
