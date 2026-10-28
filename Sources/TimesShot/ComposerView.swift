import ImageIO
import SwiftUI
import TimesShotCore
import UniformTypeIdentifiers

struct ComposerView: View {
    @Bindable var model: AppModel
    let settings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerHeader(configuration: model.configuration, settings: settings)
            Divider()
            DraftEditor(text: $model.draft.text, send: model.send, discard: {
                model.discardDraft()
                model.onAccepted?()
            }, addFiles: model.addFiles, addImage: model.addImage)
            .padding(.horizontal, 14)
            if !model.draft.images.isEmpty {
                AttachmentStrip(images: model.draft.images, remove: model.removeImage)
            }
            Divider()
            ComposerFooter(canSend: model.canSend, importing: model.importing,
                           chooseFiles: chooseFiles, send: model.send)
        }
        .frame(minWidth: 460, minHeight: 270)
        .onChange(of: model.draft) { _, _ in model.changed() }
    }

    private func chooseFiles() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.image]
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.prompt = "添付"
        guard let window = NSApp.keyWindow else { return }
        picker.beginSheetModal(for: window) { response in
            if response == .OK { model.addFiles(picker.urls) }
        }
    }
}

private struct ComposerHeader: View {
    let configuration: Configuration
    let settings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "number").foregroundStyle(.secondary)
            if configuration.isConfigured {
                Text(configuration.destination).fontWeight(.semibold)
                Text(configuration.workspace).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("投稿先を設定してください").foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: settings) { Image(systemName: "gearshape") }
                .buttonStyle(.plain).help("設定")
                .accessibilityLabel("設定を開く")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }
}

private struct ComposerFooter: View {
    let canSend: Bool
    let importing: Bool
    let chooseFiles: () -> Void
    let send: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: chooseFiles) { Image(systemName: "photo.badge.plus") }
                .buttonStyle(.plain).help("画像を添付")
                .accessibilityLabel("画像を添付")
                .disabled(importing)
            Text(importing ? "画像を読み込み中…" : "Escで破棄 · ⌘Wで保存")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("送信 ⌘↵", action: send).buttonStyle(.borderedProminent).disabled(!canSend)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }
}

private struct AttachmentStrip: View {
    let images: [ImageAttachment]
    let remove: (ImageAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(images) { image in
                    AttachmentThumbnail(image: image, remove: { remove(image) })
                }
            }.padding(12)
        }
        .frame(height: 100)
    }
}

private struct AttachmentThumbnail: View {
    let image: ImageAttachment
    let remove: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 90, height: 72)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Button(action: remove) { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7)) }
                .buttonStyle(.plain)
                .accessibilityLabel("\(image.filename)を削除")
                .offset(x: 5, y: -5)
        }
        .help(image.filename)
        .task(id: image.id) {
            let url = image.fileURL
            let cgImage = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 180
                ] as CFDictionary)
            }.value
            if let cgImage { thumbnail = NSImage(cgImage: cgImage, size: .zero) }
        }
    }
}
