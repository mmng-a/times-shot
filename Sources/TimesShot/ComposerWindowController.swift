import AppKit
import Observation
import SwiftUI

private final class ComposerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ComposerWindowController: NSWindowController, NSToolbarDelegate {
    private let model: AppModel
    let channelPicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 28), pullsDown: false)
    let attachmentItem = NSToolbarItem(itemIdentifier: .init("attachImage"))
    let sendItem = NSToolbarItem(itemIdentifier: .init("sendPost"))
    private var shownChannels: [PostingChannel] = []

    init(model: AppModel) {
        self.model = model
        let panel = ComposerPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 340),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "新規投稿"
        panel.toolbarStyle = .unified
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let hostingController = NSHostingController(rootView: ComposerView(model: model))
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.contentView = hostingController.view
        let contentController = NSViewController()
        contentController.addChild(hostingController)
        contentController.view = glass
        panel.contentViewController = contentController
        panel.contentMinSize = NSSize(width: 460, height: 240)
        panel.setContentSize(NSSize(width: 540, height: 340))

        channelPicker.target = self
        channelPicker.action = #selector(selectChannel)
        channelPicker.setAccessibilityLabel("投稿先")
        channelPicker.cell?.lineBreakMode = .byTruncatingMiddle
        channelPicker.translatesAutoresizingMaskIntoConstraints = false
        channelPicker.widthAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
        attachmentItem.label = "画像を添付"
        attachmentItem.toolTip = "画像を添付…"
        attachmentItem.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: attachmentItem.label)
        attachmentItem.target = self
        attachmentItem.action = #selector(chooseFiles)
        attachmentItem.autovalidates = false
        sendItem.label = "送信"
        sendItem.toolTip = "送信（⌘Return）"
        sendItem.image = NSImage(systemSymbolName: "paperplane", accessibilityDescription: sendItem.label)
        sendItem.style = .prominent
        sendItem.visibilityPriority = .high
        sendItem.target = self
        sendItem.action = #selector(sendPost)
        sendItem.autovalidates = false
        let toolbar = NSToolbar(identifier: "composer")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        panel.toolbar = toolbar
        observeModel()
    }

    required init?(coder: NSCoder) { nil }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("channel"), .flexibleSpace, attachmentItem.itemIdentifier, sendItem.itemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case attachmentItem.itemIdentifier: return attachmentItem
        case sendItem.itemIdentifier: return sendItem
        default:
            if identifier.rawValue == "channel" {
                let item = NSToolbarItem(itemIdentifier: identifier)
                item.label = "投稿先"
                item.view = channelPicker
                return item
            }
            return nil
        }
    }

    private func observeModel() {
        withObservationTracking {
            updateToolbar()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeModel() }
        }
    }

    private func updateToolbar() {
        let configuration = model.configuration
        let channels = configuration.channels
        if channels != shownChannels || channelPicker.numberOfItems == 0 {
            channelPicker.removeAllItems()
            if channels.isEmpty { channelPicker.addItem(withTitle: "投稿先なし") }
            for channel in channels {
                channelPicker.addItem(withTitle: channel.label)
                channelPicker.lastItem?.representedObject = channel.id
            }
            shownChannels = channels
        }
        channelPicker.isEnabled = !channels.isEmpty
        if let selected = channelPicker.itemArray.first(where: { $0.representedObject as? String == configuration.selectedDestinationID }) {
            channelPicker.select(selected)
        }
        window?.subtitle = configuration.workspace
        attachmentItem.isEnabled = !model.importing
        sendItem.isEnabled = model.canSend
    }

    @objc private func selectChannel(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        model.selectChannel(id)
        updateToolbar()
    }

    @objc private func sendPost() { model.send() }

    @objc func chooseFiles() {
        guard let window else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.image]
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.prompt = "添付"
        picker.beginSheetModal(for: window) { [weak self] response in
            if response == .OK { self?.model.addFiles(picker.urls) }
        }
    }
}
