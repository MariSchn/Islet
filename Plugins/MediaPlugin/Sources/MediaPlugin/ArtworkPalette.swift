import AppKit
import IsletCore

enum ArtworkPalette {
    static func tint(for data: Data) -> PillTint? {
        guard let image = NSImage(data: data), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return dominantColor(of: cgImage).map(legible)
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
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        var buckets: [Int: (weight: Double, red: Double, green: Double, blue: Double, count: Double)] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let color = NSColor(red: red, green: green, blue: blue, alpha: 1)
            let weight = 0.1 + color.saturationComponent * color.brightnessComponent
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

    private static func legible(_ color: NSColor) -> PillTint {
        let adjusted = NSColor(
            hue: color.hueComponent,
            saturation: min(color.saturationComponent, 0.8),
            brightness: max(color.brightnessComponent, 0.8),
            alpha: 1
        )
        return PillTint(red: adjusted.redComponent, green: adjusted.greenComponent, blue: adjusted.blueComponent)
    }
}
