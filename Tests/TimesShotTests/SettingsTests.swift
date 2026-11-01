import AppKit
import AuthenticationServices
import SwiftUI
import Testing
import TimesShotCore
@testable import TimesShot

@MainActor private struct SettingsFixture {
    let suite = "TimesShotSettingsTests.\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let app: AppModel

    init(connected: Bool = false) throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        var configuration = Configuration()
        if connected {
            configuration.channelID = "C00000001"
            configuration.channelName = "times"
            configuration.workspace = "Workspace"
            configuration.username = "user"
            configuration.teamID = "T1"
            configuration.userID = "U1"
        }
        try configuration.save(defaults: defaults)
        app = AppModel(storage: try DraftStorage(directory: directory), defaults: defaults,
                       connection: try testConnection(connected: connected))
    }

    func cleanup() {
        app.defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor @Test func composerToolbarUsesNativeControlsAndTracksPostingState() async throws {
    _ = NSApplication.shared
    let fixture = try SettingsFixture(connected: true)
    defer { fixture.cleanup() }
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in }, client: testSlackClient())
    let extra = PostingChannel(channelID: "C00000002", name: "project")
    try settings.saveChannel(extra)
    let controller = ComposerWindowController(model: fixture.app)
    let window = try #require(controller.window)
    defer { window.close() }
    #expect(window.toolbarStyle == .unified)
    #expect(window.title == "新規投稿")
    #expect(controller.sendItem.style == .prominent)
    #expect(!controller.sendItem.isEnabled)
    #expect(controller.channelPicker.numberOfItems == 2)
    fixture.app.draft = Draft(text: "本文")
    await Task.yield()
    #expect(controller.sendItem.isEnabled)
    controller.channelPicker.selectItem(at: 1)
    controller.channelPicker.sendAction(controller.channelPicker.action, to: controller.channelPicker.target)
    #expect(fixture.app.configuration.selectedDestinationID == extra.id)
    fixture.app.importing = true
    await Task.yield()
    #expect(!controller.sendItem.isEnabled)
    #expect(!controller.attachmentItem.isEnabled)
    #expect(!window.isVisible)
}

@MainActor @Test func settingsPaneTitlesAreLocalizedInJapaneseAndEnglish() throws {
    let fixture = try SettingsFixture()
    defer { fixture.cleanup() }
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in }, client: testSlackClient())
    let japanese = SettingsViewController(settings: settings, locale: Locale(identifier: "ja"))
    let english = SettingsViewController(settings: settings, locale: Locale(identifier: "en"))
    #expect(japanese.tabViewItems.map(\.label) == ["一般", "チャンネル"])
    #expect(english.tabViewItems.map(\.label) == ["General", "Channels"])
}

@MainActor @Test func channelChangesSaveWithoutAConnectionAndProtectDrafts() throws {
    let fixture = try SettingsFixture()
    defer { fixture.cleanup() }
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in }, client: testSlackClient())
    #expect(fixture.app.configuration.channels.isEmpty)
    try settings.saveChannel(PostingChannel(id: Configuration.defaultDestinationID, channelID: "C00000001", name: "times"))
    let extra = PostingChannel(channelID: "C00000002", name: "project")
    try settings.saveChannel(extra)
    fixture.app.selectChannel(extra.id)
    #expect(Configuration.load(defaults: fixture.app.defaults).channels.count == 2)
    #expect(throws: StorageError.self) {
        try settings.saveChannel(PostingChannel(channelID: "C00000001", name: "duplicate"))
    }
    try settings.removeChannel(Configuration.defaultDestinationID)
    #expect(fixture.app.configuration.selectedChannel?.channelID == "C00000002")
    #expect(fixture.app.configuration.selectedDestinationID == Configuration.defaultDestinationID)
    fixture.app.draft = Draft(text: "編集中")
    #expect(throws: StorageError.self) { try settings.removeChannel(Configuration.defaultDestinationID) }
    #expect(fixture.app.configuration.channels.count == 1)
    fixture.app.draft = Draft()
    try settings.removeChannel(Configuration.defaultDestinationID)
    #expect(Configuration.load(defaults: fixture.app.defaults).channels.isEmpty)
}

@MainActor @Test func reconnectingAnotherAccountDoesNotMoveDraftsOrReplaceCredentials() throws {
    let fixture = try SettingsFixture(connected: true)
    defer { fixture.cleanup() }
    fixture.app.draft = Draft(text: "編集中")
    let original = fixture.app.connection.credentials
    #expect(throws: StorageError.self) { try fixture.app.connect(testCredentials(teamID: "T2")) }
    #expect(throws: StorageError.self) { try fixture.app.connect(testCredentials(userID: "U2")) }
    #expect(fixture.app.connection.credentials == original)
    #expect(fixture.app.configuration.selectedChannel?.channelID == "C00000001")
    try fixture.app.connect(testCredentials())
    #expect(fixture.app.connection.credentials?.connectionID == original?.connectionID)
    #expect(fixture.app.draft.text == "編集中")
}

@MainActor @Test func disconnectRemovesCredentialsAndPreventsSendingWithoutDiscardingDrafts() throws {
    let fixture = try SettingsFixture(connected: true)
    defer { fixture.cleanup() }
    fixture.app.draft = Draft(text: "編集中")
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in }, client: testSlackClient())
    settings.disconnect()
    #expect(fixture.app.connection.credentials == nil)
    #expect(!fixture.app.canSend)
    #expect(fixture.app.draft.text == "編集中")
    try fixture.app.connect(testCredentials())
    #expect(fixture.app.canSend)
    #expect(fixture.app.configuration.selectedChannel?.channelID == "C00000001")
}

@MainActor @Test func browserCancellationIsVisibleAndLeavesTheExistingConnectionIntact() async throws {
    _ = NSApplication.shared
    let fixture = try SettingsFixture(connected: true)
    defer { fixture.cleanup() }
    let original = fixture.app.connection.credentials
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in }, client: testSlackClient(),
                                 authenticate: { _, _ in
        throw NSError(domain: ASWebAuthenticationSessionErrorDomain, code: ASWebAuthenticationSessionError.canceledLogin.rawValue)
    })
    let window = NSWindow()
    window.isReleasedWhenClosed = false
    defer { window.close() }
    await settings.connect(window: window)
    #expect(settings.connectionError?.contains("キャンセル") == true)
    #expect(!settings.checkingConnection)
    #expect(fixture.app.connection.credentials == original)
}

@MainActor @Test func settingsUseLocalizedToolbarAndChooseChannelsWithoutIDFields() async throws {
    _ = NSApplication.shared
    let fixture = try SettingsFixture(connected: true)
    defer { fixture.cleanup() }
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in }, client: testSlackClient())
    try settings.saveChannel(PostingChannel(channelID: "C00000002", name: "project"))
    let controller = SettingsViewController(settings: settings, locale: Locale(identifier: "ja"))
    let window = controller.makeWindow()
    defer { window.close() }
    #expect(controller.tabStyle == .toolbar)
    #expect(controller.tabViewItems.map(\.label) == ["一般", "チャンネル"])
    #expect(window.toolbarStyle == .preference)
    #expect(window.toolbar != nil)
    #expect(!window.isVisible)

    controller.selectedTabViewItemIndex = 1
    try await Task.sleep(for: .milliseconds(100))
    #expect(window.attachedSheet == nil)
    #expect(fixture.app.configuration.channels.count == 2)

    if let path = ProcessInfo.processInfo.environment["TIMES_SHOT_UI_PREVIEW_DIR"] {
        let directory = URL(filePath: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func capture(_ window: NSWindow, filename: String) throws {
            let view = try #require(window.contentView?.superview)
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent(filename))
        }
        for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            window.appearance = NSAppearance(named: appearance)
            for index in 0..<2 {
                controller.selectedTabViewItemIndex = index
                try await Task.sleep(for: .milliseconds(100))
                try capture(window, filename: "\(index)-\(name).png")
            }
        }
        let composer = ComposerWindowController(model: fixture.app)
        let composerWindow = try #require(composer.window)
        defer { composerWindow.close() }
        for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            composerWindow.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(100))
            try capture(composerWindow, filename: "composer-\(name).png")
        }
    }
}
