import ImageIO
import SwiftUI
import TimesShotCore
import UniformTypeIdentifiers

struct ComposerView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DraftEditor(text: $model.draft.text, richText: $model.draft.richText, send: model.send, discard: {
                model.discardDraft()
                model.onAccepted?()
            }, addFiles: model.addFiles, addImage: model.addImage)
            if !model.draft.images.isEmpty {
                AttachmentStrip(images: model.draft.images, remove: model.removeImage)
            }
        }
        .frame(minWidth: 460, minHeight: 240)
        .onChange(of: model.draft) { _, _ in model.changed() }
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
