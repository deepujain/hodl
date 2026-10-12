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

/// Hold the Door Lid, literally: a rubber doorstop wedged under a MacBook lid, light still on inside.
struct AppIconArtwork: View {
    private let shape = RoundedRectangle(cornerRadius: 186, style: .continuous)

    var body: some View {
        ZStack {
            shape
                .fill(LinearGradient(colors: [Color(red: 0.31, green: 0.43, blue: 1.0), Color(red: 0.50, green: 0.30, blue: 0.92)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay { IconMark().clipShape(shape) }
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 22, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// The icon’s foreground in its 824-point space: moon, laptop, and doorstop. Marketing scenes reuse it.
struct IconMark: View {
    private let moonLight = Color(red: 1.0, green: 0.94, blue: 0.80)
    private let screenLight = Color(red: 0.80, green: 0.92, blue: 1.0)
    private let aluminum = LinearGradient(colors: [Color(white: 0.98), Color(white: 0.76)], startPoint: .top, endPoint: .bottom)
    private let rubber = LinearGradient(colors: [Color(red: 1.0, green: 0.66, blue: 0.24), Color(red: 0.94, green: 0.38, blue: 0.10)],
                                        startPoint: .top, endPoint: .bottom)

    private let hinge = CGPoint(x: 96, y: 590)
    private let length: CGFloat = 590
    private let angle = Angle.degrees(-14)
    /// Where the doorstop starts under the lid, and how far it sticks out past the front.
    private let wedgeStart: CGFloat = 340
    private let wedgeEnd: CGFloat = 712

    private var lift: CGFloat { length * CGFloat(sin(-angle.radians)) }
    private var reach: CGFloat { length * CGFloat(cos(angle.radians)) }
    private var lidFront: CGPoint { CGPoint(x: hinge.x + reach, y: hinge.y - lift) }

    var body: some View {
        ZStack {
            ForEach(Array([(560.0, 120.0, 9.0), (680, 210, 7), (470, 250, 6), (130, 330, 6)].enumerated()), id: \.offset) { _, star in
                Circle().fill(.white.opacity(0.8)).frame(width: star.2, height: star.2).position(x: star.0, y: star.1)
            }
            moon.position(x: 230, y: 230)

            // Soft shadow on the desk.
            Ellipse().fill(.black.opacity(0.28)).frame(width: 640, height: 50).blur(radius: 18)
                .position(x: hinge.x + length / 2 + 30, y: hinge.y + 52)
            // Screen light in the gap, behind the doorstop.
            gap
                .fill(LinearGradient(colors: [screenLight.opacity(0.2), screenLight, .white], startPoint: .leading, endPoint: .trailing))
                .shadow(color: screenLight.opacity(0.9), radius: 30)
            doorstop
            // Lid, resting on the doorstop.
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(aluminum)
                .frame(width: length, height: 26)
                .overlay(alignment: .top) { Capsule().fill(.white).frame(height: 2).padding(.horizontal, 14).padding(.top, 1) }
                .rotationEffect(angle, anchor: .bottomLeading)
                .position(x: hinge.x + length / 2, y: hinge.y - 13)
            // Base.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(aluminum)
                .frame(width: length + 12, height: 40)
                .overlay(alignment: .bottom) { Capsule().fill(Color(white: 0.55)).frame(width: length - 80, height: 4).offset(y: 3) }
                .position(x: hinge.x + length / 2 + 6, y: hinge.y + 20)
        }
    }

    private var moon: some View {
        Circle()
            .fill(LinearGradient(colors: [.white, moonLight], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 190, height: 190)
            .mask {
                ZStack {
                    Rectangle()
                    Circle().frame(width: 170, height: 170).offset(x: 62, y: -42).blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .shadow(color: moonLight.opacity(0.5), radius: 30)
    }

    /// Between the lid’s underside and the base: nothing at the hinge, open at the front.
    private var gap: Path {
        var path = Path()
        path.move(to: CGPoint(x: hinge.x + 8, y: hinge.y))
        path.addLine(to: CGPoint(x: lidFront.x - 4, y: lidFront.y + 4))
        path.addLine(to: CGPoint(x: lidFront.x - 4, y: hinge.y))
        path.closeSubpath()
        return path
    }

    /// A rubber wedge on the base whose slope meets the lid’s front edge, so the lid rests on it.
    private var doorstop: some View {
        let rise = (hinge.y - lidFront.y + 8) / (lidFront.x - wedgeStart)
        let height = (wedgeEnd - wedgeStart) * rise
        let wedge = Path { path in
            path.move(to: CGPoint(x: wedgeStart, y: hinge.y))
            path.addLine(to: CGPoint(x: wedgeEnd - 14, y: hinge.y - height + 6))
            path.addQuadCurve(to: CGPoint(x: wedgeEnd, y: hinge.y - height + 22), control: CGPoint(x: wedgeEnd, y: hinge.y - height))
            path.addLine(to: CGPoint(x: wedgeEnd, y: hinge.y))
            path.closeSubpath()
        }
        return wedge.fill(rubber)
            .overlay {
                Path { path in
                    path.move(to: CGPoint(x: wedgeStart + 30, y: hinge.y - 4))
                    path.addLine(to: CGPoint(x: wedgeEnd - 18, y: hinge.y - height + 14))
                }
                .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
    }
}
