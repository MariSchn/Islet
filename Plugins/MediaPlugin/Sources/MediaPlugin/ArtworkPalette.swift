import AppKit
import SwiftUI

struct Artwork: Sendable {
    static let thumbnailSide = 320

    let image: CGImage
    let tint: Color.Resolved

    init?(data: Data) {
        guard let source = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let image = Self.render(source, side: Self.thumbnailSide),
              let dominant = Self.dominantColor(of: source) else { return nil }
        self.image = image
        tint = Self.legible(dominant)
    }

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private static func render(_ image: CGImage, side: Int) -> CGImage? {
        guard image.width > 0, image.height > 0, let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        let scale = CGFloat(side) / CGFloat(min(image.width, image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.draw(image, in: CGRect(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2, width: size.width, height: size.height))
        return context.makeImage()
    }

    private static func dominantColor(of image: CGImage) -> NSColor? {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        var buckets: [Int: (weight: Double, red: Double, green: Double, blue: Double, count: Double)] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let brightness = max(red, green, blue)
            let saturation = brightness > 0 ? (brightness - min(red, green, blue)) / brightness : 0
            let weight = 0.1 + saturation * brightness
            let key = (Int(red * 7) << 6) | (Int(green * 7) << 3) | Int(blue * 7)
            var bucket = buckets[key] ?? (0, 0, 0, 0, 0)
            bucket.weight += weight
            bucket.red += red
            bucket.green += green
            bucket.blue += blue
            bucket.count += 1
            buckets[key] = bucket
        }
        guard let best = buckets.values.max(by: { $0.weight < $1.weight }) else { return nil }
        return NSColor(red: best.red / best.count, green: best.green / best.count, blue: best.blue / best.count, alpha: 1)
    }

    private static func legible(_ color: NSColor) -> Color.Resolved {
        let adjusted = NSColor(
            hue: color.hueComponent,
            saturation: min(color.saturationComponent, 0.8),
            brightness: max(color.brightnessComponent, 0.8),
            alpha: 1
        )
        return Color.Resolved(red: Float(adjusted.redComponent), green: Float(adjusted.greenComponent), blue: Float(adjusted.blueComponent))
    }
}
