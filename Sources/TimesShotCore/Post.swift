import Foundation

public struct ImageAttachment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let filename: String
    public let fileURL: URL

    public init(id: UUID = UUID(), filename: String, fileURL: URL) {
        self.id = id
        self.filename = filename
        self.fileURL = fileURL
    }
}

public struct Draft: Codable, Equatable, Sendable {
    public var text: String
    public var images: [ImageAttachment]
    public var richText: AttributedString?

    public init(text: String = "", images: [ImageAttachment] = [], richText: AttributedString? = nil) {
        self.text = text
        self.images = images
        self.richText = richText
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty
    }

    public var notificationSummary: String {
        let excerpt = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let description = excerpt.isEmpty ? "" : "「\(excerpt.prefix(140))\(excerpt.count > 140 ? "…" : "")」"
        let attachments = images.isEmpty ? "" : "画像\(images.count)枚：\(images.map(\.filename).joined(separator: "、"))"
        return [description, attachments].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public struct PendingPost: Identifiable, Sendable {
    public let id: UUID
    public let draft: Draft
    public let channelID: String
    public let connectionID: UUID

    public init(draft: Draft, channelID: String, connectionID: UUID) {
        self.id = UUID()
        self.draft = draft
        self.channelID = channelID
        self.connectionID = connectionID
    }
}

public enum DeliveryError: Error, LocalizedError, Sendable {
    case rejected(String)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .rejected(let message): message
        case .unknown: "投稿結果を確認できませんでした。Slackに投稿されている可能性があります。"
        }
    }
}
