import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the app icon artwork into an `.iconset` folder for `iconutil`.
@MainActor
enum AppIconRenderer {
    static func writeIconset(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: AppIconArtwork())
        renderer.scale = 1
        guard let master = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let sizes: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, pixels) in sizes {
            guard let image = resize(master, to: pixels),
                  let destination = CGImageDestinationCreateWithURL(folder.appending(path: "\(name).png") as CFURL,
                                                                    UTType.png.identifier as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }

    private static func resize(_ image: CGImage, to pixels: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }
}

/// The icon photo ships in `Contents/Resources`. The rest are website-only and load from the repository.
enum Photo: String {
    case icon = "Resources/IconPhoto"
    case hero = "docs/photos/hero"
    case evening = "docs/photos/evening"
    case sunrise = "docs/photos/sunrise"
    case detail = "docs/photos/detail"

    var image: Image {
        let name = URL(fileURLWithPath: rawValue).lastPathComponent
        let url = Bundle.main.url(forResource: name, withExtension: "jpg")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "\(rawValue).jpg")
        return NSImage(contentsOf: url).map { Image(nsImage: $0) } ?? Image(systemName: "laptopcomputer")
    }
}

/// A MacBook at night, lid closed, screen light still glowing from the gap.
struct AppIconArtwork: View {
    private let shape = RoundedRectangle(cornerRadius: 186, style: .continuous)

    var body: some View {
        ZStack {
            Photo.icon.image
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 824, height: 824)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 22, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}
