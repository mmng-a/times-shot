import AppKit
import Carbon
import ImageIO
import Security
import TimesShotCore
import UniformTypeIdentifiers

struct PostingChannel: Codable, Equatable, Identifiable {
    let id: String
    var channelID: String
    var name: String

    init(id: String = UUID().uuidString, channelID: String = "", name: String = "") {
        self.id = id
        self.channelID = channelID
        self.name = name
    }

    var label: String {
        name.isEmpty ? channelID : "#" + name.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }
}

struct Configuration: Codable, Equatable {
    static let defaultDestinationID = "default"
    var channelID = ""
    var channelName = ""
    var additionalChannels: [PostingChannel] = []
    var selectedDestinationID = defaultDestinationID
    var workspace = ""
    var username = ""
    var teamID = ""
    var userID = ""
    var keyCode = UInt32(kVK_Space)
    var modifiers = UInt32(shiftKey)
    var shortcutLabel = "⇧Space"

    var channels: [PostingChannel] {
        let usual = PostingChannel(id: Self.defaultDestinationID, channelID: channelID, name: channelName)
        return (channelID.isEmpty ? [] : [usual]) + additionalChannels
    }

    var selectedChannel: PostingChannel? { channels.first { $0.id == selectedDestinationID } }
    var destination: String { selectedChannel?.label ?? "" }
    var isConfigured: Bool { selectedChannel?.channelID.isEmpty == false && !workspace.isEmpty }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case channelID, channelName, additionalChannels, selectedDestinationID
        case workspace, username, teamID, userID, keyCode, modifiers, shortcutLabel
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        channelID = try values.decode(String.self, forKey: .channelID)
        channelName = try values.decode(String.self, forKey: .channelName)
        additionalChannels = try values.decodeIfPresent([PostingChannel].self, forKey: .additionalChannels) ?? []
        selectedDestinationID = try values.decodeIfPresent(String.self, forKey: .selectedDestinationID) ?? Self.defaultDestinationID
        workspace = try values.decode(String.self, forKey: .workspace)
        username = try values.decode(String.self, forKey: .username)
        teamID = try values.decodeIfPresent(String.self, forKey: .teamID) ?? ""
        userID = try values.decodeIfPresent(String.self, forKey: .userID) ?? ""
        keyCode = try values.decode(UInt32.self, forKey: .keyCode)
        modifiers = try values.decode(UInt32.self, forKey: .modifiers)
        shortcutLabel = try values.decode(String.self, forKey: .shortcutLabel)
    }

    mutating func validateChannels() throws {
        channelID = channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        channelName = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        additionalChannels = additionalChannels.map { channel in
            var channel = channel
            channel.channelID = channel.channelID.trimmingCharacters(in: .whitespacesAndNewlines)
            channel.name = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return channel
        }
        guard channels.allSatisfy({ $0.channelID.range(of: "^[CG][A-Z0-9]+$", options: .regularExpression) != nil }) else {
            throw StorageError.message("投稿先のチャンネルを選び直してください。")
        }
        guard Set(channels.map(\.channelID)).count == channels.count else {
            throw StorageError.message("同じチャンネルが重複しています。")
        }
        guard selectedChannel != nil else { throw StorageError.message("選択中の投稿先が登録されていません。") }
    }

    mutating func removeAdditionalChannel(_ id: String) {
        additionalChannels.removeAll { $0.id == id }
        if selectedDestinationID == id { selectedDestinationID = Self.defaultDestinationID }
    }

    mutating func removeChannel(_ id: String) {
        guard id == Self.defaultDestinationID else { removeAdditionalChannel(id); return }
        if additionalChannels.isEmpty {
            channelID = ""
            channelName = ""
        } else {
            let replacement = additionalChannels.removeFirst()
            channelID = replacement.channelID
            channelName = replacement.name
            if selectedDestinationID == replacement.id { selectedDestinationID = Self.defaultDestinationID }
        }
    }

    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: "configuration"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save(defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: "configuration")
    }
}

@MainActor enum TokenStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "jp.sendocorp.TimesShot",
        kSecAttrAccount as String: "slack-oauth-credentials"
    ]

    static func read() throws -> SlackCredentials? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw StorageError.message("KeychainからSlackの認証情報を読み出せませんでした。")
        }
        return try JSONDecoder().decode(SlackCredentials.self, from: data)
    }

    static func save(_ credentials: SlackCredentials?) throws {
        guard let credentials else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw StorageError.message("Slackの認証情報を削除できませんでした。")
            }
            return
        }
        let data = try JSONEncoder().encode(credentials)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw StorageError.message("Slackの認証情報をKeychainに保存できませんでした。")
        }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw StorageError.message("Slackの認証情報をKeychainに保存できませんでした。")
        }
    }
}

enum StorageError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

/// Attachment files are immutable; saving text never rewrites image bytes.
struct DraftStorage: Sendable {
    let directory: URL
    var imagesDirectory: URL { directory.appendingPathComponent("Images", isDirectory: true) }
    private var draftURL: URL { directory.appendingPathComponent("draft.json") }

    init(directory: URL? = nil) throws {
        self.directory = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("TimesShot", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
    }

    func load() throws -> Draft {
        guard FileManager.default.fileExists(atPath: draftURL.path) else { return Draft() }
        let draft = try JSONDecoder().decode(Draft.self, from: Data(contentsOf: draftURL))
        guard draft.images.allSatisfy({
            $0.fileURL.deletingLastPathComponent().standardizedFileURL == imagesDirectory.standardizedFileURL
                && FileManager.default.fileExists(atPath: $0.fileURL.path)
        }) else { throw StorageError.message("下書きの添付画像を読み出せませんでした。") }
        return draft
    }

    func save(_ draft: Draft) throws {
        try JSONEncoder().encode(draft).write(to: draftURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: draftURL.path)
    }

    func remove(_ images: [ImageAttachment]) {
        for image in images where image.fileURL.deletingLastPathComponent().standardizedFileURL == imagesDirectory.standardizedFileURL {
            try? FileManager.default.removeItem(at: image.fileURL)
        }
    }

    func removeOrphans(keeping images: [ImageAttachment]) throws {
        let keep = Set(images.map(\.fileURL))
        for file in try FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)
        where !keep.contains(file) {
            try FileManager.default.removeItem(at: file)
        }
    }

    func importImage(data: Data, filename: String) throws -> ImageAttachment {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source),
              let type = UTType(sourceType as String),
              CGImageSourceGetStatus(source) == .statusComplete else {
            throw StorageError.message("画像を読み込めませんでした：\(filename)")
        }
        let id = UUID()
        let passthrough = [UTType.png, .jpeg, .gif, .webP].contains(type)
        let outputType: UTType = passthrough ? type : .png
        let ext = outputType.preferredFilenameExtension ?? "png"
        let base = (filename as NSString).deletingPathExtension
        let outputName = (base.isEmpty ? "image" : base) + "." + ext
        let destination = imagesDirectory.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
        if passthrough {
            try data.write(to: destination, options: .atomic)
        } else {
            guard CGImageSourceGetCount(source) == 1 else {
                throw StorageError.message("複数フレームの画像はGIF・PNG・WebP形式で添付してください：\(filename)")
            }
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw StorageError.message("画像を変換できませんでした：\(filename)")
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            CGImageDestinationAddImage(writer, image, properties)
            guard CGImageDestinationFinalize(writer) else {
                try? FileManager.default.removeItem(at: destination)
                throw StorageError.message("画像を保存できませんでした：\(filename)")
            }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return ImageAttachment(id: id, filename: outputName, fileURL: destination)
    }
}
