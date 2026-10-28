import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct TimesShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("設定…") { delegate.showSettings() }.keyboardShortcut(",")
                }
            }
    }
}

private final class ComposerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private var model: AppModel!
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var previousApp: NSRunningApplication?
    private var statusItem: NSStatusItem!
    private let hotKey = GlobalHotKey()
    private var activeShortcut: (UInt32, UInt32)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do { model = AppModel(storage: try DraftStorage()) }
        catch {
            let alert = NSAlert()
            alert.messageText = "Times Shotを起動できませんでした"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        model.onAccepted = { [weak self] in self?.hideComposer() }
        model.onStatusChange = { [weak self] in self?.updateStatus() }
        hotKey.action = { [weak self] in self?.toggleComposer() }
        do { try applyShortcut(model.configuration) }
        catch { model.notify(title: "ショートカットを登録できませんでした", body: error.localizedDescription) }
        UNUserNotificationCenter.current().delegate = self
        updateStatus()
        if !model.isReady { showSettings() }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        }
        if !UserDefaults.standard.bool(forKey: "loginPreferenceChosen") {
            do {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: "loginPreferenceChosen")
            } catch { model.notify(title: "ログイン時の起動を設定できませんでした", body: "設定画面で再度有効にしてください。") }
        }
    }

    private func applyShortcut(_ configuration: Configuration) throws {
        if let activeShortcut,
           activeShortcut.0 == configuration.keyCode, activeShortcut.1 == configuration.modifiers { return }
        try hotKey.register(keyCode: configuration.keyCode, modifiers: configuration.modifiers)
        activeShortcut = (configuration.keyCode, configuration.modifiers)
    }

    @objc private func toggleComposer() {
        if panel?.isVisible == true { hideComposer() } else { showComposer() }
    }

    private func showComposer() {
        previousApp = NSWorkspace.shared.frontmostApplication
        if panel == nil {
            let window = ComposerPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 340),
                                       styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Times Shot"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            window.contentView = NSHostingView(rootView: ComposerView(model: model, settings: { [weak self] in self?.showSettings() }))
            panel = window
        }
        guard let panel else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let bounds = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: bounds.midX - panel.frame.width / 2, y: bounds.midY - panel.frame.height / 2))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        if let editor = findEditor(in: panel.contentView) {
            panel.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }

    private func hideComposer() {
        model.saveDraft()
        let shouldRestore = panel?.isKeyWindow == true && NSApp.isActive
        panel?.orderOut(nil)
        if shouldRestore, let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate()
        }
        previousApp = nil
    }

    private func findEditor(in view: NSView?) -> PostingTextView? {
        if let editor = view as? PostingTextView { return editor }
        for child in view?.subviews ?? [] {
            if let editor = findEditor(in: child) { return editor }
        }
        return nil
    }

    @objc func showSettings() {
        model.saveDraft()
        panel?.orderOut(nil)
        previousApp = nil
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 540),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Times Shot 設定"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, applyShortcut: { [weak self] config in
                try self?.applyShortcut(config)
            }))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateStatus() {
        guard statusItem != nil else { return }
        let count = model.queue.count
        let symbol = count > 0 ? "arrow.up.circle.fill" : (model.latestError == nil ? "square.and.pencil" : "exclamationmark.circle")
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Times Shot")
        statusItem.button?.title = count > 0 ? " \(count)" : ""
        statusItem.button?.toolTip = count > 0 ? "Times Shot：\(count)件を送信中・送信待ち" : "Times Shot"
        let menu = NSMenu()
        let post = menu.addItem(withTitle: "投稿する（\(model.configuration.shortcutLabel)）", action: #selector(toggleComposer), keyEquivalent: "")
        post.target = self
        if count > 0 { menu.addItem(withTitle: "送信中・送信待ち：\(count)件", action: nil, keyEquivalent: "") }
        if let error = model.latestError {
            let latest = menu.addItem(withTitle: String(error.prefix(220)), action: nil, keyEquivalent: "")
            latest.toolTip = error
            let clear = menu.addItem(withTitle: "エラー表示を消す", action: #selector(clearError), keyEquivalent: "")
            clear.target = self
        }
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "設定…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let quit = menu.addItem(withTitle: "Times Shotを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        statusItem.menu = menu
    }

    @objc private func clearError() { model.latestError = nil; updateStatus() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel { hideComposer(); return false }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model != nil else { return .terminateNow }
        if model.queue.count > 0 || model.importing {
            let alert = NSAlert()
            alert.messageText = "処理を中止して終了しますか？"
            alert.informativeText = "送信中・送信待ちの\(model.queue.count)件と読み込み中の画像を破棄します。送信中の投稿は、Slack側で完了する可能性があります。"
            alert.addButton(withTitle: "キャンセル")
            alert.addButton(withTitle: "破棄して終了")
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        }
        model.cancelImport()
        model.queue.discardAll()
        model.saveDraft()
        try? model.storage.removeOrphans(keeping: model.draft.images)
        return .terminateNow
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions { [.banner, .list] }
}
