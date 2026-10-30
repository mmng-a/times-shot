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

@MainActor @Test func settingsUseTheNativePreferencesToolbar() async throws {
    _ = NSApplication.shared
    let fixture = try SettingsFixture(connected: true)
    defer { fixture.cleanup() }
    let settings = SettingsModel(app: fixture.app, applyShortcut: { _ in })
    try settings.saveChannel(PostingChannel(channelID: "C00000002", name: "project"))
    let controller = SettingsViewController(settings: settings)
    let window = controller.makeWindow()
    defer { window.close() }
    #expect(controller.tabStyle == .toolbar)
    #expect(controller.tabViewItems.map(\.label) == ["General", "Channels"])
    #expect(window.toolbarStyle == .preference)
    #expect(window.toolbar != nil)
    #expect(!window.isVisible)

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
        let composer = NSWindow(contentViewController: NSHostingController(rootView: ComposerView(model: fixture.app, settings: {})))
        composer.isReleasedWhenClosed = false
        composer.setContentSize(NSSize(width: 540, height: 340))
        defer { composer.close() }
        try await Task.sleep(for: .milliseconds(100))
        try capture(composer, filename: "composer.png")
    }
}
