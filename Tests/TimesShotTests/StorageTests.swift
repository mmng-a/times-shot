import CoreGraphics
import Foundation
import ImageIO
import Testing
import TimesShotCore
import UniformTypeIdentifiers
@testable import TimesShot

private func sampleImage(type: UTType, frames: Int = 1) throws -> Data {
    let bytes: [UInt8] = [255, 0, 0, 128]
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, frames, nil))
    for _ in 0..<frames { CGImageDestinationAddImage(destination, image, nil) }
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

@Test func draftSurvivesRestartWithoutOriginalImageAndDiscardRemovesIt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try DraftStorage(directory: directory)
    let bytes = try sampleImage(type: .png)
    let attachment = try storage.importImage(data: bytes, filename: "screen.png")
    let draft = Draft(text: "書きかけ", images: [attachment])
    try storage.save(draft)
    let reloaded = try DraftStorage(directory: directory).load()
    #expect(reloaded == draft)
    #expect(try Data(contentsOf: reloaded.images[0].fileURL) == bytes)
    try storage.save(Draft())
    try storage.removeOrphans(keeping: [])
    #expect(!FileManager.default.fileExists(atPath: attachment.fileURL.path))
    #expect(try storage.load().isEmpty)
}

@Test func tiffConvertsToPNGAndAnimatedGIFKeepsFrames() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try DraftStorage(directory: directory)
    let converted = try storage.importImage(data: sampleImage(type: .tiff), filename: "photo.tiff")
    #expect(converted.filename == "photo.png")
    let source = try #require(CGImageSourceCreateWithURL(converted.fileURL as CFURL, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    let originalGIF = try sampleImage(type: .gif, frames: 2)
    let animated = try storage.importImage(data: originalGIF, filename: "animation.gif")
    #expect(try Data(contentsOf: animated.fileURL) == originalGIF)
    let animatedSource = try #require(CGImageSourceCreateWithURL(animated.fileURL as CFURL, nil))
    #expect(CGImageSourceGetCount(animatedSource) == 2)
}

@Test func nonImageCannotBeAttached() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try DraftStorage(directory: directory)
    #expect(throws: (any Error).self) { try storage.importImage(data: Data("text".utf8), filename: "fake.png") }
}
