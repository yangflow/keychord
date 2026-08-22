#!/usr/bin/env swift
//
// generate-icon.swift — Slice AppIcon sizes from scripts/appicon-master.png.
//
// Run:
//     swift scripts/generate-icon.swift
//
// Writes 10 PNG files into keychord/Assets.xcassets/AppIcon.appiconset/

import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let masterURL = repoRoot.appendingPathComponent("scripts/appicon-master.png")
let assetPath = repoRoot.appendingPathComponent("keychord/Assets.xcassets/AppIcon.appiconset")

let sizes: [(filename: String, pixels: Int)] = [
    ("icon_16.png",        16),
    ("icon_16@2x.png",     32),
    ("icon_32.png",        32),
    ("icon_32@2x.png",     64),
    ("icon_128.png",      128),
    ("icon_128@2x.png",   256),
    ("icon_256.png",      256),
    ("icon_256@2x.png",   512),
    ("icon_512.png",      512),
    ("icon_512@2x.png",  1024),
]

guard let master = NSImage(contentsOf: masterURL) else {
    fputs("missing \(masterURL.path)\n", stderr)
    exit(1)
}

func png(of image: NSImage, pixels: Int) -> Data? {
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
    ) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    return rep.representation(using: .png, properties: [:])
}

for (filename, px) in sizes {
    guard let data = png(of: master, pixels: px) else {
        fputs("failed to encode \(filename)\n", stderr)
        continue
    }
    let url = assetPath.appendingPathComponent(filename)
    try data.write(to: url)
    print("  \(filename.padding(toLength: 20, withPad: " ", startingAt: 0))  \(px)×\(px)")
}

print("")
print("Wrote \(sizes.count) icon PNGs from \(masterURL.lastPathComponent)")
