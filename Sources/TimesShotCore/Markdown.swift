import Foundation

/// Converts the supported Markdown subset into Slack's mrkdwn without interpreting code as formatting.
public enum SlackMarkdown {
    public static func convert(_ source: String) -> String {
        var fence: Character?
        var fenceLength = 0
        let lines = source.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let first = trimmed.first
            let count = trimmed.prefix(while: { $0 == first }).count
            if (first == "`" || first == "~"), count >= 3 {
                if fence == nil {
                    fence = first
                    fenceLength = count
                    return "```"
                }
                if fence == first, count >= fenceLength,
                   trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                    return "```"
                }
            }
            if fence != nil { return escape(line) }
            if trimmed.hasPrefix(">") {
                let indent = line.prefix(while: \.isWhitespace)
                return String(indent) + ">" + inline(String(trimmed.dropFirst()))
            }
            return inline(line)
        }
        return lines.joined(separator: "\n") + (fence == nil ? "" : "\n```")
    }

    private static func inline(_ text: String) -> String {
        guard let parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return escape(text) }
        return parsed.runs.map { run in
            var value = escape(String(parsed[run.range].characters))
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { return "`\(value)`" }
            if intent.contains(.stronglyEmphasized) { value = "*\(value)*" }
            if intent.contains(.emphasized) { value = "_\(value)_" }
            if intent.contains(.strikethrough) { value = "~\(value)~" }
            if let link = run.link, ["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                return "<\(escape(link.absoluteString))|\(value)>"
            }
            return value
        }.joined()
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
