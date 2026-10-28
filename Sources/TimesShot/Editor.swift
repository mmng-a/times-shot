import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DraftEditor: NSViewRepresentable {
    @Binding var text: String
    let send: () -> Void
    let discard: () -> Void
    let addFiles: ([URL]) -> Void
    let addImage: (Data, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = PostingTextView()
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.font = .systemFont(ofSize: 15)
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 4, height: 10)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.registerForDraggedTypes([.fileURL, .png, .tiff])
        editor.string = text
        editor.send = send
        editor.discard = discard
        editor.addFiles = addFiles
        editor.addImage = addImage
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PostingTextView else { return }
        if editor.string != text, !editor.hasMarkedText() {
            editor.string = text
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            editor.undoManager?.removeAllActions()
        }
        editor.send = send
        editor.discard = discard
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DraftEditor
        init(_ parent: DraftEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

final class PostingTextView: NSTextView {
    var send: (() -> Void)?
    var discard: (() -> Void)?
    var addFiles: (([URL]) -> Void)?
    var addImage: ((Data, String) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 36, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            if hasMarkedText() { return super.performKeyEquivalent(with: event) }
            send?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() {
            unmarkText()
            inputContext?.discardMarkedText()
        } else { discard?() }
    }

    override func paste(_ sender: Any?) {
        if !acceptImages(from: .general) { super.pasteAsPlainText(sender) }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canAcceptImages(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        acceptImages(from: sender.draggingPasteboard)
    }

    private func canAcceptImages(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.availableType(from: [.png, .tiff, NSPasteboard.PasteboardType("com.compuserve.gif"),
                                              NSPasteboard.PasteboardType("org.webmproject.webp")]) != nil
    }

    private func acceptImages(from pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            addFiles?(urls)
            return true
        }
        for (type, filename) in [
            (NSPasteboard.PasteboardType("com.compuserve.gif"), "clipboard.gif"),
            (NSPasteboard.PasteboardType("org.webmproject.webp"), "clipboard.webp"),
            (.png, "clipboard.png"), (.tiff, "clipboard.tiff")
        ] {
            if let data = pasteboard.data(forType: type) {
                addImage?(data, filename)
                return true
            }
        }
        return false
    }
}
