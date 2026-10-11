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

/// Night, a crescent moon, and a MacBook in profile with its lid held open a crack, light still on inside.
struct AppIconArtwork: View {
    private let shape = RoundedRectangle(cornerRadius: 186, style: .continuous)

    var body: some View {
        ZStack {
            shape
                .fill(LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.24), Color(red: 0.20, green: 0.16, blue: 0.46)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay { NightMark().clipShape(shape) }
                .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 22, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

private struct NightMark: View {
    private let moonLight = Color(red: 1.0, green: 0.93, blue: 0.76)
    private let glow = Color(red: 0.45, green: 0.98, blue: 0.80)
    private let aluminum = LinearGradient(colors: [Color(white: 0.96), Color(white: 0.72)], startPoint: .top, endPoint: .bottom)

    // Side view of the laptop, in the 824-point icon space.
    private let hinge = CGPoint(x: 132, y: 586)
    private let length: CGFloat = 560
    private let angle = Angle.degrees(-8)

    var body: some View {
        ZStack {
            ForEach(Array([(150.0, 160.0, 9.0), (250, 300, 6), (330, 120, 7), (700, 440, 6), (170, 450, 5), (640, 150, 5)].enumerated()), id: \.offset) { _, star in
                Circle().fill(.white.opacity(0.75)).frame(width: star.2, height: star.2).position(x: star.0, y: star.1)
            }
            Circle()
                .fill(RadialGradient(colors: [moonLight.opacity(0.16), moonLight.opacity(0)], center: .center, startRadius: 80, endRadius: 260))
                .frame(width: 520, height: 520)
                .position(x: 470, y: 280)
            Circle()
                .fill(LinearGradient(colors: [.white, moonLight], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 280, height: 280)
                .mask {
                    ZStack {
                        Rectangle()
                        Circle().frame(width: 250, height: 250).offset(x: 92, y: -62).blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .position(x: 450, y: 280)

            // Light from the open crack, falling forward.
            Ellipse()
                .fill(RadialGradient(colors: [glow.opacity(0.32), glow.opacity(0)], center: .center, startRadius: 2, endRadius: 150))
                .frame(width: 300, height: 70)
                .blur(radius: 10)
                .position(x: hinge.x + length + 10, y: hinge.y + 40)
            gap
                .fill(LinearGradient(colors: [glow.opacity(0.15), glow, .white], startPoint: .leading, endPoint: .trailing))
                .shadow(color: glow.opacity(0.9), radius: 26)
            // Lid, pivoting on the hinge.
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(aluminum)
                .frame(width: length, height: 26)
                .overlay(alignment: .top) { Capsule().fill(.white).frame(height: 2).padding(.horizontal, 14).padding(.top, 1) }
                .rotationEffect(angle, anchor: .bottomLeading)
                .position(x: hinge.x + length / 2, y: hinge.y - 13)
            // Base.
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(aluminum)
                .frame(width: length + 8, height: 36)
                .overlay(alignment: .bottom) { Capsule().fill(Color(white: 0.5)).frame(width: length - 70, height: 4).offset(y: 3) }
                .shadow(color: .black.opacity(0.45), radius: 18, y: 12)
                .position(x: hinge.x + length / 2, y: hinge.y + 18)
        }
    }

    /// Between the lid’s underside and the base: nothing at the hinge, wide open at the front.
    private var gap: Path {
        let lift = length * CGFloat(sin(-angle.radians))
        let reach = length * CGFloat(cos(angle.radians))
        var path = Path()
        path.move(to: CGPoint(x: hinge.x + 6, y: hinge.y))
        path.addLine(to: CGPoint(x: hinge.x + reach - 4, y: hinge.y - lift + 3))
        path.addLine(to: CGPoint(x: hinge.x + reach - 4, y: hinge.y))
        path.closeSubpath()
        return path
    }
}
