import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make_app_icon.swift <output-iconset>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputURL,
    withIntermediateDirectories: true
)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(pixels: Int) throws -> Data {
    let size = CGFloat(pixels)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let inset = size * 0.08
    let tileRect = CGRect(
        x: inset,
        y: inset,
        width: size - inset * 2,
        height: size - inset * 2
    )
    let tilePath = CGPath(
        roundedRect: tileRect,
        cornerWidth: size * 0.21,
        cornerHeight: size * 0.21,
        transform: nil
    )
    context.addPath(tilePath)
    context.setFillColor(
        red: 0.94,
        green: 0.96,
        blue: 0.97,
        alpha: 1
    )
    context.fillPath()

    context.addPath(tilePath)
    context.setStrokeColor(
        red: 0.76,
        green: 0.82,
        blue: 0.86,
        alpha: 1
    )
    context.setLineWidth(max(size * 0.008, 1))
    context.strokePath()

    let pages: [(CGRect, (CGFloat, CGFloat, CGFloat))] = [
        (
            CGRect(
                x: size * 0.24,
                y: size * 0.46,
                width: size * 0.52,
                height: size * 0.27
            ),
            (0.92, 0.95, 0.97)
        ),
        (
            CGRect(
                x: size * 0.20,
                y: size * 0.31,
                width: size * 0.60,
                height: size * 0.29
            ),
            (0.09, 0.45, 0.66)
        ),
        (
            CGRect(
                x: size * 0.16,
                y: size * 0.16,
                width: size * 0.68,
                height: size * 0.30
            ),
            (0.18, 0.61, 0.50)
        )
    ]

    for (rect, color) in pages {
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: size * 0.045,
            cornerHeight: size * 0.045,
            transform: nil
        )
        context.addPath(path)
        context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        context.fillPath()
    }

    let accentRect = CGRect(
        x: size * 0.20,
        y: size * 0.24,
        width: size * 0.60,
        height: size * 0.035
    )
    let accentPath = CGPath(
        roundedRect: accentRect,
        cornerWidth: size * 0.018,
        cornerHeight: size * 0.018,
        transform: nil
    )
    context.addPath(accentPath)
    context.setFillColor(red: 0.93, green: 0.57, blue: 0.18, alpha: 1)
    context.fillPath()

    guard let image = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }

    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }

    return data
}

for variant in variants {
    let data = try drawIcon(pixels: variant.pixels)
    try data.write(to: outputURL.appendingPathComponent(variant.name))
}
