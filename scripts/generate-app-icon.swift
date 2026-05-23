#!/usr/bin/env swift
import AppKit

let resourcesDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Windburst/Resources"

let iconsetDir = (resourcesDir as NSString).appendingPathComponent("AppIcon.iconset")
let icnsPath = (resourcesDir as NSString).appendingPathComponent("AppIcon.icns")

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func renderIcon(pixels: Int) throws -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "generate-app-icon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to create bitmap"
        ])
    }

    if let data = rep.bitmapData {
        let pixelCount = rep.pixelsWide * rep.pixelsHigh
        for index in 0..<pixelCount {
            let offset = index * 4
            data[offset] = 255
            data[offset + 1] = 255
            data[offset + 2] = 255
            data[offset + 3] = 255
        }
    }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "generate-app-icon", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Failed to create graphics context"
        ])
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let dimension = CGFloat(pixels)
    let bleed = dimension * 0.04
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(
        x: -bleed,
        y: -bleed,
        width: dimension + (2 * bleed),
        height: dimension + (2 * bleed)
    )).fill()

    let symbolSize = dimension * 0.58
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.black]))

    guard let symbol = NSImage(systemSymbolName: "wind", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        throw NSError(domain: "generate-app-icon", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Failed to load wind symbol"
        ])
    }

    let symbolWidth = symbol.size.width
    let symbolHeight = symbol.size.height
    let x = (dimension - symbolWidth) / 2
    let y = (dimension - symbolHeight) / 2
    symbol.draw(in: NSRect(x: x, y: y, width: symbolWidth, height: symbolHeight))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "generate-app-icon", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Failed to encode PNG for \(path)"
        ])
    }
    try png.write(to: URL(fileURLWithPath: path))
}

let iconsetContents = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""

let fileManager = FileManager.default
try fileManager.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
try iconsetContents.write(toFile: (iconsetDir as NSString).appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

for entry in sizes {
    let rep = try renderIcon(pixels: entry.pixels)
    let path = (iconsetDir as NSString).appendingPathComponent(entry.name)
    try savePNG(rep, to: path)
    print("Wrote \(path)")
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil failed with status \(iconutil.terminationStatus)\n", stderr)
    exit(1)
}
print("Wrote \(icnsPath)")
