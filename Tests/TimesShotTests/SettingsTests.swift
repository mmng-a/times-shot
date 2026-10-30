import AppKit
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
        }
        try configuration.save(defaults: defaults)
        app = AppModel(storage: try DraftStorage(directory: directory), defaults: defaults,
                       readToken: { connected ? "xoxp-original" : "" })
    }

    func cleanup() {
        app.defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

private func identity(team: String = "Workspace") throws -> SlackIdentity {
    try JSONDecoder().decode(SlackIdentity.self, from: JSONSerialization.data(withJSONObject: [
        "team": team, "user": "updated-user", "user_id": "U00000001"
    ]))
}

@MainActor @Test func addingAChannelCreatesAnInlineDraftWithoutRegisteringAnEmptyDestination() throws {
    let fixture = try SettingsFixture()
    defer { fixture.cleanup() }
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in })
    let id = settings.startAddingChannel()
    #expect(settings.channels.count == 1)
    #expect(settings.startAddingChannel() == id)
    #expect(fixture.app.configuration.channels.isEmpty)
    settings.channelEdits[id] = PostingChannel(id: id, name: "times")
    try settings.commitChannel(id)
    #expect(fixture.app.configuration.channels.isEmpty)
    settings.channelEdits[id]?.channelID = "C00000001"
    try settings.commitChannel(id)
    #expect(settings.newChannel == nil)
    #expect(Configuration.load(defaults: fixture.app.defaults).channels.first?.label == "#times")
    let next = settings.startAddingChannel()
    try settings.removeChannel(next)
    #expect(settings.channels.count == 1)
    #expect(fixture.app.configuration.channels.count == 1)
}

@MainActor @Test func composerToolbarUsesNativeControlsAndTracksPostingState() async throws {
    _ = NSApplication.shared
    let fixture = try SettingsFixture(connected: true)
    defer { fixture.cleanup() }
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in })
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
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in })
    let japanese = SettingsViewController(settings: settings, locale: Locale(identifier: "ja"))
    let english = SettingsViewController(settings: settings, locale: Locale(identifier: "en"))
    #expect(japanese.tabViewItems.map(\.label) == ["一般", "チャンネル"])
    #expect(english.tabViewItems.map(\.label) == ["General", "Channels"])
}

@MainActor @Test func channelChangesSaveWithoutAConnectionAndProtectDrafts() throws {
    let fixture = try SettingsFixture()
    defer { fixture.cleanup() }
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in })
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

@MainActor @Test func tokenEditsAutomaticallyVerifyAndSaveOnlyValidCredentials() async throws {
    let fixture = try SettingsFixture(connected: true)
    defer { fixture.cleanup() }
    var saved: [String] = []
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in },
                                 authenticate: { _ in try identity() }, writeToken: { saved.append($0) })
    settings.tokenInput = "xoxp-updated"
    await settings.tokenTask?.value
    #expect(saved == ["xoxp-updated"])
    #expect(fixture.app.token == "xoxp-updated")
    #expect(Configuration.load(defaults: fixture.app.defaults).username == "updated-user")
    settings.tokenInput = "invalid"
    await settings.tokenTask?.value
    #expect(settings.connectionError != nil)
    #expect(saved.count == 1)
    #expect(fixture.app.token == "xoxp-updated")
    settings.tokenInput = ""
    await settings.tokenTask?.value
    #expect(fixture.app.token.isEmpty)
    #expect(!fixture.app.isReady)
    #expect(saved == ["xoxp-updated", ""])
}

@MainActor @Test func changingWorkspacesWithADraftDoesNotReplaceCredentials() async throws {
    let fixture = try SettingsFixture(connected: true)
    defer { fixture.cleanup() }
    fixture.app.draft = Draft(text: "編集中")
    var saved: [String] = []
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in },
                                 authenticate: { _ in try identity(team: "Other") }, writeToken: { saved.append($0) })
    settings.tokenInput = "xoxp-other"
    await settings.tokenTask?.value
    #expect(settings.connectionError != nil)
    #expect(saved.isEmpty)
    #expect(fixture.app.token == "xoxp-original")
    #expect(fixture.app.configuration.workspace == "Workspace")
}

@MainActor @Test func settingsUseLocalizedToolbarAndAddChannelsWithoutASheet() async throws {
    _ = NSApplication.shared
    let fixture = try SettingsFixture(connected: true)
    defer { fixture.cleanup() }
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in })
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
    func findAddControl(in view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl,
           control.segmentCount == 2, control.toolTip(forSegment: 0) == "チャンネルを追加" { return control }
        for child in view.subviews {
            if let control = findAddControl(in: child) { return control }
        }
        return nil
    }
    let content = try #require(window.contentView)
    let addControl = try #require(findAddControl(in: content))
    #expect(addControl.trackingMode == .momentary)
    addControl.trackingMode = .selectOne
    addControl.selectedSegment = 0
    #expect(addControl.sendAction(addControl.action, to: addControl.target))
    addControl.selectedSegment = -1
    addControl.trackingMode = .momentary
    await Task.yield()
    #expect(settings.newChannel != nil)
    #expect(settings.channels.count == 3)
    #expect(fixture.app.configuration.channels.count == 2)
    #expect(window.attachedSheet == nil)

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
