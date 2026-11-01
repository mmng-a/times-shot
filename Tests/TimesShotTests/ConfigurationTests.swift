import Foundation
import Testing
import TimesShotCore
@testable import TimesShot

@Test func existingSingleChannelSettingsKeepTheirDestinationAndShortcut() throws {
    let data = Data(#"{"channelID":"C00000001","channelName":"times","workspace":"Workspace","username":"user","keyCode":49,"modifiers":512,"shortcutLabel":"Shift + Space"}"#.utf8)
    let configuration = try JSONDecoder().decode(Configuration.self, from: data)
    #expect(configuration.isConfigured)
    #expect(configuration.additionalChannels.isEmpty)
    #expect(configuration.selectedDestinationID == Configuration.defaultDestinationID)
    #expect(configuration.selectedChannel?.channelID == "C00000001")
    #expect(configuration.destination == "#times")
    #expect(configuration.keyCode == 49)
    #expect(configuration.modifiers == 512)
    #expect(configuration.shortcutLabel == "Shift + Space")
}

@Test func channelSettingsNormalizeInputAndPreserveSelectionWhenEncoded() throws {
    var configuration = Configuration()
    configuration.channelID = " C00000001\n"
    configuration.channelName = " times "
    let extra = PostingChannel(channelID: " G00000002 ", name: " project ")
    configuration.additionalChannels = [extra]
    configuration.selectedDestinationID = extra.id
    try configuration.validateChannels()
    let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(configuration))
    #expect(restored == configuration)
    #expect(restored.channelID == "C00000001")
    #expect(restored.channelName == "times")
    #expect(restored.selectedChannel?.channelID == "G00000002")
    #expect(restored.destination == "#project")
    configuration.removeAdditionalChannel(extra.id)
    #expect(configuration.selectedDestinationID == Configuration.defaultDestinationID)
    #expect(configuration.selectedChannel?.channelID == "C00000001")
}

@Test(arguments: ["", "#project", "C00000001"])
func invalidOrDuplicateChannelSettingsAreRejected(channelID: String) {
    var configuration = Configuration()
    configuration.channelID = "C00000001"
    configuration.additionalChannels = [PostingChannel(channelID: channelID)]
    #expect(throws: StorageError.self) { try configuration.validateChannels() }
}

@MainActor @Test func switchingChannelsKeepsDraftsAndQueuedPostsKeepTheirDestinations() async throws {
    let suite = "TimesShotTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try DraftStorage(directory: directory)
    var configuration = Configuration()
    configuration.channelID = "C00000001"
    configuration.channelName = "times"
    configuration.workspace = "Workspace"
    configuration.teamID = "T1"
    configuration.userID = "U1"
    let extra = PostingChannel(channelID: "C00000002", name: "project")
    configuration.additionalChannels = [extra]
    try configuration.save(defaults: defaults)
    let model = AppModel(storage: storage, defaults: defaults, connection: try testConnection())
    let restartConnection = try testConnection()
    var delivered: [PendingPost] = []
    await withCheckedContinuation { done in
        model.queue = PostingQueue(send: { _ in }, completed: { post, _ in
            delivered.append(post)
            if delivered.count == 3 { done.resume() }
        })
        model.draft = Draft(text: "最初の投稿")
        model.selectChannel(extra.id)
        #expect(model.draft.text == "最初の投稿")
        #expect((try? storage.load().text) == "最初の投稿")
        model.send()
        #expect(model.configuration.selectedDestinationID == extra.id)
        model.draft = Draft(text: "次の投稿")
        model.send()
        #expect(model.configuration.selectedDestinationID == extra.id)
        let restarted = AppModel(storage: storage, defaults: defaults, connection: restartConnection)
        #expect(restarted.configuration.selectedDestinationID == extra.id)
        model.selectChannel(Configuration.defaultDestinationID)
        model.draft = Draft(text: "timesの投稿")
        model.send()
    }
    #expect(delivered.map(\.channelID) == ["C00000002", "C00000002", "C00000001"])
    #expect(delivered.map(\.draft.text) == ["最初の投稿", "次の投稿", "timesの投稿"])
    #expect(Configuration.load(defaults: defaults).selectedDestinationID == Configuration.defaultDestinationID)
}
