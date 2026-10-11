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

/// The overnight desk: a closed MacBook under a desk lamp, with a small "Holding" pill floating above it.
struct AppIconArtwork: View {
    var showsPill = true
    private let shape = RoundedRectangle(cornerRadius: 186, style: .continuous)

    var body: some View {
        ZStack {
            shape
                .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.20), Color(red: 0.16, green: 0.18, blue: 0.32)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay { DeskScene(showsPill: showsPill).clipShape(shape) }
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 22, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

private struct DeskScene: View {
    let showsPill: Bool
    private let warm = Color(red: 1.0, green: 0.82, blue: 0.52)

    var body: some View {
        ZStack {
            // A few stars through the window.
            ForEach(Array([(150.0, 140.0, 7.0), (260, 90, 5), (640, 120, 6), (700, 210, 4), (560, 70, 4)].enumerated()), id: \.offset) { _, star in
                Circle().fill(.white.opacity(0.7)).frame(width: star.2, height: star.2).position(x: star.0, y: star.1)
            }
            // Lamp light pooling on the desk.
            Ellipse()
                .fill(RadialGradient(colors: [warm.opacity(0.55), warm.opacity(0)], center: .center, startRadius: 10, endRadius: 330))
                .frame(width: 700, height: 300)
                .position(x: 430, y: 610)
            // Desk.
            Rectangle()
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.26, blue: 0.20), Color(red: 0.22, green: 0.15, blue: 0.12)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 210)
                .position(x: 412, y: 719)
            Rectangle().fill(warm.opacity(0.35)).frame(width: 824, height: 4).position(x: 412, y: 616)
            lamp
            laptop
            if showsPill { pill.position(x: 370, y: 262) }
        }
        .frame(width: 824, height: 824)
    }

    private var laptop: some View {
        ZStack {
            // Lid, seen nearly edge-on.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.4))
                .frame(width: 452, height: 40)
                .offset(y: 2)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.66)], startPoint: .top, endPoint: .bottom))
                .frame(width: 440, height: 34)
                .offset(y: -6)
            Capsule().fill(Color(white: 0.45)).frame(width: 80, height: 6).offset(y: 14)
            // A soft glow on the lid where the lamp hits it.
            Capsule().fill(warm.opacity(0.35)).frame(width: 200, height: 8).blur(radius: 6).offset(x: -60, y: -16)
        }
        .shadow(color: .black.opacity(0.45), radius: 14, y: 10)
        .position(x: 440, y: 590)
    }

    private var lamp: some View {
        let metal = LinearGradient(colors: [Color(white: 0.5), Color(white: 0.28)], startPoint: .top, endPoint: .bottom)
        return ZStack {
            // Light spilling from the shade.
            Ellipse().fill(warm.opacity(0.8)).frame(width: 70, height: 26).blur(radius: 14)
                .rotationEffect(.degrees(-24)).position(x: 572, y: 452)
            // Arm: base, elbow, and shade joined in one stroke.
            Path { path in
                path.move(to: CGPoint(x: 680, y: 600))
                path.addLine(to: CGPoint(x: 712, y: 430))
                path.addLine(to: CGPoint(x: 612, y: 372))
            }
            .stroke(metal, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
            Circle().fill(Color(white: 0.36)).frame(width: 24, height: 24).position(x: 712, y: 430)
            // Shade, tipped down toward the laptop.
            Path { path in
                path.move(to: CGPoint(x: 596, y: 352))
                path.addLine(to: CGPoint(x: 640, y: 386))
                path.addLine(to: CGPoint(x: 600, y: 452))
                path.addQuadCurve(to: CGPoint(x: 530, y: 404), control: CGPoint(x: 548, y: 452))
                path.closeSubpath()
            }
            .fill(metal)
            Capsule().fill(warm).frame(width: 64, height: 12).blur(radius: 3)
                .rotationEffect(.degrees(-56)).position(x: 566, y: 430)
            Ellipse().fill(Color(white: 0.22)).frame(width: 128, height: 26).position(x: 680, y: 610)
        }
    }

    private var pill: some View {
        HStack(spacing: 18) {
            Circle().fill(Color(red: 0.3, green: 0.85, blue: 0.5)).frame(width: 28, height: 28)
            Text(verbatim: "Holding · 4 agents")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 22)
        .background(.white.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 2))
    }
}
