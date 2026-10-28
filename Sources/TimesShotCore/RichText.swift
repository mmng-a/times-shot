import AppKit

/// Bridges native text formatting and Slack while retaining older Markdown drafts.
public enum RichText {
    public static var font: NSFont { .systemFont(ofSize: 15) }
    public static var codeFont: NSFont { .monospacedSystemFont(ofSize: 15, weight: .regular) }

    public static func fromMarkdown(_ source: String) -> AttributedString {
        let output = NSMutableAttributedString(string: "")
        var fence: Character?
        var fenceLength = 0
        var codeLines: [String] = []
        var firstLine = true
        func append(_ value: NSAttributedString) {
            if !firstLine { output.append(NSAttributedString(string: "\n", attributes: [.font: font])) }
            firstLine = false
            output.append(value)
        }
        func appendCode() {
            var value = AttributedString(NSAttributedString(string: codeLines.joined(separator: "\n"), attributes: [.font: codeFont]))
            value.presentationIntent = PresentationIntent(.codeBlock(languageHint: nil), identity: output.length + 1)
            append(NSAttributedString(value))
            codeLines = []
        }
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let character = trimmed.first
            let count = trimmed.prefix(while: { $0 == character }).count
            if (character == "`" || character == "~"), count >= 3 {
                if fence == nil {
                    fence = character
                    fenceLength = count
                    continue
                }
                if fence == character, count >= fenceLength, trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty {
                    appendCode()
                    fence = nil
                    continue
                }
            }
            if fence != nil {
                codeLines.append(line)
                continue
            }
            let rendered = NSMutableAttributedString(string: "")
            // Existing drafts use Markdown; new edits retain native attributes instead.
            let parsed = (try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(line)
            for run in parsed.runs {
                let intent = run.inlinePresentationIntent ?? []
                var traits: NSFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                let displayFont = intent.contains(.code) ? codeFont
                    : NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
                var attributes: [NSAttributedString.Key: Any] = [.font: displayFont, .foregroundColor: NSColor.textColor]
                if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let link = run.link { attributes[.link] = link }
                rendered.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
            }
            append(rendered)
        }
        if fence != nil { appendCode() }
        return AttributedString(output)
    }

    /// Serializes visible formatting without parsing typed Markdown punctuation.
    public static func slackText(_ text: AttributedString) -> String {
        guard !text.characters.isEmpty else { return "" }
        let source = NSAttributedString(text)
        var segments: [(text: String, markers: [Marker])] = []
        var offset = 0
        for run in text.runs {
            var value = String(text[run.range].characters)
            let attributes = source.attributes(at: offset, effectiveRange: nil)
            offset += (value as NSString).length
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle, !style.textLists.isEmpty {
                value = value.replacingOccurrences(of: "•\t", with: "• ")
            }
            let font = attributes[.font] as? NSFont ?? Self.font
            let traits = font.fontDescriptor.symbolicTraits
            var markers: [Marker] = []
            if traits.contains(.monoSpace) {
                let block = run.presentationIntent?.components.contains { if case .codeBlock = $0.kind { true } else { false } } == true
                markers = [Marker(open: block ? "```" : "`", close: block ? "```" : "`")]
            } else {
                if let value = attributes[.link], let url = (value as? URL) ?? URL(string: String(describing: value)),
                   ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    markers.append(Marker(open: "<\(escape(url.absoluteString))|", close: ">"))
                }
                if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { markers.append(Marker(open: "~", close: "~")) }
                if traits.contains(.bold) { markers.append(Marker(open: "*", close: "*")) }
                if traits.contains(.italic) { markers.append(Marker(open: "_", close: "_")) }
            }
            if segments.last?.markers == markers {
                segments[segments.count - 1].text += value
            } else { segments.append((value, markers)) }
        }
        var output = ""
        var active: [Marker] = []
        func transition(to markers: [Marker]) {
            let common = zip(active, markers).prefix(while: { $0 == $1 }).count
            for marker in active.dropFirst(common).reversed() { output += marker.close }
            for marker in markers.dropFirst(common) { output += marker.open }
            active = markers
        }
        for segment in segments {
            let code = segment.markers == [Marker(open: "`", close: "`")]
            let block = segment.markers == [Marker(open: "```", close: "```")]
            if block || (code && segment.text.contains("\n")) {
                transition(to: [])
                var content = segment.text
                if code, content.hasPrefix("\n") {
                    output += "\n"
                    content.removeFirst()
                }
                let trailingNewline = code && content.hasSuffix("\n")
                if trailingNewline { content.removeLast() }
                if !output.isEmpty, !output.hasSuffix("\n") { output += "\n" }
                output += "```\n" + escape(content)
                if !content.hasSuffix("\n") { output += "\n" }
                output += "```"
                if trailingNewline { output += "\n" }
                continue
            }
            let lines = segment.text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                if index > 0 {
                    transition(to: [])
                    output += "\n"
                }
                guard !line.isEmpty else { continue }
                let leading = String(line.prefix(while: \.isWhitespace))
                let remainder = String(line.dropFirst(leading.count))
                let trailing = String(remainder.reversed().prefix(while: \.isWhitespace).reversed())
                let content = String(remainder.dropLast(trailing.count))
                if !leading.isEmpty { transition(to: []); output += leading }
                transition(to: content.isEmpty ? [] : segment.markers)
                if active.isEmpty, (output.isEmpty || output.hasSuffix("\n")), content.hasPrefix(">") {
                    output += ">" + escape(String(content.dropFirst()))
                } else { output += escape(content) }
                if !trailing.isEmpty { transition(to: []); output += trailing }
            }
        }
        transition(to: [])
        return output
    }

    private struct Marker: Equatable {
        let open: String
        let close: String
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
